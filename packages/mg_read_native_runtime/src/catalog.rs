//! Native-only immutable installations and atomic catalog. The catalog owns state;
//! pending removal/version changes are committed only before libraries are loaded.
//! A same-version platform subset may be reimported when its binary hash and
//! metadata match; the installed portable archive remains unchanged.
use crate::error::{Error, Result, invalid};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, HashSet},
    fs,
    io::{Cursor, Read, Write},
    path::{Component, Path, PathBuf},
};

pub const MAX_ARCHIVE: usize = 64 * 1024 * 1024;
const SUPPORTED_TARGETS: &[&str] = &[
    "windows-x86_64",
    "android-arm64-v8a",
    "android-x86_64",
    "ohos-arm64",
    "ohos-x86_64",
];
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Target {
    pub path: String,
    pub sha256: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub format: String,
    pub engine: String,
    pub abi: u32,
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub content_kinds: Vec<String>,
    pub capabilities: Vec<String>,
    pub targets: BTreeMap<String, Target>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entry {
    pub manifest: Manifest,
    pub enabled: bool,
    #[serde(default)]
    pub pending: Option<Manifest>,
    #[serde(default)]
    pub removing: bool,
    #[serde(default)]
    pub loading: bool,
}
pub struct Catalog {
    pub root: PathBuf,
    pub entries: BTreeMap<String, Entry>,
    pub recovered: usize,
}
pub fn target() -> &'static str {
    if cfg!(target_os = "android") {
        if cfg!(target_arch = "aarch64") {
            "android-arm64-v8a"
        } else {
            "android-x86_64"
        }
    } else if cfg!(target_env = "ohos") {
        if cfg!(target_arch = "aarch64") {
            "ohos-arm64"
        } else {
            "ohos-x86_64"
        }
    } else {
        "windows-x86_64"
    }
}

fn same_installed_build(stored: &Manifest, incoming: &Manifest) -> bool {
    let mut stored_metadata = stored.clone();
    let mut incoming_metadata = incoming.clone();
    stored_metadata.targets.clear();
    incoming_metadata.targets.clear();
    stored_metadata == incoming_metadata
        && stored.targets.get(target()) == incoming.targets.get(target())
        && incoming
            .targets
            .iter()
            .all(|(name, binary)| stored.targets.get(name).is_none_or(|known| known == binary))
}
pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn replace_ascii_padded(bytes: &mut [u8], needle: &[u8], replacement: &[u8]) -> usize {
    if replacement.len() > needle.len() {
        return 0;
    }
    let mut count = 0;
    let mut offset = 0;
    while let Some(relative) = bytes[offset..]
        .windows(needle.len())
        .position(|window| window == needle)
    {
        let start = offset + relative;
        bytes[start..start + needle.len()].fill(0);
        bytes[start..start + replacement.len()].copy_from_slice(replacement);
        offset = start + needle.len();
        count += 1;
    }
    count
}

/// Android's NDK emits loader names and a marker that OHOS does not accept
/// even when the library only uses symbols exported by OHOS libc. Keep the
/// selected library's code intact and normalize only that loader metadata.
fn normalize_android_library_for_ohos(mut bytes: Vec<u8>) -> Result<Vec<u8>> {
    neutralize_android_ident_section(&mut bytes);
    replace_ascii_padded(&mut bytes, b"libdl.so", b"libc.so");
    replace_ascii_padded(&mut bytes, b"libm.so", b"libc.so");
    replace_ascii_padded(&mut bytes, b".note.android.ident", b".note.ohos.ident");
    if !normalize_elf_load_alignment(&mut bytes, ohos_page_alignment()) {
        return Err(invalid(
            "Native library load segments are incompatible with this OHOS page alignment",
        ));
    }
    Ok(bytes)
}

fn ohos_page_alignment() -> u64 {
    if cfg!(target_arch = "aarch64") {
        0x4000
    } else {
        0x1000
    }
}

