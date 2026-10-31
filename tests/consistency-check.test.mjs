import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const checker=fileURLToPath(new URL('./consistency.check.mjs',import.meta.url));
const sha='a'.repeat(64);
const hashes=keys=>Object.fromEntries(keys.map(key=>[key,sha]));
const make=platform=>({manifest:'mooncam.consistency.v1',platform,arch:'x64',node:'v22.0.0',moonc:'0.10.16+b1a0e846e',canonical_sha256:sha,
 fixtures:[{name:'workshop',canonical_sha256:hashes(['json','csv','dxf','svg']),raw_sha256:hashes(['json','csv','dxf','svg']),metrics:{state:'accepted_sampled',max_pressure_deg:27.6,min_offset_factor:0.8,sample_count:721}}],
 cli:{ok:true,status:0,files:['input.json','profile.csv','profile.dxf','profile.svg','report.json'],canonical_sha256:hashes(['csv','dxf','svg','input'])}});
function execute(manifests,{strict=true,args=[]}={}){
 const directory=mkdtempSync(join(tmpdir(),'mooncam-consistency-check-'));
 try{
  manifests.forEach((manifest,i)=>writeFileSync(join(directory,`manifest-${i}.json`),JSON.stringify(manifest)));
  return spawnSync(process.execPath,[checker,directory,...(strict?['--require-platforms=win32,linux']:[]),...args],{encoding:'utf8'});
 }finally{
  assert.ok(resolve(directory).startsWith(resolve(tmpdir())+sep+'mooncam-consistency-check-'));
  rmSync(directory,{recursive:true,force:true});
 }
}
function fails(result,pattern){assert.equal(result.status,1,result.stdout+result.stderr);assert.match(result.stderr,pattern);}

test('strict comparison accepts successful Windows and Linux manifests',()=>{
 const result=execute([make('win32'),make('linux')]);assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/identical/);
});
test('local single platform may skip, but strict comparison requires both platforms',()=>{
 const local=execute([make('win32')],{strict:false});assert.equal(local.status,0,local.stderr);assert.match(local.stdout,/only one platform/);
 fails(execute([make('win32')]),/missing required platform.*linux/);
 fails(execute([make('linux')]),/missing required platform.*win32/);
});
test('two copies of one platform cannot replace the missing platform',()=>{
 fails(execute([make('win32'),make('win32')]),/duplicate platform\/arch/);
 const second=make('win32');second.arch='arm64';fails(execute([make('win32'),second]),/missing required platform.*linux/);
});
test('identical CLI failures, one-sided failure and nonzero status all fail',()=>{
 for(const side of ['both','win32','linux','status']){
  const a=make('win32'),b=make('linux');
  if(side==='both'||side==='win32')a.cli={ok:false,status:1};
  if(side==='both'||side==='linux')b.cli={ok:false,status:1};
  if(side==='status')b.cli.status=2;
  fails(execute([a,b]),/CLI did not succeed/);
 }
 const single=make('win32');single.cli.ok=false;fails(execute([single],{strict:false}),/CLI did not succeed/);
});
test('missing CLI data, output files and digests cannot pass',()=>{
 for(const change of [m=>delete m.cli,m=>m.cli.files=[],m=>delete m.cli.canonical_sha256.dxf]){
  const a=make('win32'),b=make('linux');change(a);change(b);fails(execute([a,b]),/CLI|cli/);
 }
});
test('empty or malformed manifests are rejected even when identical',()=>{
 fails(execute([]),/no manifests/);
 for(const change of [m=>m.fixtures=[],m=>m.fixtures.push(structuredClone(m.fixtures[0])),m=>delete m.fixtures[0].canonical_sha256.svg,m=>m.manifest='wrong',m=>m.fixtures[0].metrics.max_pressure_deg=null]){
  const a=make('win32'),b=make('linux');change(a);change(b);fails(execute([a,b]),/consistency check failed/);
 }
});
test('canonical output or CLI digest mismatch fails',()=>{
 const a=make('win32'),b=make('linux');b.fixtures[0].canonical_sha256.svg='b'.repeat(64);fails(execute([a,b]),/svg digest/);
 const c=make('linux');c.cli.canonical_sha256.csv='b'.repeat(64);fails(execute([a,c]),/cli csv digest/);
});
test('state and material numeric differences are not silently ignored',()=>{
 const a=make('win32'),b=make('linux');b.fixtures[0].metrics.state='rejected';fails(execute([a,b]),/metrics.state/);
 const c=make('linux');c.fixtures[0].metrics.max_pressure_deg+=0.1;fails(execute([a,c]),/metrics.max_pressure_deg/);
});
test('raw byte differences with matching canonical outputs remain allowed',()=>{
 const a=make('win32'),b=make('linux');b.fixtures[0].raw_sha256.svg='b'.repeat(64);
 const result=execute([a,b]);assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/byte digests differ/);
 fails(execute([a,b],{args:['--require-platform=win32']}),/unknown option/);
});
