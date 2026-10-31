#!/usr/bin/env node
/*
 * Compare cross-platform consistency manifests produced by
 * tests/consistency.mjs on different operating systems.
 *
 *   node tests/consistency.check.mjs artifacts/consistency
 *
 * Every pair of manifests must agree on the canonical digests.  When a digest
 * differs the comparison falls back to a numeric diff of the reported metrics
 * and of the export coordinates, so the failure says what moved instead of just
 * "hash mismatch".
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const TOLERANCE = 1e-12;

function load(directory) {
  const files = readdirSync(directory).filter(name => name.startsWith('manifest-') && name.endsWith('.json'));
  if (files.length === 0) throw new Error(`no manifests under ${directory}`);
  return files.map(name => {
    const path = join(directory, name);
    if (!statSync(path).isFile()) throw new Error(`${path} is not a file`);
    return { name, manifest: JSON.parse(readFileSync(path, 'utf8')) };
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
  }
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
  if (left.ok !== right.ok) problems.push(`cli ok ${left.ok} != ${right.ok}`);
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
  const directory = process.argv[2] || join(process.cwd(), 'artifacts', 'consistency');
  const manifests = load(directory);
  console.log(`comparing ${manifests.length} manifest(s) in ${directory}`);
  for (const { name, manifest } of manifests) {
    console.log(`  ${name}: ${manifest.platform}/${manifest.arch} node ${manifest.node} moonc ${manifest.moonc}`);
  }
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

process.exit(main());
