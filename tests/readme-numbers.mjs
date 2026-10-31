import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {run} from '../web/engine.js';
const readme=readFileSync(new URL('../README.md',import.meta.url),'utf8');
const base=JSON.parse(readFileSync(new URL('../examples/pressure-limit.json',import.meta.url),'utf8'));
assert.equal(base.resolution,720);
assert.equal(base.pressure_limit_deg,30);
const analyze=radius=>{
 const response=JSON.parse(run(JSON.stringify({...base,base_radius_mm:radius,outputs:[]})));
 assert.equal(response.ok,true,JSON.stringify(response));
 return response.result;
};
for(const [radius,expected,state] of [[5,59.02357703389171,'rejected'],[35,30.03261241037471,'rejected'],[36,29.516044408324568,'accepted_sampled']]){
 const result=analyze(radius);
 assert.ok(Math.abs(result.max_pressure_deg-expected)<1e-8);
 assert.equal(result.state,state);
 assert.equal(result.sampled_feasible,state==='accepted_sampled');
 assert.equal(result.crossing_check.status,'complete');
 assert.equal(result.crossing_check.count,0);
 const row=readme.split('\n').find(line=>line.startsWith(`| ${radius} mm |`));
 assert.ok(row,`README missing ${radius} mm row`);
 const cells=row.split('|').slice(1,-1).map(cell=>cell.trim());
 assert.equal(cells[1],`${result.max_pressure_deg.toFixed(2)}°`);
 const margin=base.pressure_limit_deg-result.max_pressure_deg;
 assert.equal(cells[2],`${margin<0?'−':'+'}${Math.abs(margin).toFixed(2)}°`);
 assert.equal(cells[3].startsWith('通过'),result.sampled_feasible);
}
const search=JSON.parse(readFileSync(new URL('../examples/size-search.json',import.meta.url),'utf8'));
const found=JSON.parse(run(JSON.stringify({...search,outputs:[]})));
assert.equal(found.ok,true);
assert.equal(found.result.base_radius_mm,36);
assert.equal(found.grid_step_mm,1);
let low=35,high=36;
for(let i=0;i<30;i++){
 const mid=(low+high)/2;
 if(analyze(mid).sampled_feasible) high=mid; else low=mid;
}
assert.ok(high-low<1e-8);
assert.equal(analyze(low).state,'rejected');
assert.equal(analyze(high).state,'accepted_sampled');
assert.equal(analyze(35.06).state,'rejected');
assert.equal(analyze(35.07).state,'accepted_sampled');
assert.ok(readme.includes(`${high.toFixed(6)} mm`),'README sampled boundary differs');
assert.ok(readme.includes(`${(36-high).toFixed(2)} mm`),'README grid radius difference differs');
console.log(`README_NUMBERS_PASS: 5/35/36 mm, search=36 mm, sampled boundary bracket=[${low}, ${high}] mm; not a continuous certificate.`);
