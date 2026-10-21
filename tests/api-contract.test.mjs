import test from 'node:test';
import assert from 'node:assert/strict';
import{readFileSync,mkdtempSync,readdirSync,writeFileSync}from'node:fs';
import{tmpdir}from'node:os';
import{join,resolve}from'node:path';
import{spawnSync}from'node:child_process';
import{run,input_limit_bytes}from'../web/engine.js';
const base=JSON.parse(readFileSync(new URL('../examples/workshop.json',import.meta.url),'utf8'));
const call=x=>JSON.parse(run(JSON.stringify(x)));
const cli=(path,...args)=>spawnSync(process.execPath,[resolve('bin/mooncam.mjs'),path,...args],{encoding:'utf8'});
test('schema v2 requests only selected output data and input echo is opt-in',()=>{
 const r=call(base);assert.equal(r.schema_version,2);assert.equal(r.input,undefined);assert.ok(r.result.points);
 for(const key of ['csv','svg','dxf'])assert.equal(r.result[key],undefined);
 const summary=call({...base,outputs:[]});assert.equal(summary.result.points,undefined);
 const selected=call({...base,outputs:['dxf'],include_input:true});assert.ok(selected.result.dxf);assert.equal(selected.result.points,undefined);assert.equal(selected.input.base_radius_mm,40);
 for(const outputs of [['nope'],['csv','csv'],42])assert.equal(call({...base,outputs}).error_code,'invalid_input');
});
test('combined acceptance and explicit topology status replace sentinel counts',()=>{
 const r=call(base).result;assert.deepEqual(r.crossing_check,{status:'complete',count:0});assert.equal(r.sampled_feasible,true);
 assert.equal(r.state,'accepted_sampled');assert.equal(r.undercut_angle,undefined);assert.equal(r.min_offset_factor_angle_rad>=0,true);
 const failed=call({...base,base_radius_mm:5}).result;assert.equal(failed.state,'rejected');assert.equal(failed.sampled_feasible,false);
});
test('nominal resolution is separate from actual segment-aware intervals',()=>{
 const segments=Array.from({length:128},()=>({angle_deg:360/128,lift_mm:0,law:'4567'}));
 const r=call({...base,segments,resolution:36,outputs:[]}).result;
 assert.equal(r.sampling.nominal_resolution,36);assert.equal(r.sampling.actual_intervals,128);assert.equal(r.sample_count,129);
});
test('API and CLI apply the same UTF-8 byte limit including non-ASCII input',()=>{
 const limit=input_limit_bytes();const text=JSON.stringify(base);const exact=text+' '.repeat(limit-Buffer.byteLength(text));
 assert.equal(JSON.parse(run(exact)).ok,true);assert.equal(JSON.parse(run(exact+' ')).error_code,'input_too_large');
 assert.equal(JSON.parse(run(JSON.stringify({...base,unknown:'中'.repeat(limit/2)}))).error_code,'input_too_large');
 const dir=mkdtempSync(join(tmpdir(),'mooncam-limit-'));const path=join(dir,'in.json');writeFileSync(path,exact);
 assert.equal(cli(path).status,0);writeFileSync(path,exact+' ');const r=cli(path);assert.equal(r.status,1);assert.match(r.stderr,/200000 UTF-8 bytes/);
});
test('CLI distinguishes no candidate and stores compact nonduplicated reports',()=>{
 const dir=mkdtempSync(join(tmpdir(),'mooncam-cli-'));const input=join(dir,'input.json');writeFileSync(input,JSON.stringify(base));
 const out=join(dir,'out');const result=cli(input,'--out',out);assert.equal(result.status,0,result.stderr);
 const saved=JSON.parse(readFileSync(join(out,'report.json'),'utf8'));for(const key of ['csv','svg','dxf','points'])assert.equal(saved.result[key],undefined);
 assert.equal(saved.input,undefined);assert.equal(saved.files.dxf,'profile.dxf');assert.ok(readdirSync(out).includes('input.json'));
 const search={...base,action:'search',pressure_limit_deg:.01,search:{lower_mm:1,upper_mm:2,intervals:1}};writeFileSync(input,JSON.stringify(search));
 const r=cli(input);assert.equal(r.status,3);assert.match(r.stderr,/no_candidate/);
 writeFileSync(input,JSON.stringify({...base,rpm:0}));assert.equal(cli(input).status,1);
 writeFileSync(input,JSON.stringify({...base,base_radius_mm:5}));assert.equal(cli(input).status,2);
});
