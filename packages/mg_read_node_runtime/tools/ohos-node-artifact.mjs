// Create and verify the external OHOS Node 26.10.0 runtime artifact.
// The artifact is deliberately self-contained so the OHOS build never needs
// the checked-in Node/V8 source tree once the migration is complete.
import { createHash } from "node:crypto";
import { cp, mkdir, open, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const NODE_VERSION = "26.10.0";
const SCHEMA_VERSION = 1;
const ARCHITECTURES = new Set(["arm64", "x64"]);

function usage() {
  throw new Error(
    "Usage: node tools/ohos-node-artifact.mjs create <arm64|x64> <runtime-root> <source-root> <artifact-root> [toolchain-version]\n" +
      "   or: node tools/ohos-node-artifact.mjs verify <arm64|x64> <artifact-root>",
  );
}

function assertArchitecture(architecture) {
  if (!ARCHITECTURES.has(architecture)) usage();
}

function assertInside(root, candidate) {
  const relativePath = relative(root, candidate);
  if (isAbsolute(relativePath) || relativePath === ".." || relativePath.startsWith(`..${sep}`)) {
    throw new Error(`Path escapes the selected root: ${candidate}`);
  }
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function exists(path) {
  try {
    await stat(path);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function sha256File(path) {
  const hash = createHash("sha256");
  const handle = await open(path, "r");
  try {
    for (;;) {
      const buffer = Buffer.allocUnsafe(1024 * 1024);
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, null);
      if (bytesRead === 0) break;
      hash.update(buffer.subarray(0, bytesRead));
    }
  } finally {
    await handle.close();
  }
  return hash.digest("hex").toUpperCase();
}

async function collectFiles(root, prefix = "") {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const relativePath = prefix ? join(prefix, entry.name) : entry.name;
    const path = join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await collectFiles(path, relativePath)));
    } else if (entry.isFile()) {
      const item = await stat(path);
      files.push({ path: relativePath.replaceAll("\\", "/"), bytes: item.size, sha256: await sha256File(path) });
    } else {
      throw new Error(`Artifact trees cannot contain symlinks or special files: ${path}`);
    }
  }
  return files;
}

async function treeDigest(root) {
  const files = await collectFiles(root);
  const hash = createHash("sha256");
  for (const file of files) hash.update(`${file.path}\0${file.sha256}\n`);
  return { sha256: hash.digest("hex").toUpperCase(), files, bytes: files.reduce((sum, file) => sum + file.bytes, 0) };
}

async function readElfMetadata(path) {
  const handle = await open(path, "r");
  const readRange = async (offset, length) => {
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length < 0 || length > 1024 * 1024) {
      throw new Error("ELF metadata contains an invalid file range.");
    }
    const data = Buffer.alloc(length);
    const { bytesRead } = await handle.read(data, 0, length, offset);
    if (bytesRead !== length) throw new Error("ELF metadata is truncated.");
    return data;
  };
  try {
    const header = await readRange(0, 64);
    if (header[0] !== 0x7f || header.toString("ascii", 1, 4) !== "ELF" || header[4] !== 2 || header[5] !== 1) {
      throw new Error("Node shared library is not a little-endian ELF64 object.");
    }
    const machine = header.readUInt16LE(18);
    const programHeaderOffset = Number(header.readBigUInt64LE(32));
    const programHeaderSize = header.readUInt16LE(54);
    const programHeaderCount = header.readUInt16LE(56);
    if (programHeaderSize < 56 || programHeaderCount === 0 || programHeaderCount > 4096) {
      throw new Error("ELF program-header table is invalid.");
    }
    const programHeaders = await readRange(programHeaderOffset, programHeaderSize * programHeaderCount);
    const loads = [];
    let dynamicSegment;
    for (let index = 0; index < programHeaderCount; index += 1) {
      const offset = index * programHeaderSize;
      const type = programHeaders.readUInt32LE(offset);
      const fileOffset = programHeaders.readBigUInt64LE(offset + 8);
      const virtualAddress = programHeaders.readBigUInt64LE(offset + 16);
      const fileSize = programHeaders.readBigUInt64LE(offset + 32);
      if (type === 1) loads.push({ fileOffset, virtualAddress, fileSize });
      if (type === 2) dynamicSegment = { fileOffset, fileSize };
    }
    if (!dynamicSegment) throw new Error("ELF has no dynamic section.");
    const dynamicData = await readRange(Number(dynamicSegment.fileOffset), Number(dynamicSegment.fileSize));
    let stringTableAddress;
    let sonameOffset;
    for (let offset = 0; offset + 16 <= dynamicData.length; offset += 16) {
      const tag = dynamicData.readBigInt64LE(offset);
      const value = dynamicData.readBigUInt64LE(offset + 8);
      if (tag === 0n) break;
      if (tag === 5n) stringTableAddress = value;
      if (tag === 14n) sonameOffset = value;
    }
    if (stringTableAddress === undefined || sonameOffset === undefined) throw new Error("ELF has no SONAME.");
    const stringTableLoad = loads.find(
      (load) => stringTableAddress >= load.virtualAddress && stringTableAddress < load.virtualAddress + load.fileSize,
    );
    if (!stringTableLoad) throw new Error("ELF string table is not file-backed.");
    const sonameFileOffset = Number(stringTableLoad.fileOffset + stringTableAddress - stringTableLoad.virtualAddress + sonameOffset);
    const sonameData = await readRange(sonameFileOffset, 256);
    const terminator = sonameData.indexOf(0);
    if (terminator <= 0) throw new Error("ELF SONAME is invalid.");
    return { machine, soname: sonameData.toString("utf8", 0, terminator) };
  } finally {
    await handle.close();
  }
}

