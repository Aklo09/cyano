import { spawn } from 'node:child_process';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

const root = fileURLToPath(new URL('../../', import.meta.url));
const { values } = parseArgs({ options: {
  factorio: { type: 'string' }, output: { type: 'string' },
  check: { type: 'boolean' }, help: { type: 'boolean' },
} });
if (values.help) {
  console.log('Usage: node tools/asset-preparation/build-assets.mjs --check\n       node tools/asset-preparation/build-assets.mjs --factorio <app Contents> --output <new private directory>');
  process.exit(0);
}
const upstream = path.join(root, 'tools/vendor/fpsr');
const pathsUrl = pathToFileURL(path.join(upstream, 'tools/pipeline/src/paths.ts')).href;
const distillUrl = pathToFileURL(path.join(upstream, 'tools/pipeline/src/distill.ts')).href;
const tsx = pathToFileURL(path.join(root, 'tools/node_modules/tsx/dist/loader.mjs')).href;

function run(command, argv) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, argv, { stdio: 'inherit' });
    child.on('error', reject);
    child.on('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`${command}: exit ${code}, signal ${signal}`)));
  });
}

if (values.check) {
  await run(process.execPath, ['--import', tsx, '--input-type=module', '--eval',
    `Promise.all([import(${JSON.stringify(pathsUrl)}), import(${JSON.stringify(distillUrl)})]).then(([paths, distill]) => { if (typeof paths.configurePipelinePaths !== 'function' || typeof distill.distillAndPack !== 'function') throw new Error('Missing pipeline exports'); console.log('Local asset pipeline imports successfully; no game was launched.'); });`]);
  process.exit(0);
}
if (!values.factorio || !values.output) throw new Error('Both --factorio and --output are required. Use --help.');
const factorio = path.resolve(values.factorio);
const output = path.resolve(values.output);
const privateRoot = path.join(root, 'private-assets');
const relative = path.relative(privateRoot, output);
if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
  throw new Error('Output must be a new directory underneath this project\'s private-assets/ directory.');
}
const info = JSON.parse(await readFile(path.join(factorio, 'data/base/info.json'), 'utf8'));
if (info.version !== '2.1.23') throw new Error('This preparation profile requires Factorio 2.1.23.');
await mkdir(path.dirname(output), { recursive: true });
await mkdir(output); // Refuse existing outputs, preserving previous assets and evidence.
const mods = ['base', 'elevated-rails', 'quality', 'recycler', 'space-age'];
const work = path.join(output, 'game-work');
const modDir = path.join(work, 'mods');
await mkdir(modDir, { recursive: true });
const config = path.join(work, 'config.ini');
await writeFile(config, `[path]\nread-data=${path.join(factorio, 'data')}\nwrite-data=${work}\n`);
await writeFile(path.join(modDir, 'mod-list.json'), JSON.stringify({ mods: mods.map(name => ({ name, enabled: true })) }, null, 2));
await run(path.join(factorio, 'MacOS/factorio'), ['--config', config, '--mod-directory', modDir, '--dump-data', '--disable-audio']);
await copyFile(path.join(work, 'script-output/data-raw-dump.json'), path.join(output, 'data-raw-dump.json'));
await writeFile(path.join(output, 'data-raw-dump.meta.json'), JSON.stringify({ gameVersion: info.version, mods, isolatedGameProfile: true }, null, 2));
const runner = path.join(output, 'distill.mts');
await writeFile(runner, `import { configurePipelinePaths } from ${JSON.stringify(pathsUrl)};\nimport { distillAndPack } from ${JSON.stringify(distillUrl)};\nconfigurePipelinePaths(${JSON.stringify({ factorioPath: factorio, assetsOut: output, mods })});\nawait distillAndPack();\n`);
await run(process.execPath, ['--import', tsx, runner]);
console.log(`Private asset bundle: ${path.join(output, info.version)}`);
