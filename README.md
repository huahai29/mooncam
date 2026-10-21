# MoonCam

**用 MoonBit 将运动要求转换为凸轮轮廓，并计算运动学与几何约束。**

面向机械课程设计、低速教学模型和凸轮方案初选。输入升程、停歇、回程与机构尺寸，得到实际滚轮接触轮廓、压力角、曲率、基圆搜索结果和可保存的分析数据。

当前支持平面盘形凸轮、直动滚子从动件、正负偏置与恒定正转速。核心库可以直接在 MoonBit 中使用；CLI 和浏览器调用同一套 MoonBit 实现。

![MoonCam 中文工作台](docs/images/workbench.png)

## 主要功能

- 组合升程、停歇、回程，校验一圈闭合与非负升程。
- 摆线、3-4-5、4-5-6-7 多项式及位移、速度、加速度、跃度计算。
- 根据滚轮中心轨迹的法向偏置生成实际接触轮廓，支持偏置从动件。
- 压力角、有符号节曲线曲率、局部偏置奇异因子、跃度跳变分析。
- 检查非相邻采样折线边的严格交叉。
- 在指定基圆网格中搜索候选，以更细角度网格复核，并报告搜索步长。
- SVG 轮廓、CSV 分析表、毫米制闭合折线 DXF 与 JSON 报告。

上述计算与导出内容生成均由 MoonBit 完成。运行时无需 Python、CAD 或远程服务；CAD 可用于后续建模和加工准备。

## 快速运行

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，确保 `moon` 在 PATH 中。已在 MoonBit v0.10.15 工具链上验证。

```sh
git clone https://github.com/huahai29/mooncam.git
cd mooncam
moon test --target wasm-gc
moon run examples/library --target wasm-gc
```

以上只需要 MoonBit，不需要 Node.js。`examples/library` 直接调用类型化库，输出默认案例的最大压力角、最小局部偏置因子和点数。

使用 CLI 和网页时，再安装 Node.js 22 或更新版本：

```sh
npm run build
node bin/mooncam.mjs examples/workshop.json --out artifacts/workshop
npm run serve
```

访问 `http://127.0.0.1:4173/`。运行上述流程无需安装 npm 开发依赖。输出目录包含 `profile.svg`、`profile.csv`、`profile.dxf`、`report.json`、`input.json`。

CLI 退出码：`0` 表示局部条件通过且严格折线交叉检查完成、未发现交叉；`2` 表示采样检查拒绝；`3` 表示搜索未找到候选；`4` 表示检查未完成；`1` 表示输入或运行错误。通过采样检查不等于连续轮廓全局无干涉或制造认证。

## 四个可运行案例

| 输入文件 | 用途 | 预期结果 |
| --- | --- | --- |
| `examples/workshop.json` | 20 mm 升程、40 mm 基圆、4 mm 滚轮 | 最大压力角约 27.61°，满足所设 30°限制 |
| `examples/pressure-limit.json` | 将基圆缩小到 5 mm | 局部约束不满足，CLI 返回 2 |
| `examples/offset-follower.json` | 从动件偏置 10 mm | 正负压力角及轮廓随偏置变化 |
| `examples/size-search.json` | 在 5～100 mm 内按 1 mm 步长搜索 | 得到 36 mm 候选，复核压力角约 29.52° |

```sh
node bin/mooncam.mjs examples/size-search.json --out artifacts/search
```

36 mm 是有限网格与采样条件下的结果，不代表连续参数空间中的最小可行尺寸。

## 在 MoonBit 中调用

根目录是可复用库，`examples/library/` 是完整调用示例。目前尚未发布到 Mooncakes，不能直接使用 `moon add huahai29/mooncam`；可以克隆运行或作为本地模块依赖使用。

