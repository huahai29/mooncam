import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fork} from 'node:child_process';
import {once} from 'node:events';
import {publishDirectory,readSnapshot,inspectStage,cleanStage} from '../bin/delivery.mjs';
const workspace=()=>fs.mkdtempSync(join(tmpdir(),'mooncam-delivery-'));
test('publication is complete and never overwrites an existing target',()=>{
 const root=workspace(),out=join(root,'out');
 publishDirectory(out,{'a.txt':'a','b.txt':'b'});
 assert.equal(fs.readFileSync(join(out,'b.txt'),'utf8'),'b');
 assert.throws(()=>publishDirectory(out,{'a.txt':'new'}),/already exists/);
 assert.equal(fs.readFileSync(join(out,'a.txt'),'utf8'),'a');assert.equal(fs.existsSync(out+'.mooncam-lock'),false);
});
for(const failure of ['write','sync','close','rename'])test(`injected ${failure} failure never publishes an incomplete directory`,()=>{
 const root=workspace(),out=join(root,'out');let triggered=false;
 const io={...fs};
 const method={write:'writeFileSync',sync:'fsyncSync',close:'closeSync',rename:'renameSync'}[failure];
 io[method]=(...args)=>{
  if(!triggered&&(failure!=='write'||typeof args[0]==='number')){
   triggered=true;if(failure==='write')fs.writeSync(args[0],Buffer.from('partial'));if(failure==='close')fs.closeSync(...args);throw Error('injected '+failure);
  }
  return fs[method](...args);
 };
 assert.throws(()=>publishDirectory(out,{'a.txt':'a','b.txt':'b'},io),/injected/);
 assert.equal(fs.existsSync(out),false);
 const stages=fs.readdirSync(root).filter(n=>n.startsWith('.mooncam-stage-'));assert.equal(stages.length,1);
 if(failure==='rename'){const stage=join(root,stages[0]);assert.ok(inspectStage(stage));fs.writeFileSync(join(stage,'a.txt'),'user modification');assert.throws(()=>inspectStage(stage),/changed/);}
});
test('target appearing just before publication is preserved',()=>{
 const out=join(workspace(),'out');
 assert.throws(()=>publishDirectory(out,{'a.txt':'a'},fs,{beforePublish(){fs.mkdirSync(out);fs.writeFileSync(join(out,'other'),'keep');}}),/appeared/);
 assert.equal(fs.readFileSync(join(out,'other'),'utf8'),'keep');
});
test('input snapshot detects edits during reads and remains independent afterwards',()=>{
 const file=join(workspace(),'input.json');fs.writeFileSync(file,'{"a":1}');
 const snapshot=readSnapshot(file,100);fs.writeFileSync(file,'{"a":2}');assert.equal(snapshot.toString(),'{"a":1}');
 let changed=false;const io={...fs,readSync(...args){const count=fs.readSync(...args);if(!changed){changed=true;fs.writeFileSync(file,'changed and longer');}return count;}};
 assert.throws(()=>readSnapshot(file,100,io),/changed/);
});
test('killed publisher leaves identifiable staging; competing publisher is excluded; cleanup is conservative',async()=>{
 const root=workspace(),out=join(root,'out');
 const child=fork(new URL('./delivery-child.mjs',import.meta.url),[out,'pause'],{stdio:['ignore','ignore','inherit','ipc']});
 await once(child,'message');
 assert.equal(fs.existsSync(out),false);
 assert.throws(()=>publishDirectory(out,{'a':'a'}),/exist/i);
 const stage=join(root,fs.readdirSync(root).find(n=>n.startsWith('.mooncam-stage-'))),owner=inspectStage(stage);
 assert.throws(()=>cleanStage(stage,owner.token),/active/);
 const exit=once(child,'exit');child.kill('SIGKILL');await exit;
 assert.throws(()=>cleanStage(stage,'wrong'),/token/);
 fs.writeFileSync(join(stage,'foreign'),'keep');assert.throws(()=>cleanStage(stage,owner.token),/Unexpected/);
 fs.unlinkSync(join(stage,'foreign'));cleanStage(stage,owner.token);
 assert.equal(fs.existsSync(stage),false);assert.equal(fs.existsSync(out+'.mooncam-lock'),false);
 publishDirectory(out,{'a':'retry'});assert.equal(fs.readFileSync(join(out,'a'),'utf8'),'retry');
});
