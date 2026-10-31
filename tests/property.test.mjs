import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { run } from '../web/engine.js';

/*
 * Randomized property tests over the public JSON contract.
 *
 * The generator uses a fixed-seed PRNG, so a failing case reproduces from the
 * seed printed in the failure message.  The properties are invariants of the
 * contract rather than snapshots: determinism, summary/point agreement,
 * shaft-speed scaling, length scaling, acceptance monotonicity, export shape
 * and total input robustness.  The fuzz stage mutates valid requests and
 * requires a structured answer every time, so a panic or an untyped exception
 * fails the suite.
 */

const TAU = 2 * Math.PI;

function mulberry32(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function between(random, low, high) {
  return low + (high - low) * random();
}

const LAWS = ['cycloidal', '345', '4567'];

/** Alternating rise/fall pairs keep the lift non-negative and closed. */
function randomProgram(random) {
  const pairs = 1 + Math.floor(random() * 4);
  const weights = Array.from({ length: pairs * 2 }, () => between(random, 0.05, 1));
  const total = weights.reduce((sum, value) => sum + value, 0);
  const segments = [];
  for (let pair = 0; pair < pairs; pair += 1) {
    const lift = between(random, 1, 20);
    segments.push({
      angle_deg: (360 * weights[pair * 2]) / total,
      lift_mm: lift,
      law: LAWS[Math.floor(random() * LAWS.length)],
    });
    segments.push({
      angle_deg: (360 * weights[pair * 2 + 1]) / total,
      lift_mm: -lift,
      law: LAWS[Math.floor(random() * LAWS.length)],
    });
  }
  return segments;
}

function randomGeometry(random) {
  const base = between(random, 10, 200);
  const roller = between(random, 1, base * 0.3);
  const limit = base + roller;
  return {
    base_radius_mm: base,
    roller_radius_mm: roller,
    offset_mm: between(random, -0.6, 0.6) * limit,
  };
}

function analyzeRequest(geometry, segments, resolution, pressureLimit = 30) {
  return {
    action: 'analyze',
    units: 'mm',
    ...geometry,
    rpm: 60,
    resolution,
    pressure_limit_deg: pressureLimit,
    segments,
    outputs: ['points'],
  };
}

function solve(payload) {
  return JSON.parse(run(JSON.stringify(payload)));
}

function solveOk(payload, context) {
  const response = solve(payload);
  assert.equal(response.ok, true, `${context || 'request'} was rejected: ${JSON.stringify(response)}`);
  return response.result;
}

test('R1 random requests are deterministic and self-consistent', () => {
  const random = mulberry32(0x20261021);
  for (let round = 0; round < 40; round += 1) {
    const payload = analyzeRequest(
      randomGeometry(random),
      randomProgram(random),
      [36, 72, 120, 240, 720][Math.floor(random() * 5)],
    );
    const first = solve(payload);
    const second = solve(payload);
    assert.equal(first.ok, true, `round ${round} rejected`);
    assert.deepEqual(second, first, `round ${round} is not deterministic`);
    const result = first.result;
    assert.equal(result.sample_count, result.points.length);
    assert.equal(result.sampling.actual_intervals, result.points.length - 1);
    assert.equal(result.state, result.sampled_feasible ? 'accepted_sampled' : result.state);
    assert.ok(['accepted_sampled', 'rejected', 'incomplete'].includes(result.state));
    assert.ok(['complete', 'indeterminate', 'failed', 'not_checked'].includes(result.crossing_check.status));
    if (result.state === 'accepted_sampled') {
      assert.equal(result.crossing_check.status, 'complete');
      assert.equal(result.crossing_check.count, 0);
    }
    const sampled = result.points.reduce((worst, point) => Math.max(worst, Math.abs(point.pressure_deg)), 0);
    assert.ok(Math.abs(sampled - result.max_pressure_deg) <= 1e-9, 'max_pressure_deg is not the sampled maximum');
    const minFactor = result.points.reduce((worst, point) => Math.min(worst, point.offset_factor), Infinity);
    assert.ok(Math.abs(minFactor - result.min_offset_factor) <= 1e-12, 'min_offset_factor mismatch');
    for (let index = 1; index < result.points.length; index += 1) {
      assert.ok(result.points[index].theta_rad > result.points[index - 1].theta_rad, 'angles are not increasing');
    }
    assert.equal(result.points[0].theta_rad, 0);
    assert.ok(Math.abs(result.points[result.points.length - 1].theta_rad - TAU) <= 1e-15);
  }
});

test('R2 shaft speed scales the time derivatives and nothing else', () => {
  const random = mulberry32(0x5eed);
  for (let round = 0; round < 12; round += 1) {
    const payload = analyzeRequest(randomGeometry(random), randomProgram(random), 360);
    const slow = solveOk(payload, 'slow');
    const fast = solveOk({ ...payload, rpm: payload.rpm * 3 }, 'fast');
    assert.ok(Math.abs(fast.max_velocity_mm_s - slow.max_velocity_mm_s * 3) <= 1e-9 * Math.max(1, slow.max_velocity_mm_s));
    assert.ok(Math.abs(fast.max_acceleration_mm_s2 - slow.max_acceleration_mm_s2 * 9) <= 1e-9 * Math.max(1, slow.max_acceleration_mm_s2));
    assert.ok(Math.abs(fast.max_jerk_mm_s3 - slow.max_jerk_mm_s3 * 27) <= 1e-9 * Math.max(1, slow.max_jerk_mm_s3));
    assert.equal(fast.max_pressure_deg, slow.max_pressure_deg);
    assert.equal(fast.min_offset_factor, slow.min_offset_factor);
    for (let index = 0; index < slow.points.length; index += 1) {
      assert.equal(fast.points[index].x, slow.points[index].x);
      assert.equal(fast.points[index].y, slow.points[index].y);
    }
  }
});

test('R3 uniform length scaling keeps angles and scales the profile', () => {
  const random = mulberry32(0x51a7e);
  for (let round = 0; round < 10; round += 1) {
    const geometry = randomGeometry(random);
    const segments = randomProgram(random);
    const k = [0.25, 2, 7.5][round % 3];
    const base = solveOk(analyzeRequest(geometry, segments, 240), 'base');
    const scaled = solveOk(
      analyzeRequest(
        {
          base_radius_mm: geometry.base_radius_mm * k,
          roller_radius_mm: geometry.roller_radius_mm * k,
          offset_mm: geometry.offset_mm * k,
        },
        segments.map(segment => ({ ...segment, lift_mm: segment.lift_mm * k })),
        240,
      ),
      'scaled',
    );
    assert.ok(Math.abs(scaled.max_pressure_deg - base.max_pressure_deg) <= 1e-9);
    assert.ok(Math.abs(scaled.min_offset_factor - base.min_offset_factor) <= 1e-9);
    for (let index = 0; index < base.points.length; index += 1) {
      const expected = base.points[index].x * k;
      const actual = scaled.points[index].x;
      assert.ok(Math.abs(actual - expected) <= 1e-9 * Math.max(1, Math.abs(expected)), `x[${index}] did not scale`);
      const expectedY = base.points[index].y * k;
      assert.ok(Math.abs(scaled.points[index].y - expectedY) <= 1e-9 * Math.max(1, Math.abs(expectedY)));
    }
  }
});

test('R4 acceptance and pressure are monotone in their limits', () => {
  const random = mulberry32(0x11a17);
  for (let round = 0; round < 16; round += 1) {
    const geometry = randomGeometry(random);
    const segments = randomProgram(random);
    const strict = solveOk(analyzeRequest(geometry, segments, 180, 5), 'strict');
    const relaxed = solveOk(analyzeRequest(geometry, segments, 180, 89), 'relaxed');
    if (strict.sampled_feasible) {
      assert.equal(relaxed.sampled_feasible, true, 'relaxing the limit rejected a passing profile');
    }
    assert.ok(strict.max_pressure_deg >= 0);
    const larger = solveOk(
      {
        ...analyzeRequest(geometry, segments, 180),
        base_radius_mm: geometry.base_radius_mm * 4,
      },
      'larger base',
    );
    assert.ok(
      larger.max_pressure_deg <= strict.max_pressure_deg + 1e-9,
      'a larger base radius increased the maximum pressure angle',
    );
  }
});

test('R5 exports keep their declared shape and agree with the points', () => {
  const random = mulberry32(0x7e5a);
  for (let round = 0; round < 6; round += 1) {
    const payload = {
      ...analyzeRequest(randomGeometry(random), randomProgram(random), 180),
      outputs: ['points', 'csv', 'svg', 'dxf'],
    };
    const result = solveOk(payload, 'exports');
    const csvRows = result.csv.trim().split('\n');
    assert.equal(csvRows[0].split(',').length, 12, 'csv header changed');
    assert.equal(csvRows.length - 1, result.points.length, 'csv row count mismatch');
    const dxf = result.dxf.split('\n');
    const declared = Number(dxf[dxf.indexOf('90') + 1]);
    assert.equal(declared, result.points.length - 1, 'dxf vertex count mismatch');
    assert.ok(dxf.includes('LWPOLYLINE') && dxf[dxf.length - 2] === 'EOF');
    const marker = 'points="';
    const start = result.svg.indexOf(marker) + marker.length;
    const plot = result.svg.slice(start, result.svg.indexOf('"', start));
    assert.equal(plot.split(' ').filter(Boolean).length, result.points.length, 'svg point count mismatch');
  }
});

test('R6 search reports the radius it verified', () => {
  const random = mulberry32(0x3ee);
  for (let round = 0; round < 8; round += 1) {
    const geometry = randomGeometry(random);
    const segments = randomProgram(random);
    const resolution = 180;
    const request = {
      action: 'search',
      units: 'mm',
      ...geometry,
      base_radius_mm: geometry.base_radius_mm,
      rpm: 60,
      resolution,
      pressure_limit_deg: 40,
      segments,
      search: { lower_mm: 20, upper_mm: 140, intervals: 12 },
      outputs: ['points'],
    };
    const response = solve(request);
    if (!response.ok) {
      assert.ok(['no_candidate', 'check_indeterminate', 'invalid_input'].includes(response.error_code), JSON.stringify(response));
      continue;
    }
    const found = response.result;
    assert.ok(found.sampled_local_feasible, 'search returned a candidate that fails the local check');
    const radius = found.base_radius_mm;
    const direct = solveOk(
      {
        ...request,
        action: 'analyze',
        base_radius_mm: radius,
        resolution: resolution * 2,
      },
      'direct re-check',
    );
    assert.ok(
      Math.abs(direct.max_pressure_deg - found.max_pressure_deg) <= 1e-9,
      'search summary disagrees with a direct analysis at the reported radius and fine resolution',
    );
    assert.ok(Math.abs(response.grid_step_mm - (140 - 20) / 12) <= 1e-9, 'grid step does not match the request');
  }
});

test('R7 malformed and out-of-contract requests answer with typed errors', () => {
  const workshop = JSON.parse(readFileSync(new URL('../examples/workshop.json', import.meta.url), 'utf8'));
  const cases = [
    { payload: '{not json', code: 'invalid_json' },
    { payload: JSON.stringify({ ...workshop, resolution: 12.5 }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, resolution: 9999 }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, segments: [] }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, base_radius_mm: -3 }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, offset_mm: 5000 }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, surprise: true }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, action: 'render' }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, segments: [{ angle_deg: 360, lift_mm: -1, law: '345' }] }), code: 'invalid_input' },
    { payload: JSON.stringify({ ...workshop, segments: [{ angle_deg: 180, lift_mm: 10, law: 'nope' }] }), code: 'invalid_input' },
  ];
  for (const { payload, code } of cases) {
    const response = JSON.parse(run(payload));
    assert.equal(response.ok, false, `expected a failure for ${payload.slice(0, 60)}`);
    assert.equal(response.error_code, code, `wrong code for ${payload.slice(0, 60)}`);
    assert.equal(typeof response.error, 'string');
    assert.ok(response.error.length > 0);
  }
});

