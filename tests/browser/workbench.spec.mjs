import {test,expect} from '@playwright/test';
test('Chinese workbench computes, reports failures, searches and exports',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/');
 await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('满足约束');
 await expect(page.locator('#profile svg')).toHaveCount(1);
 await expect(page.locator('#segment-summary')).toContainText('分段程序通过校验');
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:'test-results/workbench-desktop.png',fullPage:true});
 await page.locator('#phase').fill('100');await page.locator('#phase').dispatchEvent('input');
 await expect(page.locator('#angle')).toHaveText('50.0°');
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="dxf"]').click()]);
 expect(download.suggestedFilename()).toBe('mooncam.dxf');
 await page.locator('#base').fill('5');await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('需调整');
 await page.locator('#search').click();
 await expect(page.locator('#status')).toContainText('网格位置');
 await expect(page.locator('#metrics')).toContainText('满足约束');
 while(await page.locator('#segment-rows tr').count())await page.locator('#segment-rows tr').first().getByRole('button').click();
 await page.locator('#analyze').click();
 await expect(page.locator('#status')).toContainText('program requires');
 expect(errors).toEqual([]);
});
test('mobile layout remains usable and inputs with unknown fields fail',async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.goto('/');
 await expect(page.locator('#analyze')).toBeEnabled();await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('满足约束');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await expect(page.locator('#segment-summary')).toContainText('分段程序通过校验');
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:'test-results/workbench-mobile.png',fullPage:true});
 await page.locator('#json-options summary').click();
 await page.locator('#segments').fill('[{"angle_deg":360,"lift_mm":0,"law":"345","extra":1}]');
 await page.locator('#apply-segments').click();await expect(page.locator('#import-status')).toContainText('导入失败');
 await expect(page.locator('#segment-rows tr')).toHaveCount(4);
});

test('worker responses are tied to a request and changed inputs stay visibly stale',async({page})=>{
 await page.addInitScript(()=>{
  const Original=window.Worker;
  window.Worker=class extends Original {
   constructor(...args){super(...args);super.addEventListener('message',event=>{
    event.stopImmediatePropagation();const data=event.data;
    setTimeout(()=>this.deliver?.({data}),data.ready?0:250);
   });}
   set onmessage(fn){this.deliver=fn;}
  };
 });
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#analyze').click();await page.locator('#base').fill('5');
 await expect(page.locator('#status')).toContainText('参数在计算期间发生变化');
 await expect(page.locator('#metrics')).toContainText('40.00 mm');
});

test('missing Worker disables comparison while single analysis and exports remain functional',async({page})=>{
 await page.addInitScript(()=>{window.Worker=undefined;});
 await page.goto('/');await expect(page.locator('#status')).toContainText('兼容模式');
 await expect(page.locator('#compare-sampling')).toBeDisabled();
 await expect(page.locator('#compare-sampling')).not.toBeChecked();
 await expect(page.locator('#compatibility-notice')).toBeVisible();
 // Request construction must enforce the policy even if a script changes DOM state.
 await page.locator('#compare-sampling').evaluate(el=>{el.checked=true;});
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('满足约束');
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="csv"]').click()]);
 expect(download.suggestedFilename()).toBe('mooncam.csv');
 const [report]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="json"]').click()]);
 const {readFile}=await import('node:fs/promises');const result=JSON.parse(await readFile(await report.path(),'utf8'));
 expect(result.input.compare_sampling).toBe(false);expect(result.result.sampling_comparison).toBeUndefined();
});

test('late duplicate response cannot overwrite a later calculation',async({page})=>{
 await page.addInitScript(()=>{
  const Original=window.Worker;
  window.Worker=class extends Original {
   constructor(...args){super(...args);super.addEventListener('message',event=>{
    event.stopImmediatePropagation();const data=event.data;this.deliver?.({data});
    if(data.response?.result&&!this.duplicated){this.duplicated=true;setTimeout(()=>this.deliver?.({data}),800);}
   });}
   set onmessage(fn){this.deliver=fn;}
  };
 });
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('40.00 mm');
 await page.locator('#base').fill('5');await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('5.00 mm');
 await page.waitForTimeout(1000);
 await expect(page.locator('#metrics')).toContainText('5.00 mm');
 await expect(page.locator('#metrics')).toContainText('需调整');
});


