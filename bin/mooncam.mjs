#!/usr/bin/env node
import {readFileSync,writeFileSync,mkdirSync,statSync} from 'node:fs';
import {resolve,join} from 'node:path';
const args=process.argv.slice(2);
if(args.length===0||args[0]==='--help'){
 console.log('Usage: node bin/mooncam.mjs INPUT.json [--out DIRECTORY]\nExit: 0 sampled accepted, 2 rejected, 3 no search candidate, 4 incomplete checks, 1 invalid input/runtime error.');
 process.exit(args.length?0:1);
}
try{
 if(![1,3].includes(args.length)||(args.length===3&&args[1]!=='--out'))throw new Error('Invalid arguments; use --help.');
 const {run,input_limit_bytes}=await import('../web/engine.js');
 const limit=input_limit_bytes();
 if(statSync(args[0]).size>limit)throw new Error(`Input exceeds ${limit} UTF-8 bytes.`);
 const bytes=readFileSync(args[0]);
 if(bytes.length>limit)throw new Error(`Input exceeds ${limit} UTF-8 bytes.`);
 const input=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
 const original=JSON.parse(input);
 const request={...original,outputs:args[1]==='--out'?['csv','svg','dxf']:[],include_input:false};
 const response=JSON.parse(run(JSON.stringify(request)));
 if(!response.ok){
  console.error(JSON.stringify({error_code:response.error_code,error:response.error}));
  process.exitCode=response.error_code==='no_candidate'?3:1;
 }else{
  const {csv,svg,dxf,points,...summary}=response.result;
  if(args[1]==='--out'){
   const out=resolve(args[2]);mkdirSync(out,{recursive:true});
   const files={'csv':'profile.csv','svg':'profile.svg','dxf':'profile.dxf','input':'input.json'};
   const compact={...response,result:summary,files};delete compact.input;
   const contents={'profile.csv':csv,'profile.svg':svg,'profile.dxf':dxf,
    'input.json':JSON.stringify(original,null,2)+'\n','report.json':JSON.stringify(compact,null,2)+'\n'};
   for(const[name,content]of Object.entries(contents))writeFileSync(join(out,name),content,'utf8');
   console.log(`Saved report, original input and profiles to ${out}`);
  }
  console.log(JSON.stringify({...summary,tested:response.tested,grid_step_mm:response.grid_step_mm},null,2));
  process.exitCode=summary.state==='incomplete'?4:summary.sampled_feasible?0:2;
 }
}catch(error){console.error(`MoonCam: ${error.message}`);process.exitCode=1;}
