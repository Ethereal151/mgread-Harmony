// Stage the JavaScript Runtime bundle for the OHOS Flutter plugin.
// The native OHOS host reads this directory after Flutter copies it into the
// application's rawfile resources.
import { createHash } from "node:crypto";
import { cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

async function directoryFingerprint(root) {
  const files = [];

  async function collect(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const file = resolve(directory, entry.name);
      if (entry.isDirectory()) await collect(file);
      else if (entry.isFile()) files.push(file);
    }
  }

  await collect(root);
  const hash = createHash("sha256");
  for (const file of files.sort()) {
    hash.update(relative(root, file).replaceAll("\\", "/"));
    hash.update("\0");
    hash.update(await readFile(file));
    hash.update("\0");
  }
  return hash.digest("hex");
}

const runtimeRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const packageJson = JSON.parse(await readFile(resolve(runtimeRoot, "package.json"), "utf8"));
const assetRoot = resolve(runtimeRoot, "../mgread_plugin_runtime/assets/runtime/ohos");
const assetDist = resolve(assetRoot, "dist");
const assetNodeModules = resolve(assetRoot, "node_modules");
const defaultPluginsRoot = resolve(assetRoot, "default-plugins");

await rm(assetDist, { force: true, recursive: true });
await rm(assetNodeModules, { force: true, recursive: true });
await rm(defaultPluginsRoot, { force: true, recursive: true });
await mkdir(assetRoot, { recursive: true });
await writeFile(resolve(assetRoot, "package.json"), '{\n  "type": "module"\n}\n');
await cp(resolve(runtimeRoot, "dist"), assetDist, { recursive: true });

// The shared Runtime Core is compiled from the desktop source tree. OHOS ships
// a separate native Node 26.10.0 host, so patch only the copied OHOS metadata
// when an older staged dist still carries the historical Node 24 marker; the
// desktop dist remains unchanged. The conditional keeps staging idempotent
// after the shared desktop launcher has itself moved to Node 26.
const ohosRuntimeVersionModule = resolve(assetDist, "runtime-version.js");
const desktopRuntimeVersionSource = await readFile(ohosRuntimeVersionModule, "utf8");
const ohosNodeVersion = "26.10.0";
const ohosRuntimeVersionSource = desktopRuntimeVersionSource.includes(`"${ohosNodeVersion}"`)
  ? desktopRuntimeVersionSource
  : desktopRuntimeVersionSource.replaceAll('"24.16.0"', `"${ohosNodeVersion}"`);
if (!ohosRuntimeVersionSource.includes(`"${ohosNodeVersion}"`)) {
  throw new Error(`OHOS Runtime version metadata does not contain Node ${ohosNodeVersion}.`);
}
await writeFile(ohosRuntimeVersionModule, ohosRuntimeVersionSource);
const assetFingerprint = await directoryFingerprint(assetDist);
const runtimeAssetVersion = `${packageJson.version}-${assetFingerprint}`;
await writeFile(resolve(assetRoot, "runtime-version.txt"), `${runtimeAssetVersion}\n`);

process.stdout.write(`Staged OHOS Runtime assets for ${runtimeAssetVersion}.\n`);
