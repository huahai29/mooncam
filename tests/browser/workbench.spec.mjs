import {test,expect} from '@playwright/test';
test('Chinese workbench computes, reports failures, searches and exports',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/');
 await expect(page.locator('#analyze')).toBeEnabled();
 await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('满足约束');
 await expect(page.locator('#profile svg')).toHaveCount(1);
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
 await page.locator('#segments').fill('[]');await page.locator('#analyze').click();
 await expect(page.locator('#status')).toContainText('program requires');
 expect(errors).toEqual([]);
});
test('mobile layout remains usable and inputs with unknown fields fail',async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.goto('/');
 await expect(page.locator('#analyze')).toBeEnabled();await page.locator('#analyze').click();
 await expect(page.locator('#metrics')).toContainText('满足约束');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:'test-results/workbench-mobile.png',fullPage:true});
 await page.locator('#segments').fill('[{"angle_deg":360,"lift_mm":0,"extra":1}]');
 await page.locator('#analyze').click();await expect(page.locator('#status')).toContainText('unknown field');
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

test('missing Worker has a functional MoonBit compatibility mode',async({page})=>{
 await page.addInitScript(()=>{window.Worker=undefined;});
 await page.goto('/');await expect(page.locator('#status')).toContainText('兼容模式');
 await page.locator('#analyze').click();await expect(page.locator('#metrics')).toContainText('满足约束');
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-export="csv"]').click()]);
 expect(download.suggestedFilename()).toBe('mooncam.csv');
});

test('late duplicate response cannot overwrite a later calculation',async({page})=>{
 await page.addInitScript(()=>{
  const Original=window.Worker;
  window.Worker=class extends Original {
   constructor(...args){super(...args);super.addEventListener('message',event=>{
    event.stopImmediatePropagation();const data=event.data;this.deliver?.({data});
    if(data.id===1)setTimeout(()=>this.deliver?.({data}),800);
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
