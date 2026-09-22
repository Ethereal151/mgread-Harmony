import { mkdir, writeFile, access } from 'node:fs/promises';

const dataRoot = process.argv
  .find((argument) => argument.startsWith('--data-root='))
  ?.slice('--data-root='.length);
if (dataRoot === undefined) {
  process.exit(71);
}

await mkdir(dataRoot, { recursive: true });
const entered = `${dataRoot}/startup-gate-entered`;
const release = `${dataRoot}/startup-gate-release`;
await writeFile(entered, 'entered');
while (true) {
  try {
    await access(release);
    process.exit(73);
  } catch {
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