fn neutralize_android_ident_section(bytes: &mut [u8]) {
    const ELF64_HEADER: usize = 64;
    const ELF64_SECTION_HEADER: usize = 64;
    if bytes.len() < ELF64_HEADER || &bytes[..4] != b"\x7fELF" || bytes[4] != 2 || bytes[5] != 1 {
        return;
    }
    let Some(shoff) = read_u64_le(bytes, 40).and_then(|value| usize::try_from(value).ok()) else {
        return;
    };
    let Some(shentsize) = read_u16_le(bytes, 58).map(usize::from) else {
        return;
    };
    let Some(shnum) = read_u16_le(bytes, 60).map(usize::from) else {
        return;
    };
    let Some(shstrndx) = read_u16_le(bytes, 62).map(usize::from) else {
        return;
    };
    if shentsize < ELF64_SECTION_HEADER || shstrndx >= shnum {
        return;
    }
    let Some(shstr) = section_header(bytes, shoff, shentsize, shstrndx) else {
        return;
    };
    let Some(shstr_offset) = usize::try_from(read_u64_le(shstr, 24).unwrap_or(0)).ok() else {
        return;
    };
    let Some(shstr_size) = usize::try_from(read_u64_le(shstr, 32).unwrap_or(0)).ok() else {
        return;
    };
    let Some(shstr_end) = shstr_offset.checked_add(shstr_size) else {
        return;
    };
    if shstr_end > bytes.len() {
        return;
    }
    for index in 0..shnum {
        let Some(header) = section_header(bytes, shoff, shentsize, index) else {
            return;
        };
        let Some(name_offset) =
            read_u32_le(header, 0).and_then(|value| usize::try_from(value).ok())
        else {
            continue;
        };
        let name_start = shstr_offset.saturating_add(name_offset);
        if name_start >= shstr_end {
            continue;
        }
        let name_end = bytes[name_start..shstr_end]
            .iter()
            .position(|byte| *byte == 0)
            .map(|offset| name_start + offset)
            .unwrap_or(shstr_end);
        if &bytes[name_start..name_end] != b".note.android.ident" {
            continue;
        }
        let section_offset = usize::try_from(read_u64_le(header, 24).unwrap_or(0)).ok();
        let section_size = usize::try_from(read_u64_le(header, 32).unwrap_or(0)).ok();
        if let (Some(section_offset), Some(section_size)) = (section_offset, section_size)
            && let Some(section_end) = section_offset.checked_add(section_size)
            && section_end <= bytes.len()
        {
            bytes[section_offset..section_end].fill(0);
        }
        let header_offset = shoff + index * shentsize;
        bytes[header_offset..header_offset + ELF64_SECTION_HEADER].fill(0);
        return;
    }
}

fn section_header(bytes: &[u8], shoff: usize, shentsize: usize, index: usize) -> Option<&[u8]> {
    let offset = shoff.checked_add(index.checked_mul(shentsize)?)?;
    let end = offset.checked_add(64)?;
    bytes.get(offset..end)
}

