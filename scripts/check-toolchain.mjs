import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
const pinned=readFileSync(new URL('../.moonbit-version',import.meta.url),'utf8').trim();
const result=spawnSync('moonc',['-v'],{encoding:'utf8',shell:false});
if(result.error||result.status!==0)throw Error('MoonBit compiler unavailable. Install MoonBit >= 0.10.16 and put moonc on PATH.');
const output=result.stdout+' '+result.stderr;
const match=output.match(/v?(\d+)\.(\d+)\.(\d+)(?:\+([a-z0-9]+))?/);
if(!match)throw Error('Cannot identify MoonBit compiler version: '+output.trim());
const numbers=match.slice(1,4).map(Number);
const minimum=[0,10,16];
let comparison=0;
for(let i=0;i<3;i++){if(numbers[i]!==minimum[i]){comparison=numbers[i]>minimum[i]?1:-1;break;}}
if(comparison<0)throw Error(`MoonBit >= 0.10.16 required; found ${match[0]}. Recommended: ${pinned}`);
const actual=match[0].replace(/^v/,'');
if(process.argv.includes('--exact')&&actual!==pinned)throw Error(`CI requires ${pinned}; found ${actual}`);
console.log(`MoonBit compiler ${actual}; minimum 0.10.16; pinned ${pinned}`);