test('R8 fuzzed requests never escape the contract', () => {
  const random = mulberry32(0xf0f0);
  const workshop = JSON.parse(readFileSync(new URL('../examples/workshop.json', import.meta.url), 'utf8'));
  const values = [
    null, true, false, 0, -0.0, 1e-9, 1e9, -1e9, '', 'mm', '345', 'cycloidal', [], {},
    { angle_deg: 90, lift_mm: 10, law: '345' },
    [{ angle_deg: 90, lift_mm: 10, law: '345' }],
  ];
  const keys = Object.keys(workshop);
  let accepted = 0;
  for (let index = 0; index < 1500; index += 1) {
    const payload = structuredClone(workshop);
    const mutations = 1 + Math.floor(random() * 3);
    for (let step = 0; step < mutations; step += 1) {
      const choice = Math.floor(random() * 4);
      if (choice === 0) {
        payload[keys[Math.floor(random() * keys.length)]] = values[Math.floor(random() * values.length)];
      } else if (choice === 1 && Array.isArray(payload.segments) && payload.segments.length > 0) {
        const at = Math.floor(random() * payload.segments.length);
        const segment = payload.segments[at];
        const field = ['angle_deg', 'lift_mm', 'law'][Math.floor(random() * 3)];
        payload.segments[at] = { ...segment, [field]: values[Math.floor(random() * values.length)] };
      } else if (choice === 2) {
        delete payload[keys[Math.floor(random() * keys.length)]];
      } else {
        payload.resolution = Math.floor(random() * 20000);
      }
    }
    let raw;
    try {
      raw = JSON.stringify(payload);
    } catch {
      continue;
    }
    if (raw === undefined) continue;
    const started = Date.now();
    const response = JSON.parse(run(raw));
    assert.ok(Date.now() - started < 2000, `fuzz case ${index} exceeded the time budget`);
    assert.equal(typeof response.ok, 'boolean', `fuzz case ${index} lost the ok flag`);
    if (response.ok === false) {
      assert.equal(typeof response.error_code, 'string', `fuzz case ${index} lost the error code`);
      assert.ok(response.error_code.length > 0);
    } else {
      accepted += 1;
      assert.ok(response.result && typeof response.result.state === 'string', `fuzz case ${index} lost the result`);
    }
  }
  assert.ok(accepted > 0, 'the fuzz stage never produced a valid request, which would hide regressions');
});
