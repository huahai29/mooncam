#!/usr/bin/env node
import {readFileSync,writeFileSync,mkdirSync,statSync} from 'node:fs';
import {resolve,join,basename,extname} from 'node:path';
const args=process.argv.slice(2);
const help=`Usage: node bin/mooncam.mjs INPUT.json [MORE.json ...] [--out DIRECTORY]
Use - for UTF-8 JSON on stdin. Multiple inputs run sequentially; stdout is JSONL.
Options: --version --rpm N --resolution N --base-radius N --pressure-limit N
Exit: 0 sampled accepted, 2 rejected, 3 no search candidate, 4 incomplete checks, 1 invalid input/runtime error.`;
if(!args.length||args.includes('--help')){console.log(help);process.exit(args.length?0:1);}
if(args.length===1&&args[0]==='--version'){console.log(JSON.parse(readFileSync(new URL('../package.json',import.meta.url),'utf8')).version);process.exit(0);}
const numeric={'--rpm':'rpm','--resolution':'resolution','--base-radius':'base_radius_mm','--pressure-limit':'pressure_limit_deg'};
try{
 const inputs=[],overrides={};let output;
 for(let i=0;i<args.length;i++){
  const arg=args[i];
  if(arg==='--out'){if(output!==undefined||!args[i+1]||args[i+1].startsWith('--'))throw new Error('Expected one --out directory.');output=args[++i];}
  else if(arg in numeric){const raw=args[++i];if(raw===undefined||raw.trim()===''||!Number.isFinite(Number(raw)))throw new Error(`Expected a finite number after ${arg}.`);overrides[numeric[arg]]=Number(raw);}
  else if(arg.startsWith('-')&&arg!=='-')throw new Error(`Unknown option: ${arg}`);
  else inputs.push(arg);
 }
 if(!inputs.length||inputs.filter(x=>x==='-').length>1)throw new Error('Provide input files, with stdin at most once.');
 const {run,input_limit_bytes,error_exit_code,result_exit_code}=await import('../web/engine.js');
 const limit=input_limit_bytes();let exit=0;
 const rank={0:0,2:1,3:2,4:3,1:4};
 for(let index=0;index<inputs.length;index++){
  const file=inputs[index];let code=1;
  try{
   let bytes;
   if(file==='-'){
    const chunks=[];let size=0;
    for await(const chunk of process.stdin){size+=chunk.length;if(size>limit)throw new Error(`Input exceeds ${limit} UTF-8 bytes.`);chunks.push(chunk);}
    bytes=Buffer.concat(chunks);
   }else{if(statSync(file).size>limit)throw new Error(`Input exceeds ${limit} UTF-8 bytes.`);bytes=readFileSync(file);}
   if(bytes.length>limit)throw new Error(`Input exceeds ${limit} UTF-8 bytes.`);
   const original=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
   const effective={...original,...overrides};
   const response=JSON.parse(run(JSON.stringify({...effective,outputs:output?['csv','svg','dxf']:[],include_input:false})));
   if(!response.ok){console.error(JSON.stringify({input:file,error_code:response.error_code,field:response.field,error:response.error}));code=error_exit_code(response.error_code);}
   else{
    const {csv,svg,dxf,points,...summary}=response.result;
    if(output){
     const name=file==='-'?'stdin':basename(file,extname(file));
     const out=resolve(output,...(inputs.length>1?[`${index+1}-${name}`]:[]));mkdirSync(out,{recursive:true});
     const files={csv:'profile.csv',svg:'profile.svg',dxf:'profile.dxf',input:'input.json'};
     const compact={...response,result:summary,files};delete compact.input;
     const contents={'profile.csv':csv,'profile.svg':svg,'profile.dxf':dxf,'input.json':JSON.stringify(effective,null,2)+'\n','report.json':JSON.stringify(compact,null,2)+'\n'};
     for(const[name,content]of Object.entries(contents))writeFileSync(join(out,name),content,'utf8');
     console.error(`Saved report, effective input and profiles to ${out}`);
    }
    console.log(JSON.stringify({...summary,input:file,tested:response.tested,grid_step_mm:response.grid_step_mm},null,inputs.length>1?0:2));
    code=result_exit_code(summary.state);
   }
  }catch(error){console.error(`MoonCam (${file}): ${error.message}`);}
  if(rank[code]>rank[exit])exit=code;
 }
 process.exitCode=exit;
}catch(error){console.error(`MoonCam: ${error.message}`);process.exitCode=1;}
