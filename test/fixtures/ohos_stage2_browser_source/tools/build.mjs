import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const code = await readFile(resolve(root, "index.mjs"));
const version = "0.1.1";
const ids = [
  "org.mgread.ohos.stage2.source-one",
  "org.mgread.ohos.stage2.source-two",
  "org.mgread.ohos.stage2.cookie-js",
  "org.mgread.ohos.stage2.javascript",
  "org.mgread.ohos.stage2.interaction",
];

function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  throw new Error("Unsupported canonical JSON value.");
}

function artifact(pluginId) {
  const descriptor = {
    engines: { node: ">=24 <25" },
    main: "dist/index.mjs",
    mgread: { contentKinds: ["novel"], displayName: `OHOS Stage 2 ${pluginId}`, id: pluginId, packageMode: "single-file", pluginApi: 1, schemaVersion: 1 },
    name: `@mgread-test/${pluginId.slice("org.mgread.ohos.stage2.".length)}`,
    type: "module",
    version,
  };
  const envelope = { codeBytes: code.byteLength, codeSha256: createHash("sha256").update(code).digest("hex"), descriptor, formatVersion: 1 };
  const header = Buffer.from(`// @mgread-plugin-v1 ${Buffer.from(canonicalJson(envelope)).toString("base64url")}\n`);
  return Buffer.concat([header, code]);
}

const artifacts = Object.fromEntries(ids.map((id) => [id, artifact(id).toString("base64url")]));
if (process.argv.includes("--write")) {
  const out = resolve(root, "artifacts");
  await mkdir(out, { recursive: true });
  await Promise.all(ids.map((id) => writeFile(resolve(out, `${id}-${version}.mgplugin.js`), Buffer.from(artifacts[id], "base64url"))));
}
const defineIndex = process.argv.indexOf("--write-defines");
if (defineIndex >= 0) {
  const target = process.argv[defineIndex + 1];
  if (typeof target !== "string" || target.length === 0) throw new Error("--write-defines requires a path.");
  await mkdir(dirname(resolve(target)), { recursive: true });
  await writeFile(resolve(target), `${JSON.stringify({ MGREAD_STAGE2_ARTIFACTS_JSON: JSON.stringify(artifacts) }, null, 2)}\n`);
}
process.stdout.write(`${JSON.stringify(artifacts)}\n`);
