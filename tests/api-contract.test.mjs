import test from 'node:test';
import assert from 'node:assert/strict';
import{readFileSync,mkdtempSync,readdirSync,writeFileSync}from'node:fs';
import{tmpdir}from'node:os';
import{join,resolve}from'node:path';
import{spawnSync}from'node:child_process';
import{run,input_limit_bytes,export_profile,contract,error_exit_code,validate_segments}from'../web/engine.js';
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
 const version=JSON.parse(readFileSync(new URL('../package.json',import.meta.url),'utf8')).version;
 assert.equal(command(['--version']).stdout.trim(),version);
 assert.equal(readFileSync(new URL('../moon.mod',import.meta.url),'utf8').match(/^version\s*=\s*"([^"]+)"/m)[1],version);
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

test('diagnostics, point indices and segment boundaries describe the same sampled position',()=>{
 for(const resolution of [36,73,720]) for(const base_radius_mm of [5,40]) {
  const r=call({...base,resolution,base_radius_mm}).result;
  for(const [index,p] of r.points.entries()) {
   assert.equal(p.sample_index,index);
   const segment=r.segments[p.segment_index];
   if(index===r.points.length-1) {assert.equal(p.segment_index,0);assert.equal(p.theta_rad,2*Math.PI);}
   else assert.ok(p.theta_rad>=segment.start_rad&&p.theta_rad<segment.end_rad);
  }
  for(const key of ['pressure','offset_factor']) {
   const d=r.diagnostics[key],l=d.location,p=r.points[l.sample_index];
   assert.equal(p.theta_rad,l.theta_rad);assert.equal(p.segment_index,l.segment_index);
   assert.equal(l.segment_start_rad,r.segments[l.segment_index].start_rad);
   assert.ok(Math.abs((key==='pressure'?Math.abs(p.pressure_deg):p.offset_factor)-d.value)<1e-12);
   assert.equal(d.passed,key==='pressure'?d.value<=d.limit:d.value>d.limit);
  }
  assert.equal(r.diagnostics.pressure.passed,base_radius_mm===40);
  assert.equal(r.diagnostics.reasons.includes('pressure_limit_exceeded'),base_radius_mm===5);
 }
});

test('optional sampling comparison matches independent reports, respects limits and keeps cache on original mesh',()=>{
 assert.equal(call(base).result.sampling_comparison,undefined);
 assert.equal(call({...base,compare_sampling:'yes'}).field,'compare_sampling');
 for(const resolution of [36,720,1001,4000]) {
  const r=call({...base,resolution,compare_sampling:true,outputs:[]}).result,c=r.sampling_comparison;
  assert.equal(c.levels.length,3);assert.ok(c.levels.some(l=>l.nominal_resolution===resolution));
  for(const level of c.levels) {
   assert.ok(level.nominal_resolution>=36&&level.nominal_resolution<=4000);
   const independent=call({...base,resolution:level.nominal_resolution,outputs:[]}).result;
   assert.deepEqual(level.pressure,independent.diagnostics.pressure);
   assert.deepEqual(level.offset_factor,independent.diagnostics.offset_factor);
   assert.deepEqual(level.crossing_check,independent.crossing_check);assert.equal(level.state,independent.state);
  }
  assert.equal(r.points,undefined);
 }
 const original=call({...base,compare_sampling:true,outputs:['csv']});
 assert.equal(JSON.parse(export_profile('csv')).content,original.result.csv);
 const rejected=call({...base,base_radius_mm:5,compare_sampling:true}).result;
 assert.equal(rejected.sampling_comparison.state_consistent,true);
 assert.equal(rejected.state,'rejected');
});

test('edge witnesses match numeric point coordinates and remain useful without points output',()=>{
 const request={...base,base_radius_mm:1,roller_radius_mm:20,resolution:72};
 const r=call(request).result;
 assert.ok(r.crossing_check.count>0);assert.ok(r.crossing_evidence.witnesses.length>0);
 for(const w of r.crossing_evidence.witnesses) for(const e of [w.edge_a,w.edge_b]) {
  const a=r.points[e.edge_index],b=r.points[e.edge_index+1];
  assert.equal(e.start.sample_index,a.sample_index);assert.equal(e.end.sample_index,b.sample_index);
  assert.equal(e.segment_index,a.segment_index);
  assert.deepEqual([e.start_x,e.start_y,e.end_x,e.end_y],[a.x,a.y,b.x,b.y]);
  assert.equal(e.start.theta_rad,a.theta_rad);assert.equal(e.end.theta_rad,b.theta_rad);
 }
 const summary=call({...request,outputs:[]}).result;
 assert.deepEqual(summary.crossing_evidence,r.crossing_evidence);assert.equal(summary.points,undefined);
 const spec=JSON.parse(contract());
 for(const key of Object.keys(r.diagnostics.pressure.location)) assert.ok(spec.position_contract.fields[key]);
 for(const code of r.diagnostics.reasons) assert.ok(spec.diagnostic_contract.reason_codes.includes(code));
 for(const w of r.crossing_evidence.witnesses) assert.ok(spec.diagnostic_contract.witness_kinds.includes(w.kind));
});

test('search compares the fixed final candidate with independent per-resolution analyses',()=>{
 const request={...base,action:'search',resolution:180,search:{lower_mm:35,upper_mm:40,intervals:5},compare_sampling:true,outputs:[]};
 const r=call(request);assert.equal(r.ok,true);
 assert.equal(r.result.sampling.nominal_resolution,360);
 for(const level of r.result.sampling_comparison.levels) {
  const independent=call({...base,base_radius_mm:r.result.base_radius_mm,resolution:level.nominal_resolution,outputs:[]}).result;
  assert.deepEqual(level.pressure,independent.diagnostics.pressure);
 }
});

test('live segment validation preserves mixed laws and does not replace session exports',()=>{
 const segments=base.segments.map((s,i)=>({...s,law:i===0?'345':i===2?'cycloidal':'4567'}));
 const result=call({...base,segments});assert.equal(result.ok,true);
 const before=export_profile('csv');
 const validate=x=>JSON.parse(validate_segments(JSON.stringify(x)));
 assert.equal(validate(segments).ok,true);
 assert.equal(validate(segments).total_angle_deg,360);
 assert.equal(validate(segments.slice(1)).ok,false);
 assert.equal(validate([{angle_deg:360,lift_mm:0,law:'345',extra:1}]).field,'segments[0].extra');
 assert.equal(validate([{angle_deg:360,lift_mm:null,law:'345'}]).field,'segments[0].lift_mm');
 assert.equal(validate(Array.from({length:129},()=>({angle_deg:360/129,lift_mm:0,law:'345'}))).ok,false);
 assert.equal(export_profile('csv'),before);
});
