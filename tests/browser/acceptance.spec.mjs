import {test,expect} from '@playwright/test';
import {readFile,mkdtemp,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {readZip} from '../zip-reader.mjs';
test('acceptance: downloaded candidate ZIP can be replayed by CLI with numerically matching profile',async({page})=>{
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#preset').selectOption('pressure-limit');await expect(page.locator('#base')).toHaveValue('5');
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('需调整');
 await page.locator('#search').click();await expect(page.locator('#apply-candidate')).toBeEnabled();
 await page.locator('#apply-candidate').click();await expect(page.locator('#candidate-note')).toContainText('重新计算');
 await expect(page.locator('#metrics')).toContainText('29.52°');
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="bundle"]').click()]);
 const files=readZip(await readFile(await download.path()));
 const root=await mkdtemp(join(tmpdir(),'mooncam-acceptance-')),input=join(root,'input.json'),out=join(root,'replayed');
 await writeFile(input,files['input.json']);
 const replay=spawnSync(process.execPath,[resolve('bin/mooncam.mjs'),input,'--out',out],{encoding:'utf8'});
 expect(replay.status,replay.stderr).toBe(0);
 const report=JSON.parse(await readFile(join(out,'report.json'),'utf8'));
 expect(report.result.base_radius_mm).toBe(36);expect(report.result.state).toBe('accepted_sampled');
 const savedCsv=await readFile(join(out,'profile.csv'),'utf8');
 const parse=text=>text.trim().split('\n').map(line=>line.trim().split(','));
 const actual=parse(savedCsv),expected=parse(files['profile.csv']);
 expect(actual[0]).toEqual(expected[0]);expect(actual.length).toBe(expected.length);
 let worst=0;
 for(let row=1;row<actual.length;row++){
  expect(actual[row].length).toBe(expected[row].length);
  for(let column=0;column<actual[row].length;column++){
   const a=Number(actual[row][column]),b=Number(expected[row][column]);
   expect(Number.isFinite(a)&&Number.isFinite(b)).toBe(true);
   worst=Math.max(worst,Math.abs(a-b)/Math.max(1,Math.abs(a),Math.abs(b)));
  }
 }
 expect(worst).toBeLessThanOrEqual(1e-12);
 await writeFile('test-results/acceptance-replay.json',JSON.stringify({state:report.result.state,base_radius_mm:36,rows:actual.length-1,columns:actual[0].length,max_scaled_difference:worst,generator:report.generator},null,2));
 expect(report.generator).toEqual(JSON.parse(files['manifest.json']).generator);
 const repeated=spawnSync(process.execPath,[resolve('bin/mooncam.mjs'),input,'--out',out],{encoding:'utf8'});
 expect(repeated.status).toBe(1);expect(repeated.stderr).toContain('already exists');
 expect(await readFile(join(out,'profile.csv'),'utf8')).toBe(savedCsv);
});