fn normalize_elf_load_alignment(bytes: &mut [u8], expected_alignment: u64) -> bool {
    const ELF64_HEADER: usize = 64;
    const ELF64_PROGRAM_HEADER: usize = 56;
    const PT_LOAD: u32 = 1;
    if bytes.len() < ELF64_HEADER || &bytes[..4] != b"\x7fELF" || bytes[4] != 2 || bytes[5] != 1 {
        return false;
    }
    let Some(phoff) = read_u64_le(bytes, 32).and_then(|value| usize::try_from(value).ok()) else {
        return false;
    };
    let Some(phentsize) = read_u16_le(bytes, 54).map(usize::from) else {
        return false;
    };
    let Some(phnum) = read_u16_le(bytes, 56).map(usize::from) else {
        return false;
    };
    if phentsize < ELF64_PROGRAM_HEADER {
        return false;
    }
    let mut load_count = 0;
    for index in 0..phnum {
        let Some(offset) = phoff.checked_add(index.saturating_mul(phentsize)) else {
            return false;
        };
        let Some(end) = offset.checked_add(ELF64_PROGRAM_HEADER) else {
            return false;
        };
        if end > bytes.len() {
            return false;
        }
        if read_u32_le(bytes, offset) != Some(PT_LOAD) {
            continue;
        }
        load_count += 1;
        let Some(segment_offset) = read_u64_le(bytes, offset + 8) else {
            return false;
        };
        let Some(segment_address) = read_u64_le(bytes, offset + 16) else {
            return false;
        };
        let Some(align) = read_u64_le(bytes, offset + 48) else {
            return false;
        };
        if align < expected_alignment
            || segment_offset % expected_alignment != 0
            || segment_address % expected_alignment != 0
        {
            return false;
        }
        let align_offset = offset + 48;
        if align != expected_alignment {
            bytes[align_offset..align_offset + 8]
                .copy_from_slice(&expected_alignment.to_le_bytes());
        }
    }
    load_count > 0
}