async function readNodeVersion(headerPath) {
  const header = await readFile(headerPath, "utf8");
  const readPart = (name) => {
    const match = header.match(new RegExp(`^\\s*#define\\s+${name}\\s+(\\d+)\\s*$`, "m"));
    if (!match) throw new Error(`Node headers are missing ${name}.`);
    return Number(match[1]);
  };
  return {
    version: ["NODE_MAJOR_VERSION", "NODE_MINOR_VERSION", "NODE_PATCH_VERSION"].map(readPart).join("."),
    moduleVersion: readPart("NODE_MODULE_VERSION"),
  };
}

async function verifyArtifact(architecture, artifactRoot) {
  assertArchitecture(architecture);
  const root = resolve(artifactRoot);
  const manifestPath = join(root, "manifest.json");
  const manifest = await readJson(manifestPath);
  if (manifest.schemaVersion !== SCHEMA_VERSION) throw new Error(`Unsupported artifact schema: ${manifest.schemaVersion}`);
  if (manifest.nodeVersion !== NODE_VERSION) throw new Error(`Artifact Node version is not ${NODE_VERSION}.`);
  if (manifest.architecture !== architecture || manifest.target !== `openharmony-${architecture}`) {
    throw new Error(`Artifact target does not match OpenHarmony ${architecture}.`);
  }
  if (manifest.sourceRoot !== "node-source") throw new Error("Artifact sourceRoot must be node-source.");
  if (!/^libnode\.so(?:\.\d+)*$/.test(manifest.soname)) throw new Error(`Artifact SONAME is invalid: ${manifest.soname}`);
  const required = [
    "mgread-node-build.json",
    "mgread-node-target.txt",
    "mgread-node-soname.txt",
    "include/node/node_version.h",
    "node-source/src/node.h",
    "node-source/deps/v8/include/include/v8.h",
  ];
  for (const relativePath of required) {
    if (!(await exists(join(root, relativePath)))) throw new Error(`Artifact file is missing: ${relativePath}`);
  }
  const libraryPath = join(root, manifest.libraryPath);
  if (!(await exists(libraryPath))) throw new Error(`Artifact library is missing: ${manifest.libraryPath}`);
  const target = (await readFile(join(root, "mgread-node-target.txt"), "utf8")).trim();
  if (target !== architecture) throw new Error(`Artifact target file is ${target}, expected ${architecture}.`);
  const soname = (await readFile(join(root, "mgread-node-soname.txt"), "utf8")).trim();
  if (soname !== manifest.soname) throw new Error(`Artifact SONAME file is ${soname}, expected ${manifest.soname}.`);
  const nodeVersion = await readNodeVersion(join(root, "include/node/node_version.h"));
  if (nodeVersion.version !== NODE_VERSION) throw new Error(`Artifact headers report Node ${nodeVersion.version}.`);
  const elf = await readElfMetadata(libraryPath);
  const expectedMachine = architecture === "x64" ? 62 : 183;
  if (elf.machine !== expectedMachine) throw new Error(`Artifact ELF machine ${elf.machine} does not match ${architecture}.`);
  if (elf.soname !== manifest.soname) throw new Error(`Artifact ELF SONAME ${elf.soname} does not match ${manifest.soname}.`);
  const libraryStat = await stat(libraryPath);
  const librarySha256 = await sha256File(libraryPath);
  if (libraryStat.size !== manifest.libraryBytes || librarySha256 !== manifest.librarySha256) {
    throw new Error("Artifact libnode.so size or SHA-256 does not match manifest.json.");
  }
  const source = await treeDigest(join(root, "node-source"));
  if (source.sha256 !== manifest.sourceSha256 || source.bytes !== manifest.sourceBytes || source.files.length !== manifest.sourceFiles) {
    throw new Error("Artifact Node/V8 source tree does not match manifest.json.");
  }
  const headers = await treeDigest(join(root, "include/node"));
  if (headers.sha256 !== manifest.headersSha256 || headers.bytes !== manifest.headersBytes || headers.files.length !== manifest.headersFiles) {
    throw new Error("Artifact Node public headers do not match manifest.json.");
  }
  return {
    artifact: manifest.artifact,
    architecture,
    nodeVersion: NODE_VERSION,
    target,
    soname,
    elfMachine: elf.machine,
    libraryPath: manifest.libraryPath,
    librarySha256,
    sourceSha256: source.sha256,
    sourceFiles: source.files.length,
    sourceBytes: source.bytes,
    headersSha256: headers.sha256,
    headersFiles: headers.files.length,
    headersBytes: headers.bytes,
  };
}

