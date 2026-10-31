#!/usr/bin/env node
/*
 * Cross-platform consistency manifest.
 *
 * The same fixture set is evaluated on every CI operating system, and each run
 * writes a manifest of canonical digests.  "Canonical" means: line endings
 * normalised to LF, keys sorted, and every number reduced to 15 significant
 * digits (double precision keeps ~15-17, so this hides last-bit formatting
 * differences between C libraries while still exposing any real difference).
 *
 * A separate step (tests/consistency.check.mjs) compares the manifests and
 * fails the build when two systems disagree.  Raw digests are recorded too, so
 * the report can say whether the bytes were identical or only numerically
 * equivalent.
 */

import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { run } from '../web/engine.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const artifacts = join(root, 'artifacts', 'consistency');
const SIGNIFICANT = 15;

const digest = text => createHash('sha256').update(text, 'utf8').digest('hex');

/** Reduce a numeric token to a canonical, precision-limited string. */
function canonicalNumber(text) {
  const value = Number(text);
  if (!Number.isFinite(value)) return text.trim();
  return Number(value.toPrecision(SIGNIFICANT)).toString();
}

function normalizeLineEndings(text) {
  return text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return `{${keys.map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) return JSON.stringify(String(value));
    return Number(value.toPrecision(SIGNIFICANT)).toString();
  }
  return JSON.stringify(value);
}

const NUMBER = /-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/g;

function canonicalCsv(text) {
  const lines = normalizeLineEndings(text).trimEnd().split('\n');
  return lines
    .map((line, index) => (index === 0 ? line : line.split(',').map(canonicalNumber).join(',')))
    .join('\n');
}

function canonicalDxf(text) {
  return normalizeLineEndings(text)
    .trimEnd()
    .split('\n')
    .map(line => (line.trim() !== '' && Number.isFinite(Number(line)) ? canonicalNumber(line) : line))
    .join('\n');
}

function canonicalSvg(text) {
  return normalizeLineEndings(text)
    .trimEnd()
    .replace(NUMBER, match => canonicalNumber(match));
}

/** Strip host-specific fields before hashing a report. */
function stripVolatile(report) {
  const clone = structuredClone(report);
  delete clone.input;
  return clone;
}

function fixtures() {
  const names = ['workshop', 'pressure-limit', 'offset-follower', 'size-search'];
  const base = names.map(name => ({
    name,
    input: JSON.parse(readFileSync(join(root, 'examples', `${name}.json`), 'utf8')),
  }));
  // Two generated fixtures with a mixed law sequence and a non-zero offset, so
  // the manifest is not limited to the shipped examples.
  const generated = {
    action: 'analyze',
    units: 'mm',
    base_radius_mm: 63.5,
    roller_radius_mm: 6.25,
    offset_mm: -11.5,
    rpm: 123.456,
    resolution: 720,
    pressure_limit_deg: 32.5,
    segments: [
      { angle_deg: 72, lift_mm: 17.25, law: 'cycloidal' },
      { angle_deg: 48, lift_mm: 0, law: '345' },
      { angle_deg: 120, lift_mm: -17.25, law: '4567' },
      { angle_deg: 120, lift_mm: 0, law: 'cycloidal' },
    ],
  };
  return [...base, { name: 'generated-mixed', input: generated }];
}

function collect() {
  mkdirSync(artifacts, { recursive: true });
  const entries = [];
  for (const { name, input } of fixtures()) {
    const payload = { ...input, outputs: ['points', 'csv', 'svg', 'dxf'], include_input: false };
    const raw = run(JSON.stringify(payload));
    const parsed = JSON.parse(raw);
    if (!parsed.ok) throw new Error(`fixture ${name} failed: ${parsed.error_code} ${parsed.error}`);
    const result = parsed.result;
    const canonical = {
      json: canonicalJson(stripVolatile(result)),
      csv: canonicalCsv(result.csv),
      dxf: canonicalDxf(result.dxf),
      svg: canonicalSvg(result.svg),
    };
    entries.push({
      name,
      canonical_sha256: {
        json: digest(canonical.json),
        csv: digest(canonical.csv),
        dxf: digest(canonical.dxf),
        svg: digest(canonical.svg),
      },
      raw_sha256: {
        json: digest(raw),
        csv: digest(result.csv),
        dxf: digest(result.dxf),
        svg: digest(result.svg),
      },
      metrics: {
        state: result.state,
        max_pressure_deg: result.max_pressure_deg,
        min_offset_factor: result.min_offset_factor,
        sample_count: result.sample_count,
      },
    });
  }

  // CLI file path: the files written to disk must match the in-memory strings
  // after canonicalisation, on every platform and with the platform newline.
  const cli = cliCheck(fixtures()[0].input);
  const manifest = {
    manifest: 'mooncam.consistency.v1',
    platform: process.platform,
    arch: process.arch,
    node: process.version,
    moonc: readToolchainPin(),
    fixtures: entries,
    cli,
    canonical_sha256: digest(entries.map(entry => `${entry.name}:${entry.canonical_sha256.json}:${entry.canonical_sha256.csv}:${entry.canonical_sha256.dxf}:${entry.canonical_sha256.svg}`).join('|')),
  };
  const file = join(artifacts, `manifest-${process.platform}-${process.arch}.json`);
  writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  return { file, manifest };
}

function readToolchainPin() {
  try {
    return readFileSync(join(root, '.moonbit-version'), 'utf8').trim();
  } catch {
    return 'unknown';
  }
}

function cliCheck(input) {
  const directory = mkdtempSync(join(tmpdir(), 'mooncam-consistency-'));
  try {
    const file = join(directory, 'input.json');
    writeFileSync(file, JSON.stringify(input), 'utf8');
    const out = join(directory, 'out');
    const completed = spawnSync(process.execPath, [join(root, 'bin', 'mooncam.mjs'), file, '--out', out], {
      cwd: root,
      stdio: 'ignore',
    });
    if (completed.status !== 0) return { ok: false, status: completed.status };
    const files = readdirSync(out).sort();
    const read = name => readFileSync(join(out, name), 'utf8');
    return {
      ok: true,
      status: completed.status,
      files,
      canonical_sha256: {
        csv: digest(canonicalCsv(read('profile.csv'))),
        dxf: digest(canonicalDxf(read('profile.dxf'))),
        svg: digest(canonicalSvg(read('profile.svg'))),
        input: digest(canonicalJson(JSON.parse(read('input.json')))),
      },
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

const { file, manifest } = collect();
console.log(`consistency manifest: ${file}`);
console.log(`platform ${manifest.platform}/${manifest.arch} node ${manifest.node}`);
for (const entry of manifest.fixtures) {
  console.log(
    `  ${entry.name.padEnd(16)} state=${entry.metrics.state.padEnd(16)} ` +
      `max_pressure=${entry.metrics.max_pressure_deg.toFixed(6)} ` +
      `json=${entry.canonical_sha256.json.slice(0, 12)}`,
  );
}
console.log(`canonical ${manifest.canonical_sha256.slice(0, 16)}`);
if (!manifest.cli.ok) {
  console.error('CLI export check failed');
  process.exit(1);
}