fn read_u16_le(bytes: &[u8], offset: usize) -> Option<u16> {
    Some(u16::from_le_bytes(
        bytes.get(offset..offset + 2)?.try_into().ok()?,
    ))
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Option<u32> {
    Some(u32::from_le_bytes(
        bytes.get(offset..offset + 4)?.try_into().ok()?,
    ))
}

fn read_u64_le(bytes: &[u8], offset: usize) -> Option<u64> {
    Some(u64::from_le_bytes(
        bytes.get(offset..offset + 8)?.try_into().ok()?,
    ))
}
/// Existing public transfer envelopes use IEEE CRC32; binary manifests use SHA256.
pub fn transfer_checksum(bytes: &[u8]) -> String {
    let mut crc = !0u32;
    for &byte in bytes {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = (crc >> 1) ^ (0xedb88320 & 0u32.wrapping_sub(crc & 1));
        }
    }
    format!("{:08x}", !crc)
}
pub fn safe_name(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 160
        && s != "."
        && s != ".."
        && s.bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"._-+".contains(&c))
}
pub fn safe_relative(s: &str) -> bool {
    !s.is_empty()
        && !s.contains('\\')
        && !s.contains(':')
        && Path::new(s)
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
}
pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| invalid("Missing parent directory"))?;
    fs::create_dir_all(parent)?;
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    {
        use std::io::Write;
        let mut f = fs::File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
    }
    fs::rename(tmp, path)?;
    Ok(())
}
impl Catalog {
    pub fn open(root: PathBuf) -> Result<Self> {
        fs::create_dir_all(&root)?;
        let root = root.canonicalize()?;
        let entries = match fs::read(root.join("catalog.json")) {
            Ok(bytes) => serde_json::from_slice(&bytes)?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => BTreeMap::new(),
            Err(e) => return Err(e.into()),
        };
        let mut c = Self {
            root,
            entries,
            recovered: 0,
        };
        let removing = c
            .entries
            .iter()
            .filter(|(_, e)| e.removing)
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        for id in removing {
            c.remove_files(&id)?;
            c.entries.remove(&id);
        }
        // A crash while initializing foreign code quarantines that source.
        for entry in c.entries.values_mut() {
            if entry.loading
                || (entry.enabled
                    && entry.pending.as_ref().unwrap_or(&entry.manifest).abi
                        != mgread_native_abi::ABI_VERSION)
            {
                entry.enabled = false;
                entry.loading = false;
                c.recovered += 1;
            }
        }
        // Only immutable files are inspected here. A pending invalid ABI is rejected
        // by the first explicit load, while the prior version remains installed.
        c.save()?;
        // No library is loaded at this boundary. Keep current/pending only;
        // failed candidates and superseded versions cannot retain DLL locks.
        for id in c.entries.keys() {
            c.prune_versions(id)?;
        }
        Ok(c)
    }
    pub fn save(&self) -> Result<()> {
        atomic_write(
            &self.root.join("catalog.json"),
            &serde_json::to_vec(&self.entries)?,
        )
    }
    pub fn versions(&self, id: &str) -> PathBuf {
        self.root.join("plugins").join(id).join("versions")
    }
    pub fn library(&self, m: &Manifest) -> Result<PathBuf> {
        let t = m
            .targets
            .get(target())
            .ok_or_else(|| Error::new("unsupported", "Plugin has no binary for this platform"))?;
        let version = self.versions(&m.id).join(&m.version);
        let library = version.join(&t.path);
        if !library.is_file() {
            // Android can select another ABI after an APK update. The immutable
            // package contains every supported target; recover only the missing
            // current target, preserving the catalog, version and private data.
            let mut archive_bytes = Vec::new();
            fs::File::open(version.join("source.mgplugin"))?
                .take(MAX_ARCHIVE as u64 + 1)
                .read_to_end(&mut archive_bytes)?;
            if archive_bytes.len() > MAX_ARCHIVE {
                return Err(invalid("Stored plugin archive is too large"));
            }
            let mut archive = zip::ZipArchive::new(Cursor::new(archive_bytes))
                .map_err(|_| invalid("Invalid stored plugin ZIP"))?;
            let mut bytes = Vec::new();
            archive
                .by_name(&t.path)
                .map_err(|_| invalid("Stored package has no target binary"))?
                .take(32 * 1024 * 1024 + 1)
                .read_to_end(&mut bytes)?;
            if bytes.len() > 32 * 1024 * 1024 || hash(&bytes) != t.sha256.to_lowercase() {
                return Err(invalid("Stored target checksum mismatch"));
            }
            atomic_write(&library, &bytes)?;
        }
        Ok(library)
    }
    pub fn validate_manifest(m: &Manifest) -> Result<()> {
        if m.format != "mgread-native"
            || m.engine != "native"
            || m.abi != mgread_native_abi::ABI_VERSION
            || !safe_name(&m.id)
            || !safe_name(&m.version)
            || semver::Version::parse(&m.version).is_err()
            || m.name.is_empty()
            || m.name.len() > 256
            || m.description.len() > 960
            || m.content_kinds.is_empty()
            || m.content_kinds.len() > 4
            || m.content_kinds
                .iter()
                .any(|k| !["novel", "manga", "audio", "video"].contains(&k.as_str()))
            || m.content_kinds.iter().collect::<HashSet<_>>().len() != m.content_kinds.len()
            || m.targets.is_empty()
            || m.targets.len() > 5
        {
            return Err(invalid("Unsupported native manifest"));
        }
        for (name, t) in &m.targets {
            if !SUPPORTED_TARGETS.contains(&name.as_str())
                || !safe_relative(&t.path)
                || t.sha256.len() != 64
                || !t.sha256.bytes().all(|c| c.is_ascii_hexdigit())
            {
                return Err(invalid("Invalid native target"));
            }
        }
        if !m.targets.contains_key(target()) {
            return Err(Error::new("unsupported", "Plugin target is unavailable"));
        }
        Ok(())
    }
    pub fn install(&mut self, bytes: &[u8], expected: Option<(&str, &str)>) -> Result<Manifest> {
        if bytes.len() > MAX_ARCHIVE {
            return Err(invalid("Plugin archive is too large"));
        }
        let mut archive =
            zip::ZipArchive::new(Cursor::new(bytes)).map_err(|_| invalid("Invalid plugin ZIP"))?;
        if archive.len() > 16 {
            return Err(invalid("Too many archive entries"));
        }
        let mut seen = HashSet::new();
        let mut expanded = 0u64;
        for i in 0..archive.len() {
            let f = archive
                .by_index(i)
                .map_err(|_| invalid("Invalid archive entry"))?;
            if !safe_relative(f.name())
                || !seen.insert(f.name().to_string())
                || f.is_dir()
                || f.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000)
            {
                return Err(invalid("Unsafe archive entry"));
            }
            expanded = expanded
                .checked_add(f.size())
                .ok_or_else(|| invalid("Archive size overflow"))?;
            if expanded > MAX_ARCHIVE as u64 {
                return Err(invalid("Expanded archive is too large"));
            }
        }
        let mut raw = Vec::new();
        archive
            .by_name("manifest.json")
            .map_err(|_| invalid("Missing native manifest"))?
            .take(65537)
            .read_to_end(&mut raw)?;
        if raw.len() > 65536 {
            return Err(invalid("Manifest is too large"));
        }
        let manifest: Manifest = serde_json::from_slice(&raw)?;
        Self::validate_manifest(&manifest)?;
        if expected.is_some_and(|(id, version)| manifest.id != id || manifest.version != version) {
            return Err(invalid(
                "Transfer metadata does not match the native manifest",
            ));
        }
        let selected = manifest.targets.get(target()).unwrap();
        let mut binary = Vec::new();
        for t in manifest.targets.values() {
            let mut data = Vec::new();
            archive
                .by_name(&t.path)
                .map_err(|_| invalid("Missing target binary"))?
                .take(32 * 1024 * 1024 + 1)
                .read_to_end(&mut data)?;
            if data.len() > 32 * 1024 * 1024 || hash(&data) != t.sha256.to_lowercase() {
                return Err(invalid("Native binary checksum mismatch"));
            }
            if t.path == selected.path {
                binary = data;
            }
        }
        let version_dir = self.versions(&manifest.id).join(&manifest.version);
        if version_dir.exists() {
            let stored: Manifest =
                serde_json::from_slice(&fs::read(version_dir.join("manifest.json"))?)?;
            // A LAN transfer may carry just this platform's targets. Treat it
            // as the same immutable build when metadata and every common
            // binary hash agree; retain the richer stored archive unchanged.
            if !same_installed_build(&stored, &manifest) {
                return Err(invalid("Installed versions are immutable"));
            }
        } else {
            let stage = self.versions(&manifest.id).join(format!(
                ".stage-{}-{}",
                std::process::id(),
                manifest.version
            ));
            if stage.exists() {
                fs::remove_dir_all(&stage)?;
            }
            fs::create_dir_all(&stage)?;
            atomic_write(&stage.join(&selected.path), &binary)?;
            atomic_write(&stage.join("manifest.json"), &raw)?;
            atomic_write(&stage.join("source.mgplugin"), bytes)?;
            fs::rename(&stage, &version_dir)?;
        }
        // Installation validates bytes and metadata only. Disabled libraries
        // must never execute constructors or ABI entry points during import.
        if let Some(e) = self.entries.get_mut(&manifest.id) {
            if e.manifest.version != manifest.version {
                e.pending = Some(manifest.clone());
            }
            e.removing = false;
        } else {
            self.entries.insert(
                manifest.id.clone(),
                Entry {
                    manifest: manifest.clone(),
                    enabled: true,
                    pending: None,
                    removing: false,
                    loading: false,
                },
            );
        }
        self.save()?;
        Ok(manifest)
    }
    /// Wrap a user-selected native library in the immutable native package
    /// format. Raw libraries do not carry the catalog metadata required by
    /// the Runtime, so the well-known Alice filename keeps its public
    /// identity and other libraries receive a stable hash-based identity.
    pub fn install_raw(&mut self, path: &Path) -> Result<Manifest> {
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| invalid("Native library filename is invalid"))?;
        let lower_name = file_name.to_ascii_lowercase();
        let extension = if target() == "windows-x86_64" {
            ".dll"
        } else {
            ".so"
        };
        if !lower_name.ends_with(extension) {
            return Err(invalid(
                "Native library extension does not match this platform",
            ));
        }
        let raw_bytes = fs::read(path)?;
        if raw_bytes.is_empty() || raw_bytes.len() > 32 * 1024 * 1024 {
            return Err(invalid("Native library is empty or too large"));
        }
        let bytes = if target().starts_with("ohos")
            && raw_bytes
                .windows(b".note.android.ident".len())
                .any(|window| window == b".note.android.ident")
        {
            normalize_android_library_for_ohos(raw_bytes)?
        } else {
            raw_bytes
        };
        let digest = hash(&bytes);
        let alice = lower_name.contains("aisishuwu") || lower_name.contains("alice");
        let (id, name, version, description) = if alice {
            (
                "org.mgread.aisishuwu.native".to_string(),
                "爱丽丝书屋（Rust）".to_string(),
                // Raw imports are persisted by the wrapper rather than by the
                // source manifest. Bump this wrapper version when the OHOS
                // loader representation changes so an older normalized arm64
                // binary cannot remain the active immutable installation.
                "0.3.1".to_string(),
                "手动导入的 Rust 原生小说数据源".to_string(),
            )
        } else {
            let stem = file_name
                .rsplit_once('.')
                .map(|(value, _)| value)
                .unwrap_or(file_name);
            let safe_stem = stem
                .chars()
                .filter(|value| value.is_ascii_alphanumeric() || matches!(value, '.' | '_' | '-'))
                .collect::<String>();
            let safe_stem = if safe_stem.is_empty() {
                "source"
            } else {
                safe_stem.as_str()
            };
            let safe_stem = &safe_stem[..safe_stem.len().min(100)];
            (
                format!("org.mgread.native.{}-{}", safe_stem, &digest[..12]),
                stem.chars().take(256).collect::<String>(),
                format!("0.0.0+{}", &digest[..12]),
                "手动导入的 Rust 原生数据源".to_string(),
            )
        };
        let archive_path = format!(
            "native/{}/{}",
            target(),
            if extension == ".dll" {
                "source.dll"
            } else {
                "libsource.so"
            }
        );
        let manifest = Manifest {
            format: "mgread-native".into(),
            engine: "native".into(),
            abi: mgread_native_abi::ABI_VERSION,
            id,
            name,
            version,
            description,
            content_kinds: vec!["novel".into()],
            capabilities: vec![
                "discover".into(),
                "search".into(),
                "searchSuggestions".into(),
                "getDetail".into(),
                "getChapters".into(),
                "getContent".into(),
            ],
            targets: BTreeMap::from([(
                target().into(),
                Target {
                    path: archive_path.clone(),
                    sha256: digest,
                },
            )]),
        };
        Self::validate_manifest(&manifest)?;
        let mut output = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut output);
            let options = zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated);
            let manifest_bytes = serde_json::to_vec(&manifest)?;
            zip.start_file("manifest.json", options)
                .map_err(|_| invalid("Native package creation failed"))?;
            zip.write_all(&manifest_bytes)?;
            zip.start_file(&archive_path, options)
                .map_err(|_| invalid("Native package creation failed"))?;
            zip.write_all(&bytes)?;
            zip.finish()
                .map_err(|_| invalid("Native package creation failed"))?;
        }
        self.install(output.get_ref(), None)
    }
    pub fn projection(&self, e: &Entry) -> Value {
        let m = &e.manifest;
        json!({"id":m.id,"name":m.name,"displayName":m.name,"description":m.description,"iconUrl":null,
               "activeVersion":m.version,"pendingVersion":e.pending.as_ref().map(|p|&p.version),"enabled":e.enabled,
               "status":if e.enabled {"active"}else{"disabled"},"contentKinds":m.content_kinds,"engine":"native"})
    }
    pub fn list(&self) -> Value {
        Value::Array(
            self.entries
                .values()
                .filter(|e| !e.removing)
                .map(|e| self.projection(e))
                .collect(),
        )
    }
    pub fn entry(&self, id: &str) -> Result<&Entry> {
        self.entries
            .get(id)
            .filter(|e| !e.removing)
            .ok_or_else(|| Error::new("plugin_not_found", "Native plugin is not installed"))
    }
    fn prune_versions(&self, id: &str) -> Result<()> {
        if !safe_name(id) {
            return Err(invalid("Invalid plugin identifier"));
        }
        let entry = &self.entries[id];
        let directory = self.versions(id);
        if !directory.is_dir() {
            return Ok(());
        }
        for child in fs::read_dir(directory)? {
            let child = child?;
            let name = child.file_name();
            let Some(name) = name.to_str() else {
                continue;
            };
            if name == entry.manifest.version
                || entry.pending.as_ref().is_some_and(|m| m.version == name)
            {
                continue;
            }
            if child.file_type()?.is_dir() && safe_name(name) {
                fs::remove_dir_all(child.path())?;
            }
        }
        Ok(())
    }
    fn remove_files(&self, id: &str) -> Result<()> {
        if !safe_name(id) {
            return Err(invalid("Invalid plugin identifier"));
        }
        let p = self.root.join("plugins").join(id);
        if p.exists() {
            fs::remove_dir_all(p)?;
        }
        Ok(())
    }
}
pub fn usage(path: &Path) -> Result<(u64, u64)> {
    if !path.exists() {
        return Ok((0, 0));
    }
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(invalid("Symlink in native storage"));
    }
    if metadata.is_file() {
        return Ok((metadata.len(), 1));
    }
    let (mut bytes, mut files) = (0, 0);
    for item in fs::read_dir(path)? {
        let (b, f) = usage(&item?.path())?;
        bytes += b;
        files += f;
    }
    Ok((bytes, files))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_path_escapes() {
        for p in ["../x", "/x", "C:/x", "x\\y", "."] {
            assert!(!safe_relative(p), "{p}");
        }
        assert!(safe_relative("android-x86_64/libsource.so"));
    }
    #[test]
    fn identifiers_are_components() {
        for p in ["..", ".", "a/b", "", "a:b"] {
            assert!(!safe_name(p));
        }
        assert!(safe_name("org.mgread.alice"));
    }
    #[test]
    fn supports_ohos_native_targets() {
        assert!(SUPPORTED_TARGETS.contains(&"ohos-arm64"));
        assert!(SUPPORTED_TARGETS.contains(&"ohos-x86_64"));
    }
    #[test]
    fn platform_subset_is_the_same_installed_build() {
        let selected = Target {
            path: "native/current/source.dll".into(),
            sha256: "a".repeat(64),
        };
        let other = Target {
            path: "native/other/source.so".into(),
            sha256: "b".repeat(64),
        };
        let manifest = Manifest {
            format: "mgread-native".into(),
            engine: "native".into(),
            abi: mgread_native_abi::ABI_VERSION,
            id: "org.mgread.alice".into(),
            name: "Alice".into(),
            version: "0.1.0".into(),
            description: String::new(),
            content_kinds: vec!["novel".into()],
            capabilities: vec!["search".into()],
            targets: BTreeMap::from([(target().into(), selected.clone()), ("other".into(), other)]),
        };
        let mut subset = manifest.clone();
        subset.targets.retain(|name, _| name == target());
        assert!(same_installed_build(&manifest, &subset));
        subset.targets.get_mut(target()).unwrap().sha256 = "c".repeat(64);
        assert!(!same_installed_build(&manifest, &subset));
        subset = manifest.clone();
        subset.version = "0.1.1".into();
        assert!(!same_installed_build(&manifest, &subset));
    }
    #[test]
    fn raw_library_import_creates_a_standard_native_package() {
        let root = std::env::temp_dir().join(format!(
            "mgread-native-catalog-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let library = root.join(if target() == "windows-x86_64" {
            "aisishuwu-native.dll"
        } else {
            "aisishuwu-native.so"
        });
        fs::create_dir_all(&root).unwrap();
        fs::write(&library, b"native-library-fixture").unwrap();
        let mut catalog = Catalog::open(root.join("runtime")).unwrap();
        let manifest = catalog.install_raw(&library).unwrap();
        assert_eq!(manifest.id, "org.mgread.aisishuwu.native");
        assert_eq!(manifest.version, "0.3.1");
        assert!(
            catalog
                .versions(&manifest.id)
                .join(&manifest.version)
                .join("source.mgplugin")
                .is_file()
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn android_library_loader_metadata_is_normalized_for_ohos() {
        let mut input = vec![0u8; 256];
        input[..4].copy_from_slice(b"\x7fELF");
        input[4] = 2;
        input[5] = 1;
        input[32..40].copy_from_slice(&64u64.to_le_bytes());
        input[54..56].copy_from_slice(&56u16.to_le_bytes());
        input[56..58].copy_from_slice(&1u16.to_le_bytes());
        input[64..68].copy_from_slice(&1u32.to_le_bytes());
        input[64 + 8..64 + 16].copy_from_slice(&0u64.to_le_bytes());
        input[64 + 16..64 + 24].copy_from_slice(&0u64.to_le_bytes());
        input[64 + 48..64 + 56].copy_from_slice(&0x4000u64.to_le_bytes());
        let metadata = b"libdl.so\0libm.so\0libc.so\0.note.android.ident\0";
        input[128..128 + metadata.len()].copy_from_slice(metadata);
        let bytes = normalize_android_library_for_ohos(input).unwrap();
        assert!(!bytes.windows(b"libdl.so".len()).any(|w| w == b"libdl.so"));
        assert!(!bytes.windows(b"libm.so".len()).any(|w| w == b"libm.so"));
        assert!(bytes.windows(b"libc.so".len()).any(|w| w == b"libc.so"));
        assert!(
            bytes
                .windows(b".note.ohos.ident".len())
                .any(|w| w == b".note.ohos.ident")
        );
        assert!(
            !bytes
                .windows(b".note.android.ident".len())
                .any(|w| w == b".note.android.ident")
        );
    }

    #[test]
    fn android_elf_load_alignment_is_normalized_to_ohos_page_alignment() {
        let mut bytes = vec![0u8; 128];
        bytes[..4].copy_from_slice(b"\x7fELF");
        bytes[4] = 2;
        bytes[5] = 1;
        bytes[32..40].copy_from_slice(&64u64.to_le_bytes());
        bytes[54..56].copy_from_slice(&64u16.to_le_bytes());
        bytes[56..58].copy_from_slice(&1u16.to_le_bytes());
        bytes[64..68].copy_from_slice(&1u32.to_le_bytes());
        bytes[64 + 48..64 + 56].copy_from_slice(&0x4000u64.to_le_bytes());
        assert!(normalize_elf_load_alignment(&mut bytes, 0x1000));
        assert_eq!(read_u64_le(&bytes, 64 + 48), Some(0x1000));
    }

    #[test]
    fn arm64_alignment_rejects_four_kib_load_segments() {
        let mut bytes = vec![0u8; 128];
        bytes[..4].copy_from_slice(b"\x7fELF");
        bytes[4] = 2;
        bytes[5] = 1;
        bytes[32..40].copy_from_slice(&64u64.to_le_bytes());
        bytes[54..56].copy_from_slice(&56u16.to_le_bytes());
        bytes[56..58].copy_from_slice(&1u16.to_le_bytes());
        bytes[64..68].copy_from_slice(&1u32.to_le_bytes());
        bytes[64 + 48..64 + 56].copy_from_slice(&0x1000u64.to_le_bytes());
        assert!(!normalize_elf_load_alignment(&mut bytes, 0x4000));
    }
}
