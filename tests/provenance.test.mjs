import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {run,contract} from '../web/engine.js';
const meta=JSON.parse(contract()).generator;
test('compiled engine provenance matches module and all result paths',()=>{
 const version=readFileSync(new URL('../moon.mod',import.meta.url),'utf8').match(/^version\s*=\s*"([^"]+)"/m)[1];
 assert.equal(meta.source_digest,readFileSync(new URL('../version.mbt',import.meta.url),'utf8').match(/sha256:[a-f0-9]{64}/)[0]);
 assert.equal(meta.name,'MoonCam');assert.equal(meta.version,version);assert.match(meta.source_digest,/^sha256:[a-f0-9]{64}$/);
 for(const name of ['workshop','pressure-limit','size-search']){
  const input=JSON.parse(readFileSync(new URL(`../examples/${name}.json`,import.meta.url),'utf8'));
  const response=JSON.parse(run(JSON.stringify({...input,outputs:[]})));
  assert.deepEqual(response.generator,meta);assert.deepEqual(response.result.generator,meta);
 }
 assert.deepEqual(JSON.parse(run('{')).generator,meta);
});
test('CLI persisted report preserves compiled engine provenance',()=>{
 const dir=mkdtempSync(join(tmpdir(),'mooncam-provenance-'));
 try{
  const result=spawnSync(process.execPath,['bin/mooncam.mjs','examples/workshop.json','--out',dir],{cwd:new URL('../',import.meta.url),encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  const saved=JSON.parse(readFileSync(join(dir,'report.json'),'utf8'));
  assert.deepEqual(saved.generator,meta);assert.deepEqual(saved.result.generator,meta);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
