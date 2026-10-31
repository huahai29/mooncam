import {sample_case} from '../_build/js/release/build/examples/sampling/sampling.js';
const rows=[];
for(const analytic of [false,true])for(const n of [720,1440,2880,5760]){
 sample_case(n,analytic);
 const start=performance.now();let result;
 for(let repeat=0;repeat<5;repeat++)result=sample_case(n,analytic);
 const [maximum,position]=result.split(',').map(Number);
 rows.push({case:analytic?'analytic345':'workshop',n,maximum,position,elapsed_ms:(performance.now()-start)/5});
}
console.log(JSON.stringify(rows));
