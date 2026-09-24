/**
 * Runtime-private development generation staging.
 *
 * A unique filesystem root gives Node a fresh ESM/CJS identity after a
 * successful project build. It copies only the bundled entry and declared icon;
 * it never copies a dependency tree or creates a distributable artifact.
 */
import { randomUUID } from "node:crypto";
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import { readPluginProject, type PluginPackageDescriptor } from "./plugin-package.js";

export interface StagedDevelopmentGeneration {
  readonly descriptor: PluginPackageDescriptor;
  readonly generationRoot: string;
}

/** Materializes one already-built, bundled artifact into a unique Runtime-private root. */
export async function stageDevelopmentGeneration(
  dataRoot: string,
  projectRoot: string,
  expectedDescriptor: PluginPackageDescriptor,
): Promise<StagedDevelopmentGeneration> {
  const generationRoot = resolve(
    dataRoot,
    "development-generations",
    expectedDescriptor.id,
    randomUUID(),
  );
  await mkdir(generationRoot, { recursive: true });
  try {
    const packageJson = JSON.parse(await readFile(resolve(projectRoot, "package.json"), "utf8")) as Record<string, unknown>;
    for (const key of ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies", "bundledDependencies", "bundleDependencies", "packageManager"]) delete packageJson[key];
    await writeFile(resolve(generationRoot, "package.json"), `${JSON.stringify(packageJson, null, 2)}\n`, { flag: "wx", mode: 0o444 });
    const entry = expectedDescriptor.entry;
    await mkdir(dirname(resolve(generationRoot, entry)), { recursive: true });
    await copyFile(resolve(projectRoot, entry), resolve(generationRoot, entry));
    if (expectedDescriptor.icon !== undefined) {
      await mkdir(dirname(resolve(generationRoot, expectedDescriptor.icon)), { recursive: true });
      await copyFile(resolve(projectRoot, expectedDescriptor.icon), resolve(generationRoot, expectedDescriptor.icon));
    }
    const staged = await readPluginProject(generationRoot);
    if (
      staged.descriptor.id !== expectedDescriptor.id ||
      staged.descriptor.version !== expectedDescriptor.version
    ) {
      throw new Error("Development generation descriptor changed while staging.");
    }
    return Object.freeze({
      descriptor: staged.descriptor,
      generationRoot,
    });
  } catch (error) {
    await rm(generationRoot, { force: true, recursive: true }).catch(() => {});
    throw error;
  }
}
