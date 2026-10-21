import {readFileSync} from 'node:fs';
import {run} from '../web/engine.js';
for(const line of readFileSync(0,'utf8').trim().split('\n')) if(line) console.log(run(line));
