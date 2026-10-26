import assert from 'node:assert/strict';
import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {performance} from 'node:perf_hooks';
import {cpus,platform,arch} from 'node:os';
import {run,contract} from '../web/engine.js';
const load=name=>JSON.parse(readFileSync(new URL(`../examples/${name}.json`,import.meta.url),'utf8'));
const base=load('workshop');
const many={...base,base_radius_mm:200,resolution:4000,segments:Array.from({length:128},(_,i)=>({angle_deg:360/128,lift_mm:i%2?-1:1,law:'4567'}))};
const workloads={analyze4000:{...base,resolution:4000},segments128hi:many,search:load('size-search')};
const observations={generator:JSON.parse(contract()).generator,environment:{node:process.version,platform:platform(),arch:arch(),cpu:cpus()[0]?.model},method:'Summary-only end-to-end median, 3 warmups and 7 samples; includes JSON and topology. Broad 2000 ms smoke ceiling, not a microbenchmark or universal complexity bound.',workloads:{}};
for(const [name,input] of Object.entries(workloads)){
 const wire=JSON.stringify({...input,outputs:[]});
 for(let i=0;i<3;i++)run(wire);
 const times=[];let raw;
 for(let i=0;i<7;i++){const start=performance.now();raw=run(wire);times.push(performance.now()-start);}
 times.sort((a,b)=>a-b);const median=times[3];const response=JSON.parse(raw);
 assert.equal(response.ok,true,`${name}: calculation must succeed`);
 assert.equal(response.result.crossing_check.status,'complete',`${name}: topology must complete`);
 for(const field of ['points','csv','svg','dxf'])assert.equal(field in response.result,false,`${name}: unexpected heavy output ${field}`);
 assert.ok(Buffer.byteLength(raw)<25000,`${name}: summary unexpectedly large`);
 assert.ok(median<2000,`${name}: summary median ${median} ms exceeds broad CI smoke budget`);
 if(name==='search'){assert.equal(response.result.base_radius_mm,36);assert.equal(response.tested,32);}
 else assert.ok(response.result.sample_count>=4001&&response.result.sample_count<=4129);
 observations.workloads[name]={median_ms:median,bytes:Buffer.byteLength(raw),sample_count:response.result.sample_count};
}
mkdirSync(new URL('../artifacts/',import.meta.url),{recursive:true});
writeFileSync(new URL('../artifacts/performance-guard.json',import.meta.url),JSON.stringify(observations,null,2)+'\n');
console.log(JSON.stringify(observations,null,2));
