import {readdirSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {inspectStage,cleanStage} from '../bin/delivery.mjs';
try{
 const [action,path,token]=process.argv.slice(2);
 if(action==='list'){
  for(const name of readdirSync(resolve(path)))if(name.startsWith('.mooncam-stage-')){
   try{console.log(JSON.stringify(inspectStage(join(resolve(path),name))));}catch(error){console.error(name+': '+error.message);}
  }
 }else if(action==='clean'&&token)cleanStage(resolve(path),token);
 else throw Error('Usage: node scripts/staging.mjs list PARENT | clean STAGE TOKEN');
}catch(error){console.error(error.message);process.exitCode=1;}
