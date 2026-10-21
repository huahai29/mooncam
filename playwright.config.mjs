import { defineConfig } from '@playwright/test';
export default defineConfig({
 testDir:'tests/browser', fullyParallel:false, retries:0,
 use:{baseURL:'http://127.0.0.1:4173',headless:true,viewport:{width:1365,height:1050}},
 webServer:{command:'node scripts/serve.mjs',url:'http://127.0.0.1:4173',reuseExistingServer:!process.env.CI,timeout:15000},
 reporter:[['list']],outputDir:'test-results',
});
