#!/usr/bin/env node
/*
 * Compare cross-platform consistency manifests produced by
 * tests/consistency.mjs on different operating systems.
 *
 *   node tests/consistency.check.mjs artifacts/consistency
 *
 * Canonical digests are strict; metric differences add field-level diagnostics.
 * CI requires both --require-platforms=win32,linux; local single-platform runs
 * may skip comparison, but their CLI result must still be successful.
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const TOLERANCE = 1e-12;

const ARTIFACTS = ['json', 'csv', 'dxf', 'svg'];
const CLI_ARTIFACTS = ['csv', 'dxf', 'svg', 'input'];
const CLI_FILES = ['input.json', 'profile.csv', 'profile.dxf', 'profile.svg', 'report.json'];

function validateManifest(manifest, name) {
  const fail = message => { throw new Error(`${name}: ${message}`); };
  if (manifest?.manifest !== 'mooncam.consistency.v1') fail('unsupported manifest format');
  if (typeof manifest.platform !== 'string' || !manifest.platform || typeof manifest.arch !== 'string' || !manifest.arch) fail('platform/arch missing');
  if (!Array.isArray(manifest.fixtures) || !manifest.fixtures.length) fail('fixtures missing or empty');
  const names = new Set();
  const hashes = (value, keys, label) => {
    for (const key of keys) if (typeof value?.[key] !== 'string' || !/^[a-f0-9]{64}$/.test(value[key])) fail(`${label}.${key}: invalid SHA-256`);
  };
  if (typeof manifest.canonical_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(manifest.canonical_sha256)) fail('invalid manifest SHA-256');
  for (const entry of manifest.fixtures) {
    if (!entry || typeof entry.name !== 'string' || !entry.name || names.has(entry.name)) fail('fixture names missing or duplicated');
    names.add(entry.name);
    hashes(entry.canonical_sha256, ARTIFACTS, `${entry.name}.canonical_sha256`);
    hashes(entry.raw_sha256, ARTIFACTS, `${entry.name}.raw_sha256`);
    if (!entry.metrics || typeof entry.metrics.state !== 'string') fail(`${entry.name}: metrics/state missing`);
    for (const key of ['max_pressure_deg', 'min_offset_factor', 'sample_count']) if (typeof entry.metrics[key] !== 'number' || !Number.isFinite(entry.metrics[key])) fail(`${entry.name}: invalid metric ${key}`);
  }
  if (manifest.cli?.ok !== true || manifest.cli.status !== 0) fail('CLI did not succeed (requires ok=true and status=0)');
  if (!Array.isArray(manifest.cli.files) || !CLI_FILES.every(file => manifest.cli.files.includes(file))) fail('CLI output files missing');
  hashes(manifest.cli.canonical_sha256, CLI_ARTIFACTS, 'cli.canonical_sha256');
}

function options(args) {
  let directory;
  let required = [];
  for (const arg of args) {
    if (arg.startsWith('--require-platforms=')) {
      if (required.length) throw new Error('required platform list specified more than once');
      required = arg.slice('--require-platforms='.length).split(',');
      if (required.some(value => !/^[a-z0-9_-]+$/.test(value)) || new Set(required).size !== required.length) throw new Error('invalid required platform list');
    } else if (arg.startsWith('--')) throw new Error(`unknown option: ${arg}`);
    else if (directory) throw new Error('expected one manifest directory');
    else directory = arg;
  }
  return {directory: directory || join(process.cwd(), 'artifacts', 'consistency'), required};
}

function load(directory) {
  const files = readdirSync(directory).filter(name => name.startsWith('manifest-') && name.endsWith('.json'));
  if (files.length === 0) throw new Error(`no manifests under ${directory}`);
  return files.map(name => {
    const path = join(directory, name);
    if (!statSync(path).isFile()) throw new Error(`${path} is not a file`);
    const manifest = JSON.parse(readFileSync(path, 'utf8'));
    validateManifest(manifest, name);
    return { name, manifest };
  });
}

function numericDifference(left, right, path, differences) {
  if (typeof left === 'number' && typeof right === 'number') {
    const scale = Math.max(1, Math.abs(left), Math.abs(right));
    const relative = Math.abs(left - right) / scale;
    if (relative > TOLERANCE) {
      differences.push({ path, left, right, relative });
    }
    return;
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    if (left.length !== right.length) {
      differences.push({ path, note: `length ${left.length} != ${right.length}` });
      return;
    }
    for (let index = 0; index < left.length; index += 1) {
      numericDifference(left[index], right[index], `${path}[${index}]`, differences);
    }
    return;
  }
  if (left && right && typeof left === 'object' && typeof right === 'object') {
    for (const key of new Set([...Object.keys(left), ...Object.keys(right)])) {
      numericDifference(left[key], right[key], path ? `${path}.${key}` : key, differences);
    }
    return;
  }
  if (!Object.is(left, right)) differences.push({ path, left, right });
}

function compare(leftEntry, rightEntry) {
  const problems = [];
  for (const artifact of ['json', 'csv', 'dxf', 'svg']) {
    const a = leftEntry.canonical_sha256[artifact];
    const b = rightEntry.canonical_sha256[artifact];
    if (a !== b) problems.push(`${artifact} digest ${a.slice(0, 12)} != ${b.slice(0, 12)}`);
  }
  const metricDifferences = [];
  numericDifference(leftEntry.metrics, rightEntry.metrics, 'metrics', metricDifferences);
  for (const difference of metricDifferences) {
    problems.push(`${difference.path}: ${difference.left} vs ${difference.right}`);
  }
  return problems;
}

function compareCli(left, right) {
  const problems = [];
  if (!left || !right) return ['CLI section missing'];
  if (left.ok !== true || right.ok !== true || left.status !== 0 || right.status !== 0) return ['CLI did not succeed on both platforms'];
  if (left.ok && right.ok) {
    if (left.files.join(',') !== right.files.join(',')) {
      problems.push(`cli files ${left.files.join(',')} != ${right.files.join(',')}`);
    }
    for (const artifact of ['csv', 'dxf', 'svg', 'input']) {
      if (left.canonical_sha256[artifact] !== right.canonical_sha256[artifact]) {
        problems.push(`cli ${artifact} digest differs`);
      }
    }
  }
  return problems;
}

function main() {
  const {directory, required} = options(process.argv.slice(2));
  const manifests = load(directory);
  console.log(`comparing ${manifests.length} manifest(s) in ${directory}`);
  for (const { name, manifest } of manifests) {
    console.log(`  ${name}: ${manifest.platform}/${manifest.arch} node ${manifest.node} moonc ${manifest.moonc}`);
  }
  const identities = new Set();
  const platforms = new Set();
  for (const {manifest} of manifests) {
    const identity = `${manifest.platform}/${manifest.arch}`;
    if (identities.has(identity)) throw new Error(`duplicate platform/arch manifest: ${identity}`);
    identities.add(identity); platforms.add(manifest.platform);
  }
  const missing = required.filter(platform => !platforms.has(platform));
  if (missing.length) throw new Error(`missing required platform(s): ${missing.join(', ')}`);
  if (manifests.length < 2) {
    console.log('only one platform present; nothing to compare (pass the artifact directory with all manifests)');
    return 0;
  }

  let failures = 0;
  const reference = manifests[0];
  for (const candidate of manifests.slice(1)) {
    const label = `${reference.manifest.platform} vs ${candidate.manifest.platform}`;
    const problems = [];
    if (reference.manifest.fixtures.length !== candidate.manifest.fixtures.length) {
      problems.push(`fixture count ${reference.manifest.fixtures.length} != ${candidate.manifest.fixtures.length}`);
    }
    const byName = new Map(candidate.manifest.fixtures.map(entry => [entry.name, entry]));
    for (const entry of reference.manifest.fixtures) {
      const other = byName.get(entry.name);
      if (!other) {
        problems.push(`fixture ${entry.name} is missing on ${candidate.manifest.platform}`);
        continue;
      }
      for (const problem of compare(entry, other)) problems.push(`${entry.name}: ${problem}`);
    }
    for (const problem of compareCli(reference.manifest.cli, candidate.manifest.cli)) problems.push(problem);

    if (problems.length === 0) {
      console.log(`${label}: identical (canonical ${reference.manifest.canonical_sha256.slice(0, 16)})`);
      const rawEqual = reference.manifest.fixtures.every(entry => {
        const other = byName.get(entry.name);
        return other && ['json', 'csv', 'dxf', 'svg'].every(artifact => entry.raw_sha256[artifact] === other.raw_sha256[artifact]);
      });
      if (!rawEqual) {
        console.log(`${label}: byte digests differ but canonical (15 significant digits, LF) digests match`);
      }
    } else {
      failures += problems.length;
      console.error(`${label}: ${problems.length} difference(s)`);
      for (const problem of problems.slice(0, 20)) console.error(`  - ${problem}`);
    }
  }
  return failures === 0 ? 0 : 1;
}

try { process.exitCode = main(); } catch (error) { console.error(`consistency check failed: ${error.message}`); process.exitCode = 1; }