test('diagnostic location matches slider, curve cursor and highlighted contact point',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#base').fill('5');await page.locator('#analyze').click();
 await expect(page.locator('#diagnostics')).toContainText('压力角超过设定上限');
 const button=page.locator('[data-locate="pressure"]');
 const index=await button.getAttribute('data-sample-index');
 await button.click();
 await expect(page.locator('#phase')).toHaveValue(index);
 await expect(page.locator('#contact-marker')).toHaveAttribute('data-sample-index',index);
 await expect(page.locator('#chart-cursor')).toHaveAttribute('data-sample-index',index);
 await expect(page.locator('#angle')).toHaveText('35.5°');
 await expect(page.locator('#selection-layer polyline')).toHaveAttribute('data-segment-index','0');
 await page.screenshot({path:'test-results/diagnostic-location.png',fullPage:true});
 await page.locator('[data-locate="offset_factor"]').click();
 await expect(page.locator('#trace')).toHaveValue('offset_factor');
 expect(errors).toEqual([]);
});

test('sampling comparison remains inside mobile viewport and does not reuse another mesh indices',async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.goto('/');
 await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#compare-sampling').check();await page.locator('#analyze').click();
 await expect(page.locator('#comparison tbody tr')).toHaveCount(3);
 await expect(page.locator('#comparison')).toContainText('720 / 721');
 await expect(page.locator('#comparison')).toContainText('2880 / 2881');
 await expect(page.locator('#comparison')).toContainText('不能直接定位到当前图');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await page.screenshot({path:'test-results/sampling-comparison-mobile.png',fullPage:true});
 await page.locator('#compare-sampling').uncheck();await page.locator('#analyze').click();
 await expect(page.locator('#comparison-panel')).toBeHidden();
});

test('actual crossing evidence highlights both identified edges and clears after recomputation',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#base').fill('1');await page.locator('#roller').fill('20');await page.locator('#resolution').fill('72');
 await page.locator('#analyze').click();
 await expect(page.locator('#evidence')).toContainText('确定交叉');
 await page.locator('[data-witness="0"]').click();
 await expect(page.locator('.witness-edge')).toHaveCount(2);
 await expect(page.locator('.witness-edge').nth(0)).toHaveAttribute('data-edge-index','37');
 await expect(page.locator('.witness-edge').nth(1)).toHaveAttribute('data-edge-index','44');
 await expect(page.locator('#phase')).toHaveValue('37');
 await page.screenshot({path:'test-results/crossing-evidence.png',fullPage:true});
 await page.locator('#base').fill('40');await page.locator('#roller').fill('4');await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('满足约束');
 await expect(page.locator('.witness-edge')).toHaveCount(0);
 await expect(page.locator('[data-witness]')).toHaveCount(0);
 expect(errors).toEqual([]);
});

test('segment table preserves per-row laws through import and saved input; errors mark the row',async({page})=>{
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await expect(page.locator('#segment-summary')).toContainText('分段程序通过校验');
 const rows=page.locator('#segment-rows tr');
 await rows.nth(0).locator('[data-field="angle_deg"]').fill('');
 await expect(rows.nth(0).locator('[data-field="angle_deg"]')).toHaveAttribute('aria-invalid','true');
 await rows.nth(0).locator('[data-field="angle_deg"]').fill('60');
 await expect(page.locator('#segment-summary')).toContainText('总转角 330°');
 await rows.nth(1).locator('[data-field="angle_deg"]').fill('120');
 await rows.nth(0).locator('[data-field="law"]').selectOption('345');
 await rows.nth(2).locator('[data-field="law"]').selectOption('cycloidal');
 await expect(page.locator('#segment-summary')).toContainText('分段程序通过校验');
 await page.locator('#json-options summary').click();
 const segments=JSON.parse(await page.locator('#segments').inputValue());
 await rows.nth(3).getByRole('button').click();await expect(rows).toHaveCount(3);
 await page.locator('#segments').fill(JSON.stringify(segments));await page.locator('#apply-segments').click();
 await expect(rows).toHaveCount(4);await expect(rows.nth(2).locator('[data-field="law"]')).toHaveValue('cycloidal');
 await page.locator('#analyze').click();await expect(page.locator('#profile svg')).toHaveCount(1);
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('#save-input').click()]);
 const {readFile}=await import('node:fs/promises');const saved=JSON.parse(await readFile(await download.path(),'utf8'));
 expect(saved.segments).toEqual(segments);
 await page.locator('#add-segment').click();await expect(rows).toHaveCount(5);
 await rows.last().getByRole('button').click();await expect(rows).toHaveCount(4);
 await page.screenshot({path:'test-results/segment-editor.png',fullPage:true});
});

