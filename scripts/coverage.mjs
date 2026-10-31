import {spawnSync} from 'node:child_process';
import {mkdirSync,rmSync,lstatSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join,resolve,relative} from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const directory=resolve(root,'_build','coverage-ci');
if(relative(root,directory)!==join('_build','coverage-ci'))throw Error('coverage target outside workspace');
for(const target of [join(root,'_build'),directory]){
 if(lstatSync(target,{throwIfNoEntry:false})?.isSymbolicLink())throw Error('coverage directory must not be a symbolic link');
}
const moon=process.env.MOON||(process.platform==='win32'?'moon.exe':'moon');
function execute(command,args){
 const result=spawnSync(command,args,{cwd:root,stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)throw Error(`${command} exited ${result.status}`);
}
try{
 // Only this dedicated generated directory is removed; prior traces cannot raise coverage.
 rmSync(directory,{recursive:true,force:true});
 mkdirSync(join(root,'artifacts','coverage'),{recursive:true});
 execute(moon,['test','--target','js','--deny-warn','--enable-coverage','--target-dir',directory]);
 execute(moon,['coverage','analyze','--target-dir',directory,'--','-f','coveralls','-o',join(root,'artifacts','coverage','coveralls.json')]);
 execute(process.execPath,['scripts/coverage-check.mjs']);
}catch(error){console.error(`Coverage failed: ${error.message}`);process.exitCode=1;}
