import test from 'node:test';
import assert from 'node:assert/strict';
import{readFileSync,mkdtempSync,readdirSync,writeFileSync}from'node:fs';
import{tmpdir}from'node:os';
import{join,resolve}from'node:path';
import{spawnSync}from'node:child_process';
import{run,input_limit_bytes,export_profile,contract,error_exit_code}from'../web/engine.js';
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

test('field errors and invalid include_input are structured',()=>{
 for(const [patch,field] of [[{include_input:1},'include_input'],[{resolution:35},'resolution'],[{rpm:'fast'},'rpm'],[{outputs:['csv','csv']},'outputs']]){
  const r=call({...base,...patch});assert.equal(r.ok,false);assert.equal(r.error_code,'invalid_input');assert.equal(r.field,field);
 }
});

test('MoonBit session exports the previous result without replay and clears on failure',()=>{
 const first=call({...base,outputs:['csv','svg','dxf']});
 for(const ext of ['csv','svg','dxf'])assert.equal(JSON.parse(export_profile(ext)).content,first.result[ext]);
 assert.equal(JSON.parse(export_profile('unknown')).error_code,'invalid_input');
 assert.equal(call({...base,rpm:0}).ok,false);
 assert.equal(JSON.parse(export_profile('csv')).error_code,'no_result');
});

test('CLI supports bounded stdin, version, overrides and independent batch reports',()=>{
 const command=(args,input)=>spawnSync(process.execPath,[resolve('bin/mooncam.mjs'),...args],{encoding:'utf8',input});
 assert.match(command(['--version']).stdout,/^0\.2\.0/);
 assert.equal(command(['-'],JSON.stringify(base)).status,0);
 const changed=command(['-','--base-radius','5'],JSON.stringify(base));assert.equal(changed.status,2);
 assert.equal(command(['-','--rpm','oops'],JSON.stringify(base)).status,1);
 assert.equal(command(['-'],' '.repeat(input_limit_bytes()+1)).status,1);
 const dir=mkdtempSync(join(tmpdir(),'mooncam-batch-'));
 const batch=command(['examples/workshop.json','examples/pressure-limit.json','--out',dir]);
 assert.equal(batch.status,2,batch.stderr);const rows=batch.stdout.trim().split('\n').map(JSON.parse);assert.equal(rows.length,2);
 assert.equal(rows[0].sampled_feasible,true);assert.equal(rows[1].sampled_feasible,false);
 assert.equal(readdirSync(dir).length,2);
});

test('published contract and actual JSON limits agree at both boundaries',()=>{
 const spec=JSON.parse(contract()),l=spec.limits;assert.equal(spec.schema_version,2);
 for(const resolution of [l.resolution_min,l.json_resolution_max])assert.equal(call({...base,resolution,outputs:[]}).ok,true);
 for(const resolution of [l.resolution_min-1,l.json_resolution_max+1]){
  const r=call({...base,resolution});assert.equal(r.error_code,'invalid_input');assert.equal(r.field,'resolution');
 }
 const search={...base,action:'search',search:{lower_mm:40,upper_mm:40,intervals:1},outputs:[]};
 assert.equal(call({...search,resolution:l.search_resolution_max}).ok,true);
 assert.equal(call({...search,resolution:l.search_resolution_max+1}).field,'resolution');
 assert.equal(l.search_resolution_max*l.search_refinement,l.json_resolution_max);
 assert.equal(l.input_bytes_max,input_limit_bytes());
 for(const error of spec.errors)assert.equal(error_exit_code(error.code),error.exit_code);
 assert.equal(error_exit_code('unknown_future_error'),1);
});

test('nested error paths locate segments and search fields',()=>{
 for(const [patch,field] of [
  [{segments:[{angle_deg:360,lift_mm:0,law:'unknown'}]},'segments[0].law'],
  [{segments:[{angle_deg:360,lift_mm:'oops',law:'4567'}]},'segments[0].lift_mm'],
  [{segments:[{angle_deg:360,lift_mm:0,law:'4567',extra:1}]},'segments[0].extra'],
  [{action:'search',search:{lower_mm:40,upper_mm:40,intervals:0}},'search.intervals'],
  [{action:'search',search:{lower_mm:40,upper_mm:30,intervals:1}},'search.upper_mm'],
  [{action:'search',search:{lower_mm:40,upper_mm:40,intervals:1},offset_mm:100},'offset_mm'],
  [{rpm:0},'rpm'],[{pressure_limit_deg:90},'pressure_limit_deg'],[{roller_radius_mm:0},'roller_radius_mm'],
 ]){
  const r=call({...base,...patch});assert.equal(r.error_code,'invalid_input');assert.equal(r.field,field);
 }
 const missing={...base};delete missing.segments;assert.equal(call(missing).field,'segments');
 assert.equal(call({...base,action:'search',search:undefined}).field,'search');
});

test('finite valid input with derivative overflow is a calculation failure',()=>{
 const r=call({...base,rpm:1e120,outputs:[]});assert.equal(r.ok,false);
 assert.equal(r.error_code,'calculation_failed');assert.equal(r.field,null);
 assert.equal(error_exit_code(r.error_code),1);
});