test('walkthrough failure, location, candidate search, sampling comparison and export',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#preset').selectOption('pressure-limit');await expect(page.locator('#base')).toHaveValue('5');
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('需调整');
 await page.locator('[data-locate="pressure"]').click();await expect(page.locator('#angle')).toHaveText('35.5°');
 await page.locator('#search').click();await expect(page.locator('#metrics')).toContainText('36.00 mm');
 await expect(page.locator('#base')).toHaveValue('5');
 await page.locator('#base').fill('36');await page.locator('#compare-sampling').check();await page.locator('#analyze').click();
 await expect(page.locator('#comparison tbody tr')).toHaveCount(3);await expect(page.locator('#metrics')).toContainText('满足约束');
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="dxf"]').click()]);expect(download.suggestedFilename()).toBe('mooncam.dxf');
 await page.screenshot({path:'test-results/walkthrough-result.png',fullPage:true});
 await page.goto('/web/tutorial.html');await expect(page.getByRole('heading',{level:2})).toHaveCount(5);
 for(const link of await page.locator('a[download]').all()){const response=await page.request.get(await link.getAttribute('href'));expect(response.ok()).toBe(true);}
 expect(errors).toEqual([]);
});

test('live validation keeps cached exports and rapid edits use latest totals on mobile',async({page})=>{
 await page.addInitScript(()=>{
  const Original=window.Worker;
  window.Worker=class extends Original {
   constructor(...args){super(...args);super.addEventListener('message',event=>{
    event.stopImmediatePropagation();const data=event.data;
    setTimeout(()=>this.deliver?.({data}),data.response?.total_angle_deg===280?700:0);
   });}
   set onmessage(fn){this.deliver=fn;}
  };
 });
 await page.setViewportSize({width:390,height:844});await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('满足约束');
 const angle=page.locator('#segment-rows tr').first().locator('[data-field="angle_deg"]');
 await angle.fill('10');await page.waitForTimeout(200);await angle.fill('20');await angle.fill('90');
 await expect(page.locator('#segment-summary')).toContainText('总转角 360°');await page.waitForTimeout(800);await expect(page.locator('#segment-summary')).toContainText('通过校验');
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="csv"]').click()]);expect(download.suggestedFilename()).toBe('mooncam.csv');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:'test-results/segment-editor-mobile.png',fullPage:true});
});

test('runtime Worker failure cancels an already selected sampling comparison',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  const Original=window.Worker;
  window.Worker=class extends Original {
   postMessage(task){
    if(task.kind==='calculate'&&!this.failed){this.failed=true;queueMicrotask(()=>this.onerror?.(new Event('error')));}
    else super.postMessage(task);
   }
  };
 });
 await page.goto('/');await expect(page.locator('#analyze')).toBeEnabled();
 await expect(page.locator('#compare-sampling')).toBeEnabled();
 await page.locator('#compare-sampling').check();await page.locator('#analyze').click();
 await expect(page.locator('#status')).toContainText('兼容模式');
 await expect(page.locator('#compare-sampling')).toBeDisabled();await expect(page.locator('#compare-sampling')).not.toBeChecked();
 await expect(page.locator('#compatibility-notice')).toContainText('无法强制超时中断');
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('满足约束');
 await expect(page.locator('#comparison-panel')).toBeHidden();
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="json"]').click()]);
 const {readFile}=await import('node:fs/promises');const result=JSON.parse(await readFile(await download.path(),'utf8'));
 expect(result.input.compare_sampling).toBe(false);expect(result.result.sampling_comparison).toBeUndefined();
 await expect(page.locator('#compatibility-notice')).toBeVisible();expect(errors).toEqual([]);
 await page.locator('.settings').screenshot({path:'test-results/compatibility-mode.png'});
});
