#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';
const args = process.argv.slice(2);
if (args.length === 0 || args[0] === '--help') {
  console.log('Usage: node bin/mooncam.mjs INPUT.json [--out DIRECTORY]\nBuild first: npm run build\nExit: 0 locally feasible, 2 locally infeasible, 1 input/runtime error.');
  process.exit(args.length ? 0 : 1);
}
try {
  if (![1, 3].includes(args.length) || (args.length === 3 && args[1] !== '--out')) throw new Error('Invalid arguments; use --help.');
  if (statSync(args[0]).size > 800000) throw new Error('Input file exceeds 800 KB.');
  const { run } = await import('../web/engine.js');
  const response = JSON.parse(run(readFileSync(args[0], 'utf8')));
  if (!response.ok) throw new Error(response.error);
  const { csv, svg, dxf, points, ...summary } = response.result;
  if (args[1] === '--out') {
    const out = resolve(args[2]);
    mkdirSync(out, { recursive: true });
    for (const [name, content] of Object.entries({ 'profile.csv': csv, 'profile.svg': svg, 'profile.dxf': dxf, 'report.json': JSON.stringify(response, null, 2) + '\n' })) {
      writeFileSync(join(out, name), content, 'utf8');
    }
    console.log(`Saved report and profiles to ${out}`);
  }
  console.log(JSON.stringify({ ...summary, tested: response.tested, grid_step_mm: response.grid_step_mm }, null, 2));
  process.exitCode = summary.sampled_local_feasible ? 0 : 2;
} catch (error) {
  console.error(`MoonCam: ${error.message}`);
  process.exitCode = 1;
}
