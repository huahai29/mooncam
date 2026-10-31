import * as fs from 'node:fs';
import {resolve,dirname,basename,join} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
export function readSnapshot(path,limit,io=fs){
 const before=io.lstatSync(path,{bigint:true});
 if(!before.isFile()||before.isSymbolicLink())throw Error('Input must be a regular file');
 const fd=io.openSync(path,'r');
 try{
  const first=io.fstatSync(fd,{bigint:true});
  if(first.size>BigInt(limit))throw Error(`Input exceeds ${limit} UTF-8 bytes.`);
  const buffer=Buffer.alloc(limit+1);let size=0,count;
  while(size<buffer.length&&(count=io.readSync(fd,buffer,size,buffer.length-size,null))>0)size+=count;
  const bytes=buffer.subarray(0,size),last=io.fstatSync(fd,{bigint:true}),named=io.lstatSync(path,{bigint:true});
  for(const key of ['dev','ino','size','mtimeNs','ctimeNs'])if(first[key]!==last[key]||first[key]!==named[key]||before[key]!==first[key])throw Error('Input changed during reading');
  if(bytes.length>limit)throw Error('Input exceeds byte limit');
  return bytes;
 }finally{io.closeSync(fd);}
}
function exists(io,path){try{io.lstatSync(path);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
export function publishDirectory(target,contents,io=fs,hooks={}){
 target=resolve(target);const parent=dirname(target),lock=target+'.mooncam-lock';
 io.mkdirSync(parent,{recursive:true});
 const token=randomUUID(),stage=join(parent,'.mooncam-stage-'+token);
 io.mkdirSync(lock); // Exclusive reservation among MoonCam publishers; never steal a lock.
 let published=false;
 try{
  if(exists(io,target))throw Error('Output already exists; choose a new directory');
  io.mkdirSync(stage);
  const owner={format:'mooncam.stage.v1',token,pid:process.pid,target,stage,files:Object.keys(contents),hashes:{}};
  io.writeFileSync(join(lock,'owner.json'),JSON.stringify(owner),{flag:'wx'});
  io.writeFileSync(join(stage,'owner.json'),JSON.stringify(owner),{flag:'wx'});
  hooks.staged?.(stage);
  for(const [name,text] of Object.entries(contents)){
   if(!/^[a-zA-Z0-9_.-]+$/.test(name)||name==='owner.json')throw Error('Invalid output name');
   const fd=io.openSync(join(stage,name),'wx');
   try{io.writeFileSync(fd,text,'utf8');io.fsyncSync(fd);}finally{io.closeSync(fd);}
   owner.hashes[name]=createHash('sha256').update(text,'utf8').digest('hex');
   io.writeFileSync(join(stage,'owner.json'),JSON.stringify(owner));
  }
  hooks.beforePublish?.(stage);
  if(exists(io,target))throw Error('Output appeared during publication');
  io.renameSync(stage,target);published=true;
 }finally{
  // Failed stages remain inspectable; lock is released only by the owning publisher.
  try{if(exists(io,join(lock,'owner.json')))io.unlinkSync(join(lock,'owner.json'));io.rmdirSync(lock);}catch(e){if(published)console.error('MoonCam: output complete; reservation cleanup needs inspection:',lock);}
 }
 return target;
}
export function inspectStage(stage){
 stage=resolve(stage);const st=fs.lstatSync(stage);
 if(!st.isDirectory()||st.isSymbolicLink()||!basename(stage).startsWith('.mooncam-stage-'))throw Error('Not a MoonCam staging directory');
 const owner=JSON.parse(fs.readFileSync(join(stage,'owner.json'),'utf8'));
 if(owner.format!=='mooncam.stage.v1'||owner.stage!==stage||basename(stage)!=='.mooncam-stage-'+owner.token||dirname(owner.target)!==dirname(stage)||!Number.isInteger(owner.pid)||owner.pid<1)throw Error('Invalid staging ownership');
 for(const entry of fs.readdirSync(stage,{withFileTypes:true}))if(!entry.isFile()||entry.isSymbolicLink()||!['owner.json',...owner.files].includes(entry.name))throw Error('Unexpected staging contents; manual inspection required');
 for(const name of fs.readdirSync(stage))if(name!=='owner.json'){
  const hash=createHash('sha256').update(fs.readFileSync(join(stage,name))).digest('hex');
  if(owner.hashes?.[name]!==hash)throw Error('Staging file changed or was not closed successfully; preserve for manual inspection');
 }
 return owner;
}
export function cleanStage(stage,token){
 const owner=inspectStage(stage);if(token!==owner.token)throw Error('Operation token mismatch');
 try{process.kill(owner.pid,0);throw Error('Owner process may still be active');}catch(e){if(e.code!=='ESRCH')throw e;}
 // Nonrecursive removal of explicitly enumerated regular files only. Recheck immediately.
 const again=inspectStage(stage);if(JSON.stringify(again)!==JSON.stringify(owner))throw Error('Staging ownership changed');
 for(const name of fs.readdirSync(owner.stage))fs.unlinkSync(join(owner.stage,name));
 fs.rmdirSync(owner.stage);
 const lock=owner.target+'.mooncam-lock';
 if(fs.existsSync(lock)){
  const record=JSON.parse(fs.readFileSync(join(lock,'owner.json'),'utf8'));
  if(record.token===token&&fs.readdirSync(lock).length===1){fs.unlinkSync(join(lock,'owner.json'));fs.rmdirSync(lock);}
 }
}
