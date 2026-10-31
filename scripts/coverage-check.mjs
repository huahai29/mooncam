import {readFileSync,readdirSync,writeFileSync,appendFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
export function summarizeCoverage(report,expected,budget){
 if(!Array.isArray(report?.source_files)||!report.source_files.length)throw Error('empty coverage report');
 if(!Array.isArray(expected)||!expected.length)throw Error('no core sources');
 if(!Number.isInteger(budget?.max_uncovered)||budget.max_uncovered<0)throw Error('invalid coverage budget');
 const files=new Map();
 for(const file of report.source_files){
  const name=file.name?.replaceAll('\\','/');
  if(!expected.includes(name))continue;
  if(files.has(name))throw Error(`duplicate coverage source: ${name}`);
  if(!Array.isArray(file.coverage)||file.coverage.some(n=>n!==null&&(!Number.isInteger(n)||n<0)))throw Error(`invalid coverage: ${name}`);
  const executable=file.coverage.filter(n=>n!==null).length;
  if(!executable)throw Error(`no executable coverage lines: ${name}`);
  const uncovered=file.coverage.filter(n=>n===0).length;
  files.set(name,{name,executable,covered:executable-uncovered,uncovered});
 }
 let total=0,uncovered=0;
 for(const name of expected){
  const file=files.get(name);if(!file)throw Error(`missing core source: ${name}`);
  if(!Number.isInteger(budget.files?.[name]))throw Error(`missing per-file budget: ${name}`);
  if(file.uncovered>budget.files[name])throw Error(`uncovered regression: ${name} ${file.uncovered} > ${budget.files[name]}`);
  total+=file.executable;uncovered+=file.uncovered;
 }
 if(uncovered>budget.max_uncovered)throw Error(`total uncovered regression: ${uncovered} > ${budget.max_uncovered}`);
 return {executable:total,covered:total-uncovered,uncovered,percent:Number((100*(total-uncovered)/total).toFixed(2)),files:[...files.values()].sort((a,b)=>a.name.localeCompare(b.name))};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const root=fileURLToPath(new URL('../',import.meta.url));
  const expected=readdirSync(root).filter(n=>n.endsWith('.mbt')&&!/_(?:wb|bb)?test\.mbt$/.test(n));
  const report=JSON.parse(readFileSync(resolve(root,'artifacts/coverage/coveralls.json'),'utf8'));
  const budget=JSON.parse(readFileSync(new URL('../tests/coverage-budget.json',import.meta.url),'utf8'));
  const summary=summarizeCoverage(report,expected,budget);
  mkdirSync(resolve(root,'artifacts/coverage'),{recursive:true});
  writeFileSync(resolve(root,'artifacts/coverage/summary.json'),JSON.stringify(summary,null,2)+'\n');
  const table=['## MoonBit 核心插桩行覆盖率','',`${summary.covered}/${summary.executable} (${summary.percent}%)；未覆盖 ${summary.uncovered} 行，上限 ${budget.max_uncovered}。`,'','| 文件 | 已覆盖 / 可执行 | 未覆盖 |','| --- | --- | --- |',...summary.files.map(f=>`| ${f.name} | ${f.covered} / ${f.executable} | ${f.uncovered} |`)].join('\n')+'\n';
  writeFileSync(resolve(root,'artifacts/coverage/summary.md'),table);
  if(process.env.GITHUB_STEP_SUMMARY)appendFileSync(process.env.GITHUB_STEP_SUMMARY,table);
  console.log(table);
 }catch(error){console.error(`Coverage check failed: ${error.message}`);process.exitCode=1;}
}
