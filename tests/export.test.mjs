import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {run} from '../web/engine.js';
const r=JSON.parse(run(JSON.stringify({...JSON.parse(readFileSync(new URL('../examples/workshop.json',import.meta.url),'utf8')),outputs:['points','csv','svg','dxf']}))).result;
test('DXF group-pair parser recovers closed mm polyline matching profile',()=>{
 const lines=r.dxf.trim().split('\n');assert.equal(lines.length%2,0);
 const pairs=[];for(let i=0;i<lines.length;i+=2)pairs.push([lines[i],lines[i+1]]);
 const records=[];let record;
 for(const pair of pairs){if(pair[0]==='0'){record={kind:pair[1],tags:[]};records.push(record);}else record?.tags.push(pair);}
 const layer=records.find(x=>x.kind==='LAYER'&&x.tags.some(([c,v])=>c==='2'&&v==='MOONCAM'));
 const linetype=records.find(x=>x.kind==='LTYPE'&&x.tags.some(([c,v])=>c==='2'&&v==='CONTINUOUS'));
 assert.ok(layer,'referenced MOONCAM layer must be explicitly declared');
 assert.ok(linetype,'referenced continuous linetype must be declared');
 assert.equal(layer.tags.find(([c])=>c==='6')[1],'CONTINUOUS');
 const entity=pairs.findIndex(([c,v])=>c==='0'&&v==='LWPOLYLINE');assert.ok(entity>0);
 const body=pairs.slice(entity+1,pairs.findIndex((p,i)=>i>entity&&p[0]==='0'));
 assert.equal(body.find(([c])=>c==='90')[1],String(r.points.length-1));
 assert.equal(body.find(([c])=>c==='70')[1],'1');
 const xs=body.filter(([c])=>c==='10').map(p=>Number(p[1]));const ys=body.filter(([c])=>c==='20').map(p=>Number(p[1]));
 assert.equal(xs.length,720);for(let i=0;i<xs.length;i++){assert.equal(xs[i],r.points[i].x);assert.equal(ys[i],r.points[i].y);}
});
test('CSV rows preserve signed curvature, closure and angular derivative units',()=>{
 const rows=r.csv.trim().split('\n');assert.equal(rows.length,r.points.length+1);
 for(let i=0;i<r.points.length;i+=37){const cells=rows[i+1].split(',').map(Number);assert.equal(cells.length,12);assert.equal(cells[0],r.points[i].theta_rad);assert.equal(cells[7],r.points[i].x);assert.equal(cells[10],r.points[i].pitch_curvature);}
});
