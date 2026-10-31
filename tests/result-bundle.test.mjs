import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as engine from '../web/engine.js';
import {executeTask} from '../web/engine-task.mjs';
import {zipFiles,resultBundle} from '../web/result-bundle.mjs';
import {readZip} from './zip-reader.mjs';
const base=JSON.parse(readFileSync(new URL('../examples/pressure-limit.json',import.meta.url),'utf8'));
const parse=x=>JSON.parse(x);
const run=request=>parse(engine.run(JSON.stringify({...request,outputs:['points']})));
const saved=async(request,response)=>readZip(await resultBundle({request,response},executeTask(engine,{kind:'bundle'}).files).arrayBuffer());
test('ZIP uses standard headers and CRC for UTF-8 Chinese text and empty files',async()=>{
 const files={'README.md':'中文说明：此轮廓采用毫米。\n','empty.csv':''};
 assert.deepEqual(readZip(await zipFiles(files).arrayBuffer()),files);
 assert.throws(()=>zipFiles({'../escape.txt':'bad'}),/文件名/);
 assert.throws(()=>zipFiles({}),/数量/);
});
test('bundle reuses the cached MoonBit exports and never invokes computation',()=>{
 let calls=[];
 const host={export_profile(format){calls.push(format);return JSON.stringify({ok:true,content:format});},run(){throw Error('unexpected recomputation');}};
 assert.deepEqual(executeTask(host,{kind:'bundle'}),{ok:true,files:{csv:'csv',svg:'svg',dxf:'dxf'}});
 assert.deepEqual(calls,['csv','svg','dxf']);
 calls=[];host.export_profile=format=>{calls.push(format);return JSON.stringify({ok:false,error_code:'no_result'});};
 assert.equal(executeTask(host,{kind:'bundle'}).error_code,'no_result');assert.deepEqual(calls,['csv']);
});
test('rejected and accepted bundles preserve input, compact report, version and exact profile bytes',async()=>{
 for(const base_radius_mm of [5,36]){
  const request={...base,base_radius_mm},response=run(request),files=await saved(request,response);
  assert.deepEqual(Object.keys(files),['input.json','request.json','report.json','profile.csv','profile.svg','profile.dxf','README.md','manifest.json']);
  assert.deepEqual(parse(files['input.json']),request);assert.deepEqual(parse(files['request.json']),request);
  const report=parse(files['report.json']),manifest=parse(files['manifest.json']);
  assert.equal(report.result.points,undefined);assert.equal(report.result.csv,undefined);
  assert.equal(report.result.state,response.result.state);assert.deepEqual(report.input,request);
  assert.deepEqual(report.generator,response.generator);assert.deepEqual(manifest.generator,response.generator);
  for(const format of ['csv','svg','dxf'])assert.equal(files[`profile.${format}`],parse(engine.export_profile(format)).content);
  const replay=run(parse(files['input.json']));
  assert.equal(replay.result.max_pressure_deg,report.result.max_pressure_deg);assert.equal(replay.result.state,report.result.state);
  assert.ok(files['README.md'].includes(response.generator.source_digest));assert.ok(files['README.md'].includes('不是连续安全证明'));
 }
});
test('a search bundle saves the final candidate and fine resolution separately from the original request',async()=>{
 const request=JSON.parse(readFileSync(new URL('../examples/size-search.json',import.meta.url),'utf8'));
 const response=run(request),files=await saved(request,response),input=parse(files['input.json']);
 assert.equal(input.action,'analyze');assert.equal(input.base_radius_mm,36);
 assert.equal(input.resolution,response.result.sampling.nominal_resolution);assert.equal(input.search,undefined);
 assert.deepEqual(parse(files['request.json']),request);
 const replay=run(input);assert.equal(replay.result.max_pressure_deg,response.result.max_pressure_deg);
 assert.equal(replay.result.state,response.result.state);assert.equal(replay.result.sample_count,response.result.sample_count);
});
test('missing exports and invalidated sessions cannot produce a partial result package',()=>{
 const response=run(base);
 assert.throws(()=>resultBundle({request:base,response},{csv:'only csv'}),/缺少/);
 run({...base,rpm:0});assert.equal(executeTask(engine,{kind:'bundle'}).error_code,'no_result');
});