async function copyTree(source, destination) {
  const entries = await readdir(source, { withFileTypes: true });
  await mkdir(destination, { recursive: true });
  for (const entry of entries) {
    const sourcePath = join(source, entry.name);
    const destinationPath = join(destination, entry.name);
    if (entry.isDirectory()) await copyTree(sourcePath, destinationPath);
    else if (entry.isFile()) await cp(sourcePath, destinationPath);
    else throw new Error(`Artifact trees cannot contain symlinks or special files: ${sourcePath}`);
  }
}

async function createArtifact(architecture, runtimeRootArgument, sourceRootArgument, artifactRootArgument, toolchainVersion = "unknown") {
  assertArchitecture(architecture);
  const runtimeRoot = resolve(runtimeRootArgument);
  const sourceRoot = resolve(sourceRootArgument);
  const artifactRoot = resolve(artifactRootArgument);
  if (await exists(artifactRoot)) throw new Error(`Artifact already exists; remove it explicitly before recreating: ${artifactRoot}`);
  const version = await readNodeVersion(join(runtimeRoot, "include/node/node_version.h"));
  const metadataPath = join(runtimeRoot, "mgread-node-build.json");
  const runtimeMetadata = (await exists(metadataPath))
    ? await readJson(metadataPath)
    : { nodeVersion: version.version, target: `openharmony-${architecture}`, moduleVersion: version.moduleVersion };
  if (runtimeMetadata.nodeVersion !== NODE_VERSION || (runtimeMetadata.target && runtimeMetadata.target !== `openharmony-${architecture}`)) {
    throw new Error("Runtime metadata does not match Node 26.10.0 and the selected OpenHarmony ABI.");
  }
  const runtimeSonamePath = join(runtimeRoot, "mgread-node-soname.txt");
  const candidateLibrary = join(runtimeRoot, "lib", "libnode.so");
  const versionedLibrary = (await exists(candidateLibrary)) ? candidateLibrary : join(runtimeRoot, "lib", `libnode.so.${runtimeMetadata.moduleVersion}`);
  const candidateElf = await readElfMetadata(versionedLibrary);
  const soname = (await exists(runtimeSonamePath)) ? (await readFile(runtimeSonamePath, "utf8")).trim() : candidateElf.soname;
  if (!/^libnode\.so(?:\.\d+)*$/.test(soname)) throw new Error(`Runtime SONAME is invalid: ${soname}`);
  const libraryPath = join(runtimeRoot, "lib", soname);
  if (!(await exists(libraryPath))) throw new Error(`Runtime library named by SONAME is missing: ${libraryPath}`);
  if (candidateElf.soname !== soname) throw new Error(`Runtime ELF SONAME ${candidateElf.soname} does not match ${soname}.`);
  for (const path of [libraryPath, join(runtimeRoot, "include/node"), join(sourceRoot, "src/node.h"), join(sourceRoot, "deps/v8/include/include/v8.h")]) {
    if (!(await exists(path))) throw new Error(`Artifact input is missing: ${path}`);
  }
  const stagingRoot = `${artifactRoot}.staging-${process.pid}`;
  await rm(stagingRoot, { force: true, recursive: true });
  try {
    await mkdir(join(stagingRoot, "lib"), { recursive: true });
    await copyTree(join(runtimeRoot, "include/node"), join(stagingRoot, "include/node"));
    await copyTree(join(sourceRoot, "src"), join(stagingRoot, "node-source/src"));
    await copyTree(join(sourceRoot, "deps/v8/include"), join(stagingRoot, "node-source/deps/v8/include"));
    if (await exists(join(sourceRoot, "source_location"))) await cp(join(sourceRoot, "source_location"), join(stagingRoot, "node-source/source_location"));
    await cp(libraryPath, join(stagingRoot, "lib", soname));
    await writeFile(join(stagingRoot, "mgread-node-build.json"), `${JSON.stringify({
      ...runtimeMetadata,
      nodeVersion: NODE_VERSION,
      target: `openharmony-${architecture}`,
      sharedLibrary: `lib/${soname}`,
      soname,
      moduleVersion: runtimeMetadata.moduleVersion ?? version.moduleVersion,
      elfMachine: candidateElf.machine,
    }, null, 2)}\n`, "utf8");
    await writeFile(join(stagingRoot, "mgread-node-target.txt"), `${architecture}\n`, "utf8");
    await writeFile(join(stagingRoot, "mgread-node-soname.txt"), `${soname}\n`, "utf8");
    const source = await treeDigest(join(stagingRoot, "node-source"));
    const headers = await treeDigest(join(stagingRoot, "include/node"));
    const libraryStat = await stat(join(stagingRoot, "lib", soname));
    const manifest = {
      schemaVersion: SCHEMA_VERSION,
      artifact: `mgread-ohos-node-${NODE_VERSION}-${architecture}`,
      nodeVersion: NODE_VERSION,
      architecture,
      target: `openharmony-${architecture}`,
      soname,
      libraryPath: `lib/${soname}`,
      libraryBytes: libraryStat.size,
      librarySha256: await sha256File(join(stagingRoot, "lib", soname)),
      sourceRoot: "node-source",
      sourceFiles: source.files.length,
      sourceBytes: source.bytes,
      sourceSha256: source.sha256,
      headersFiles: headers.files.length,
      headersBytes: headers.bytes,
      headersSha256: headers.sha256,
      moduleVersion: runtimeMetadata.moduleVersion,
      sourceCommit: runtimeMetadata.sourceCommit ?? null,
      toolchainVersion,
      generatedAtUtc: new Date().toISOString(),
    };
    await writeFile(join(stagingRoot, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    await rename(stagingRoot, artifactRoot);
  } catch (error) {
    await rm(stagingRoot, { force: true, recursive: true });
    throw error;
  }
  const result = await verifyArtifact(architecture, artifactRoot);
  process.stdout.write(`${JSON.stringify({ ...result, artifactRoot }, null, 2)}\n`);
}

const [command, architecture, ...args] = process.argv.slice(2);
if (command === "verify" && args.length === 1) {
  const result = await verifyArtifact(architecture, args[0]);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
} else if (command === "create" && (args.length === 3 || args.length === 4)) {
  await createArtifact(architecture, args[0], args[1], args[2], args[3]);
} else {
  usage();
}