```moonbit
let p = @cam.example_program(@cam.Polynomial4567)
let g : @cam.Geometry = {
  base_radius: 40.0,
  roller_radius: 4.0,
  offset: 0.0,
}
match @cam.analyze(p, g, 720, @math.PI / 6.0, 2.0 * @math.PI) {
  Ok(a) => println(a.max_pressure * 180.0 / @math.PI)
  Err(message) => println(message)
}
```

核心 API 使用弧度、rad/s 和统一长度单位。JSON、CLI、网页固定使用毫米、角度、rpm。CSV 明确保留对角度的导数；JSON 使用时间导数。详见 [输入输出说明](docs/输入输出说明.md)。

## 实现结构

| 模块 | 职责 | 语言 |
| --- | --- | --- |
| `motion.mbt`、`program.mbt` | 运动规律、周期校验、角度与时间导数 | MoonBit |
| `geometry.mbt` | 滚轮包络轮廓、压力角和曲率 | MoonBit |
| `analysis.mbt`、`topology.mbt` | 分段采样、约束、跃度跳变和折线交叉 | MoonBit |
| `search.mbt` | 基圆网格搜索和复核 | MoonBit |
| `export.mbt`、`api.mbt`、`bridge/` | 导出内容、JSON 校验和编译接口 | MoonBit |
| `bin/`、`web/`、`scripts/` | 文件读写、页面交互、本地服务和构建 | JS / HTML / CSS |
| `tests/oracle.py` | 独立数值验证，仅开发时运行 | Python |

`web/engine.js` 是 MoonBit 编译产物，由构建生成，不作为手写 JS 提交。宿主适配层不重新实现核心计算。

## 验证

```sh
moon fmt --check
moon check --deny-warn --target all
moon test --target wasm
moon test --target wasm-gc
moon test --target js
npm run build
npm run test:integration
python tests/oracle.py
python -m pip install -r requirements-test.txt
python tests/dxf_interop.py
npm ci
npx playwright install chromium
npm run test:browser
```

测试涵盖解析导数、周期、单位换算、偏置圆形退化、滚轮接触距离、法线正交、段落连续性、搜索、溢出和交叉识别。独立 Python 验证通过另一种多项式表达和中心差分检查 18 组参数、432 个接触点。浏览器测试覆盖桌面、手机、失败提示、搜索和下载。

方法及记录见 [验证记录](docs/验证记录.md)。GitHub Actions 从干净环境执行检查，实际状态以仓库 Actions 页面为准。

## 适用边界

`sampled_local_feasible` 只表示局部条件；`sampled_feasible` 还要求严格折线交叉检查完成且计数为零。`crossing_check` 明确区分完成、失败和未检查。零交叉不代表连续轮廓没有相切、采样间回环或非局部滚轮干涉。应提高分辨率检查收敛；采样不能替代连续极值求解。

当前不包含强度、载荷、弹簧预紧、磨损、弹性和公差分析。DXF 是离散轮廓交换文件，未承诺可直接加工。详见 [算法与适用范围](docs/算法与适用范围.md)。

## 来源和后续工作

按公开机械运动学公式独立编写，未复制第三方凸轮实现代码。参考项目与来源见 [参考与来源](THIRD_PARTY_NOTICES.md)，采用 [MIT 许可证](LICENSE)。已有数学方法不作为原创理论申报；项目贡献是 MoonBit 实现、组合接口、验证和工作流。

[后续改进清单](docs/后续改进清单.md) 记录十项尚未实现的能力。

## 0.2 版本接口变化

JSON schema 升至 2。默认只返回点数据和摘要；通过 `outputs` 选择 points / csv / svg / dxf，空数组仅返回摘要，`include_input` 控制输入回显。CLI 自动按需请求格式，报告只保存摘要与文件引用。`resolution` 改为 `sampling.nominal_resolution`，实际点数另行报告；根切角字段改名为 `min_offset_factor_angle`。旧版本调用方需按 [输入输出说明](docs/输入输出说明.md) 迁移。

本次 14 项核查、正确性测试、性能实测与尚未覆盖的边界见 [优化核查记录](docs/优化核查记录.md)。
