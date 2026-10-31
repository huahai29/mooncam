import test from 'node:test';
import assert from 'node:assert/strict';
import {summarizeCoverage} from '../scripts/coverage-check.mjs';
const budget={max_uncovered:1,files:{'a.mbt':1,'b.mbt':0}};
const report=()=>({source_files:[{name:'a.mbt',coverage:[null,1,0]},{name:'b.mbt',coverage:[2]}]});
test('coverage summary counts instrumented core lines and excludes host examples',()=>{
 const r=report();r.source_files.push({name:'bridge/main.mbt',coverage:[0]});
 const s=summarizeCoverage(r,['a.mbt','b.mbt'],budget);
 assert.equal(s.executable,3);assert.equal(s.uncovered,1);assert.equal(s.percent,66.67);
});
test('empty, missing and duplicate coverage sources cannot pass',()=>{
 for(const r of [{source_files:[]},{source_files:[report().source_files[0]]},{source_files:[...report().source_files,report().source_files[0]]}]){
  assert.throws(()=>summarizeCoverage(r,['a.mbt','b.mbt'],budget),/empty|missing|duplicate/);
 }
 assert.throws(()=>summarizeCoverage(report(),['a.mbt','b.mbt','new.mbt'],budget),/missing/);
});
test('uncovered growth fails both per-file and aggregate budgets',()=>{
 const r=report();r.source_files[1].coverage=[0];
 assert.throws(()=>summarizeCoverage(r,['a.mbt','b.mbt'],budget),/regression/);
 assert.throws(()=>summarizeCoverage(r,['a.mbt','b.mbt'],{max_uncovered:1,files:{'a.mbt':1,'b.mbt':1}}),/total/);
});
test('malformed counters and zero executable files cannot pass',()=>{
 for(const coverage of [[-1],[null],[NaN],[1.5],['1']]){
  const r=report();r.source_files[0].coverage=coverage;
  assert.throws(()=>summarizeCoverage(r,['a.mbt','b.mbt'],budget),/invalid|no executable/);
 }
});
