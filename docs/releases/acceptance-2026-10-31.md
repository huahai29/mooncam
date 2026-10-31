# MoonCam 验收快照 · 2026-10-31

本标签固定 GitHub 工作台、CLI、测试与文档，核心库对应 Mooncakes huahai29/mooncam@0.4.1；不是新的库版本。

- 在线流程：超限定位、网格搜索、应用候选后复核、ZIP 结果包下载。
- CLI：输入快照、默认拒绝覆盖、同级暂存完成后发布与保守恢复；保证范围见安全交付文档。
- 验证：两组四档采样误差实验、闭式极值对照、FreeCAD 实际导入、故障路径与跨平台检查。
- 干净克隆可按 README 直接构建；新增浏览器 ZIP → CLI 的逐点复算，允许明确的 1e-12 跨运行时浮点容差，已有结果保护仍按字节核对。

复现：

```sh
git clone --branch acceptance-2026-10-31 https://github.com/huahai29/mooncam.git
cd mooncam
npm run build
node bin/mooncam.mjs examples/workshop.json --out artifacts/first-run
npm run serve
```

需要 moonc ≥0.10.16 与 Node.js 22+；验收固定编译器为 0.10.16+b1a0e846e。输出目录必须不存在，重复演示请换目录。

入口：https://github.com/huahai29/mooncam/blob/acceptance-2026-10-31/docs/验收入口.md

边界：采样通过不是连续安全证明，固定算例误差不是任意输入的误差界，CAD 导入不代表制造认证；CLI 不宣称断电持久性或任意外部竞争下的通用原子不覆盖。
