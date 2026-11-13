import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { lstat, readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const json = async file => JSON.parse(await readFile(path.join(root, file), 'utf8'));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const provenance = await json('tools/provenance.json');
for (const file of provenance.files) {
  const filename = path.join(root, file.path);
  assert.ok((await lstat(filename)).isFile(), `Expected a regular file: ${file.path}`);
  const bytes = await readFile(filename);
  assert.equal(bytes.length, file.bytes, `Copied file size changed: ${file.path}`);
  assert.equal(sha256(bytes), file.sha256, `Copied file hash changed: ${file.path}`);
}
const planner = await json('Sources/PreviewRenderer/Resources/planner.json');
assert.equal(planner.plannerRevision, provenance.sources.fpsr.revision);
assert.equal(sha256(await readFile(path.join(root, 'Sources/PreviewRenderer/Resources/planner.js'))), planner.sha256);
for (const input of planner.inputs) {
  assert.equal(sha256(await readFile(path.join(root, input.file))), input.sha256, `Planner input changed: ${input.file}`);
}
const manifest = await json('tools/package.json');
const lock = await json('tools/package-lock.json');
assert.deepEqual(manifest.dependencies, lock.packages[''].dependencies);
for (const [name, version] of Object.entries(manifest.dependencies)) {
  assert.match(version, /^\d+\.\d+\.\d+$/, `Unpinned dependency: ${name}`);
  const installed = await json(`tools/node_modules/${name}/package.json`);
  assert.equal(installed.version, version, `Installed version mismatch: ${name}`);
}
async function inspect(directory) {
  for (const entry of await readdir(path.join(root, directory), { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'vendor') continue;
    const relative = path.join(directory, entry.name);
    if (entry.isDirectory()) await inspect(relative);
    else if (/\.(swift|mjs|ts|sh)$/.test(entry.name)) {
      const source = await readFile(path.join(root, relative), 'utf8');
      assert.ok(!source.includes('/Users/' + 'aklo/Projects/fb'), `External source path: ${relative}`);
      assert.ok(!source.includes('/private/tmp/' + 'fb-fpsr-evaluation'), `Temporary upstream path: ${relative}`);
      assert.ok(!source.includes('/private/tmp/' + 'fb-renderer-runtime'), `Temporary runtime path: ${relative}`);
    }
  }
}
await inspect('Sources');
await inspect('tools');
console.log(`Foundation verified: ${provenance.files.length} copied files, ${planner.inputs.length} planner inputs, ${Object.keys(manifest.dependencies).length} pinned development dependencies; no external project paths.`);
