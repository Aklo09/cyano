import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
if (args.length > 1 || (args.length === 1 && args[0] !== '--check')) {
  throw new Error('Usage: node tools/build-planner.mjs [--check]');
}
const result = await build({
  absWorkingDir: root,
  entryPoints: ['tools/planner-entry.ts'],
  bundle: true,
  write: false,
  format: 'iife',
  globalName: 'FBPlanner',
  platform: 'neutral',
  target: 'es2020',
  charset: 'utf8',
  legalComments: 'inline',
  metafile: true,
  banner: { js: '// Generated from fpsr 2f7dc70f2681de530402556f757006e904e692d5 (MIT). See tools/vendor/fpsr/LICENSE.' },
});
const inputs = Object.keys(result.metafile.inputs).sort();
if (inputs.some(input => !input.startsWith('tools/vendor/fpsr/packages/renderer/src/') && input !== 'tools/planner-entry.ts')) {
  throw new Error('Planner bundle includes a dependency outside the reviewed source boundary');
}
if (Object.values(result.metafile.outputs).some(output => output.imports.length > 0)) {
  throw new Error('Planner bundle retains external imports');
}
const js = result.outputFiles[0].contents;
const metadata = Buffer.from(JSON.stringify({
  schema: 1,
  plannerRevision: '2f7dc70f2681de530402556f757006e904e692d5',
  sha256: createHash('sha256').update(js).digest('hex'),
  inputs: await Promise.all(inputs.map(async file => ({
    file, sha256: createHash('sha256').update(await readFile(path.join(root, file))).digest('hex'),
  }))),
}, null, 2) + '\n');
const directory = path.join(root, 'Sources/PreviewRenderer/Resources');
if (!args.includes('--check')) await mkdir(directory, { recursive: true });
const license = await readFile(path.join(root, 'tools/vendor/fpsr/LICENSE'));
for (const [name, bytes] of [['planner.js', js], ['planner.json', metadata], ['fpsr-LICENSE.txt', license]]) {
  const filename = path.join(directory, name);
  if (args.includes('--check')) {
    if (!Buffer.from(bytes).equals(await readFile(filename))) throw new Error(`Stale planner resource: ${name}`);
  } else {
    await writeFile(filename, bytes);
  }
}
console.log(`Planner ${args.includes('--check') ? 'verified' : 'built'}: ${inputs.length} local inputs, ${js.length} bytes, no external imports.`);
