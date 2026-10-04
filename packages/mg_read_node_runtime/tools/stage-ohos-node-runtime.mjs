// Stage a verified Node shared build into the ABI-specific OHOS host input.
// The source build is separate from staging so device acceptance can precede
// publishing a new embedded runtime artifact.
import { cp, mkdir, open, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const [architecture, installRootArgument, ...extraArguments] = process.argv.slice(2);
if (!new Set(["arm64", "x64"]).has(architecture) || !installRootArgument || extraArguments.length > 0) {
  throw new Error("Usage: node tools/stage-ohos-node-runtime.mjs <arm64|x64> <Node install root>");
}

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const installRoot = resolve(installRootArgument);
const metadataPath = join(installRoot, "mgread-node-build.json");
let metadata;
try {
  metadata = JSON.parse(await readFile(metadataPath, "utf8"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

if (metadata && (metadata.nodeVersion !== "26.10.0" || metadata.target !== `openharmony-${architecture}`)) {
  throw new Error(`Node build metadata does not match Node 26.10.0 OpenHarmony ${architecture}.`);
}
if (metadata && (typeof metadata.sharedLibrary !== "string" || metadata.sharedLibrary.length === 0)) {
  throw new Error("Node build metadata is missing the shared-library path.");
}
const sharedLibrary = resolve(installRoot, metadata?.sharedLibrary ?? "lib/libnode.so");
const sharedLibraryRelative = relative(installRoot, sharedLibrary);
if (isAbsolute(sharedLibraryRelative) || sharedLibraryRelative === ".." || sharedLibraryRelative.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`)) {
  throw new Error("Node shared-library path escapes the selected install root.");
}
const includeRoot = join(installRoot, "include", "node");
const libraryStat = await stat(sharedLibrary);
if (libraryStat.size === 0) throw new Error(`Node shared library is empty: ${sharedLibrary}`);
const versionHeader = await readFile(join(includeRoot, "node_version.h"), "utf8");
function readNodeVersionPart(name) {
  const match = versionHeader.match(new RegExp(`^\\s*#define\\s+${name}\\s+(\\d+)\\s*$`, "m"));
  if (!match) throw new Error(`The staged Node headers are missing ${name}.`);
  return Number(match[1]);
}
const nodeVersion = ["NODE_MAJOR_VERSION", "NODE_MINOR_VERSION", "NODE_PATCH_VERSION"]
  .map(readNodeVersionPart)
  .join(".");
if (nodeVersion !== "26.10.0") throw new Error(`Expected Node headers 26.10.0, got ${nodeVersion}.`);
const moduleVersion = readNodeVersionPart("NODE_MODULE_VERSION");

const libraryHandle = await open(sharedLibrary, "r");
const elfHeader = Buffer.alloc(64);
let elfMachine;
let soname;
async function readElfRange(offset, length) {
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(length) || length < 0 || length > 1024 * 1024) {
    throw new Error("Node shared-library ELF metadata contains an invalid file range.");
  }
  const data = Buffer.alloc(length);
  const { bytesRead } = await libraryHandle.read(data, 0, length, offset);
  if (bytesRead !== length) throw new Error("Node shared-library ELF metadata is truncated.");
  return data;
}
try {
  const { bytesRead } = await libraryHandle.read(elfHeader, 0, elfHeader.length, 0);
  if (bytesRead !== elfHeader.length || elfHeader[0] !== 0x7f || elfHeader.toString("ascii", 1, 4) !== "ELF" || elfHeader[4] !== 2 || elfHeader[5] !== 1) {
    throw new Error("Node shared library is not a little-endian ELF64 object.");
  }
  elfMachine = elfHeader.readUInt16LE(18);
  const expectedMachine = architecture === "x64" ? 62 : 183;
  if (elfMachine !== expectedMachine) {
    throw new Error(`Node shared-library ELF machine ${elfMachine} does not match OpenHarmony ${architecture}.`);
  }

  const programHeaderOffset = Number(elfHeader.readBigUInt64LE(32));
  const programHeaderSize = elfHeader.readUInt16LE(54);
  const programHeaderCount = elfHeader.readUInt16LE(56);
  if (programHeaderSize < 56 || programHeaderCount === 0 || programHeaderCount > 4096) {
    throw new Error("Node shared library has an invalid ELF program-header table.");
  }
  const programHeaders = await readElfRange(programHeaderOffset, programHeaderSize * programHeaderCount);
  const loads = [];
  let dynamicSegment;
  for (let index = 0; index < programHeaderCount; index++) {
    const offset = index * programHeaderSize;
    const type = programHeaders.readUInt32LE(offset);
    const fileOffset = programHeaders.readBigUInt64LE(offset + 8);
    const virtualAddress = programHeaders.readBigUInt64LE(offset + 16);
    const fileSize = programHeaders.readBigUInt64LE(offset + 32);
    if (type === 1) loads.push({ fileOffset, virtualAddress, fileSize });
    if (type === 2) dynamicSegment = { fileOffset, fileSize };
  }
  if (!dynamicSegment) throw new Error("Node shared library has no ELF dynamic section.");
  const dynamicData = await readElfRange(Number(dynamicSegment.fileOffset), Number(dynamicSegment.fileSize));
  let stringTableAddress;
  let sonameOffset;
  for (let offset = 0; offset + 16 <= dynamicData.length; offset += 16) {
    const tag = dynamicData.readBigInt64LE(offset);
    const value = dynamicData.readBigUInt64LE(offset + 8);
    if (tag === 0n) break;
    if (tag === 5n) stringTableAddress = value;
    if (tag === 14n) sonameOffset = value;
  }
  if (stringTableAddress === undefined || sonameOffset === undefined) {
    throw new Error("Node shared library has no ELF SONAME.");
  }
  const stringTableLoad = loads.find(
    (load) => stringTableAddress >= load.virtualAddress && stringTableAddress < load.virtualAddress + load.fileSize,
  );
  if (!stringTableLoad) throw new Error("Node shared-library ELF string table is not file-backed.");
  const sonameFileOffset = Number(stringTableLoad.fileOffset + stringTableAddress - stringTableLoad.virtualAddress + sonameOffset);
  const sonameData = await readElfRange(sonameFileOffset, 256);
  const terminator = sonameData.indexOf(0);
  if (terminator <= 0) throw new Error("Node shared-library SONAME is invalid.");
  soname = sonameData.toString("utf8", 0, terminator);
  if (!/^libnode\.so(?:\.\d+)*$/.test(soname)) {
    throw new Error(`Unexpected Node shared-library SONAME: ${soname}`);
  }
  if (metadata?.soname && metadata.soname !== soname) {
    throw new Error(`Node build metadata SONAME '${metadata.soname}' does not match ELF SONAME '${soname}'.`);
  }
} finally {
  await libraryHandle.close();
}
await stat(join(includeRoot, "node.h"));
const sonameLibrary = join(installRoot, "lib", soname);
await stat(sonameLibrary);

const runtimeRoot = resolve(packageRoot, "../mgread_plugin_runtime/ohos/src/main/cpp/node-runtime", architecture);
const stagingRoot = `${runtimeRoot}.staging-${process.pid}`;
await rm(stagingRoot, { force: true, recursive: true });
await mkdir(join(stagingRoot, "lib"), { recursive: true });
await mkdir(join(stagingRoot, "include"), { recursive: true });
await cp(sonameLibrary, join(stagingRoot, "lib", soname));
await cp(includeRoot, join(stagingRoot, "include", "node"), { recursive: true });
await writeFile(join(stagingRoot, "mgread-node-target.txt"), `${architecture}\n`);
await writeFile(join(stagingRoot, "mgread-node-soname.txt"), `${soname}\n`);
const stagedMetadata = {
  nodeVersion,
  target: `openharmony-${architecture}`,
  sharedLibrary: `lib/${soname}`,
  soname,
  moduleVersion,
  elfMachine,
};
if (metadata?.sourceCommit) stagedMetadata.sourceCommit = metadata.sourceCommit;
await writeFile(join(stagingRoot, "mgread-node-build.json"), `${JSON.stringify(stagedMetadata, null, 2)}\n`);

async function copyDirectory(sourceRoot, destinationRoot) {
  await mkdir(destinationRoot, { recursive: true });
  for (const entry of await readdir(sourceRoot, { withFileTypes: true })) {
    const sourcePath = join(sourceRoot, entry.name);
    const destinationPath = join(destinationRoot, entry.name);
    if (entry.isDirectory()) {
      await copyDirectory(sourcePath, destinationPath);
    } else if (entry.isFile()) {
      await cp(sourcePath, destinationPath);
    } else {
      throw new Error(`Unsupported Node header entry: ${sourcePath}`);
    }
  }
}

await mkdir(runtimeRoot, { recursive: true });
await mkdir(join(runtimeRoot, "lib"), { recursive: true });
await cp(join(stagingRoot, "lib", soname), join(runtimeRoot, "lib", soname));
await copyDirectory(join(stagingRoot, "include", "node"), join(runtimeRoot, "include", "node"));
await cp(join(stagingRoot, "mgread-node-build.json"), join(runtimeRoot, "mgread-node-build.json"));
await cp(join(stagingRoot, "mgread-node-target.txt"), join(runtimeRoot, "mgread-node-target.txt"));
await cp(join(stagingRoot, "mgread-node-soname.txt"), join(runtimeRoot, "mgread-node-soname.txt"));
for (const entry of await readdir(join(runtimeRoot, "lib"), { withFileTypes: true })) {
  if (entry.isFile() && /^libnode\.so(?:\.\d+)*$/.test(entry.name) && entry.name !== soname) {
    await rm(join(runtimeRoot, "lib", entry.name), { force: true });
  }
}
await rm(stagingRoot, { force: true, recursive: true });

process.stdout.write(`Staged Node 26.10.0 OpenHarmony ${architecture} host input at ${runtimeRoot}.\n`);
