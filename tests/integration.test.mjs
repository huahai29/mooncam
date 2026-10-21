import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { run } from '../web/engine.js';
const example = name => JSON.parse(readFileSync(new URL(`../examples/${name}.json`, import.meta.url), 'utf8'));
const solve = input => JSON.parse(run(JSON.stringify(input)));
test('workshop produces locally feasible geometry and complete exports', () => {
  const r = solve(example('workshop'));
  assert.equal(r.ok, true);
  assert.equal(r.result.sampled_local_feasible, true);
  assert.equal(r.result.jerk_jumps, 0);
  assert.deepEqual(r.input, example('workshop'));
  assert.equal(JSON.parse(run(JSON.stringify(r.input))).result.max_pressure_deg, r.result.max_pressure_deg);
  assert.equal(r.result.points.length, 721);
  assert.match(r.result.csv, /pressure_rad/);
  assert.match(r.result.dxf, /LWPOLYLINE/);
});
test('small radius fails pressure constraints and bounded search finds a candidate', () => {
  assert.equal(solve(example('pressure-limit')).result.sampled_local_feasible, false);
  const r = solve(example('size-search'));
  assert.equal(r.ok, true);
  assert.equal(r.result.sampled_local_feasible, true);
  assert.equal(r.grid_step_mm, 1);
  assert.deepEqual(r.input, example('size-search'));
});
test('public boundary rejects unknown fields, fractional resolution and malformed programs', () => {
  for (const change of [{surprise: 1}, {resolution: 36.5}, {rpm: 0}, {units:'in'}, {action:'bogus'}, {segments:[]}, {offset_mm:1000}]) {
    assert.equal(solve({...example('workshop'), ...change}).ok, false, JSON.stringify(change));
  }
});
