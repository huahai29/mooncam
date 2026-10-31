// Generate CAD exchange fixtures from the actual MoonBit engine.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {run,contract} from '../web/engine.js';
const root=resolve(process.argv[2]||'artifacts/cad-cases');mkdirSync(root,{recursive:true});
const load=name=>JSON.parse(readFileSync(new URL(`../examples/${name}.json`,import.meta.url),'utf8'));
const base=load('workshop');
const cases={circle:{...base,segments:base.segments.map(s=>({...s,lift_mm:0}))},workshop:base,offset:load('offset-follower')};
const expected={generator:JSON.parse(contract()).generator,cases:{}};
for(const [name,input] of Object.entries(cases)){
 const dir=resolve(root,name);mkdirSync(dir,{recursive:true});
 const response=JSON.parse(run(JSON.stringify({...input,outputs:['points','dxf']})));
 if(!response.ok)throw Error(JSON.stringify(response));
 const points=response.result.points.slice(0,-1),xs=points.map(p=>p.x),ys=points.map(p=>p.y);
 let perimeter=0,area=0;
 points.forEach((p,i)=>{const q=points[(i+1)%points.length];perimeter+=Math.hypot(q.x-p.x,q.y-p.y);area+=p.x*q.y-q.x*p.y;});
 expected.cases[name]={vertices:points.length,closed:true,units:'mm',bbox:{xmin:Math.min(...xs),xmax:Math.max(...xs),ymin:Math.min(...ys),ymax:Math.max(...ys)},perimeter_mm:perimeter,area_mm2:Math.abs(area/2),state:response.result.state};
 writeFileSync(resolve(dir,'profile.dxf'),response.result.dxf);
 writeFileSync(resolve(dir,'input.json'),JSON.stringify(input,null,2)+'\n');
 writeFileSync(resolve(dir,'points.json'),JSON.stringify(points)+'\n');
}
writeFileSync(resolve(root,'expected.json'),JSON.stringify(expected,null,2)+'\n');
console.log('Generated CAD fixtures:',root);
