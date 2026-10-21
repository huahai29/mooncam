import{readFileSync,writeFileSync}from'node:fs';
import{performance}from'node:perf_hooks';
import{pathToFileURL}from'node:url';
import{resolve}from'node:path';
import{run}from'../web/engine.js';
const base=JSON.parse(readFileSync('examples/workshop.json','utf8'));
const workloads={analyze720:base,analyze4000:{...base,resolution:4000},search:JSON.parse(readFileSync('examples/size-search.json','utf8'))};
workloads.segments128={...base,base_radius_mm:200,segments:Array.from({length:128},(_,i)=>({angle_deg:360/128,lift_mm:i%2?-1:1,law:'4567'}))};
const baselinePath=process.argv[2];const old=baselinePath?(await import(pathToFileURL(resolve(baselinePath)))).run:undefined;
const report={method:'Same process; 5 warm-ups and 15 interleaved samples; median milliseconds. Full output requests compare computation at similar output coverage. Not a worst-case complexity claim.',workloads:{}};
for(const[name,q]of Object.entries(workloads)){
 const oldInput=JSON.stringify(q),newInput=JSON.stringify({...q,outputs:['points','csv','svg','dxf'],include_input:true});
 for(let i=0;i<5;i++){if(old)old(oldInput);run(newInput);}
 const before=[],after=[];for(let i=0;i<15;i++){
  if(old){const start=performance.now();old(oldInput);before.push(performance.now()-start);}
  const start=performance.now();run(newInput);after.push(performance.now()-start);
 }
 const median=a=>a.sort((a,b)=>a-b)[Math.floor(a.length/2)];
 const full=run(newInput),defaults=run(JSON.stringify(q)),summary=run(JSON.stringify({...q,outputs:[]}));
 const r={full_median_ms:median(after),full_bytes:Buffer.byteLength(full),default_bytes:Buffer.byteLength(defaults),summary_bytes:Buffer.byteLength(summary)};
 if(old){r.baseline_median_ms=median(before);r.full_speedup=r.baseline_median_ms/r.full_median_ms;r.baseline_bytes=Buffer.byteLength(old(oldInput));}
 report.workloads[name]=r;
}
writeFileSync('artifacts/performance.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
