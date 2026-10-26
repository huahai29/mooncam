# MoonCam

[![MoonCam 检查](https://github.com/huahai29/mooncam/actions/workflows/ci.yml/badge.svg)](https://github.com/huahai29/mooncam/actions/workflows/ci.yml)

**用 MoonBit 将运动要求转换为凸轮轮廓，并计算运动学与几何约束。**

面向机械课程设计、低速教学模型和凸轮方案初选。输入分段升程、机构尺寸和转速，由 MoonBit 输出真实滚轮接触轮廓与采样约束分析。

| 速览 | 当前交付 |
| --- | --- |
| 模型 | 平面盘形凸轮、直动滚子从动件、正负偏置、恒定正转速 |
| 核心语言 | MoonBit：运动学、几何、采样、搜索、判定、校验与导出 |
| 网页工作台 | 运动段表格、逐段规律、实时校验、问题定位、三档采样比较 |
| 输入 → 输出 | JSON / MoonBit 类型 → 分析报告、点数据、CSV、SVG、毫米制 DXF |
| 通过的含义 | 局部采样约束满足，且采样折线检查完成、确定零交叉 |
| 不确定时 | 单独报告；不解释成通过，也不宣称物理不可行 |
| 搜索范围 | 有限网格首个通过复核的基圆候选，不是连续全局最优 |

[完整案例：5 mm 超限 → 36 mm 候选与三档复核](docs/完整操作案例.md) · [公共 API](docs/公共API.md) · [输入输出](docs/输入输出说明.md) · [状态、上限与错误码](docs/接口契约.md) · [设计取舍](docs/设计取舍.md) · [固定验收用例](docs/判定验收.md)

运行时无需 Python、CAD 或远程服务；JavaScript 只承担 Node.js / 浏览器宿主对接。核心库可在 MoonBit 中直接使用。

![MoonCam 中文工作台](docs/images/workbench.png)

## 快速运行

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，确保 `moon` 在 PATH 中。可复现工具链为 `0.10.15+943464bfa`，CI 使用同一固定版本。

```sh
git clone https://github.com/huahai29/mooncam.git
cd mooncam
moon test --target wasm-gc
moon run examples/library --target wasm-gc
```

以上只需要 MoonBit，不需要 Node.js。`examples/library` 直接调用类型化库，输出默认案例的最大压力角、最小局部偏置因子和点数。

### 在线使用

[打开 MoonCam 在线工作台](https://huahai29.github.io/mooncam/web/)：无需安装，选择算例即可计算、定位问题和下载结果。参数在浏览器本地处理，核心引擎由 MoonBit 编译生成；运行时无需远程计算服务。使用说明见工作台内的“第一次使用”。

在线页面在 main 分支检查通过后由 GitHub Pages 自动更新，包含教程、算例和本次检查构建的计算引擎。

### 打开网页工作台

使用网页或 CLI 时，还需安装 Node.js 22 或更新版本。在仓库根目录运行：

```sh
npm run build
npm run serve
```

终端出现 `MoonCam: http://127.0.0.1:4173/` 后，用**同一台电脑的浏览器**打开 [本地工作台](http://127.0.0.1:4173/)。保持服务终端运行；按 `Ctrl+C` 会停止服务。`127.0.0.1` 指当前电脑，只有启动本地服务后才能访问。

首次构建或修改 MoonBit 源码后需执行 `npm run build`，生成网页计算引擎。以后重新打开工作台，在仓库根目录运行 `npm run serve` 即可。运行工作台无需安装 npm 开发依赖。

首次使用可按[完整操作案例](docs/完整操作案例.md)完成一轮操作：

1. 选择“小基圆 · 压力角不满足”，在表格中查看升程、停歇和回程；每段可独立选择规律，MoonBit 返回闭合校验与行内错误。
2. 点击“计算轮廓”，查看超限原因并定位到相应运动段、采样点和曲线转角。
3. 搜索基圆尺寸，将返回的候选半径填回左侧参数，勾选三档采样比较并重新计算。
4. 保存输入配置、JSON 报告，以及所需的 CSV、SVG 或 DXF。修改参数后应重新计算，图表和下载对应上次提交计算时的参数。

### 只运行命令行

无需启动网页服务，构建后直接执行：

```sh
npm run build
node bin/mooncam.mjs examples/workshop.json --out artifacts/workshop
```

输出目录包含 `profile.svg`、`profile.csv`、`profile.dxf`、`report.json`、`input.json`。

### 本地页面打不开时

| 现象 | 检查与处理 |
| --- | --- |
| 浏览器提示无法连接 | 在仓库根目录运行 `npm run serve`，确认终端出现监听地址且没有退出 |
| 重启电脑或关闭终端后无法连接 | 重新运行 `npm run serve`；本地服务不会随电脑启动自动运行 |
| 提示 `EADDRINUSE` | 4173 端口已被占用；若已有 MoonCam 服务，直接访问，否则先确认并处理占用进程 |
| 页面能打开，但引擎加载失败 | 执行 `npm run build`，通过上述 HTTP 地址访问并刷新页面 |
| 另一台电脑无法用这个地址访问 | `127.0.0.1` 指向访问者自己的电脑；当前服务只监听本机 |

CLI 退出码：`0` 表示局部条件通过且折线交叉检查完成、未发现交叉；`2` 表示采样检查拒绝；`3` 表示搜索未找到候选；`4` 表示检查未完成；`1` 表示输入或运行错误。通过采样检查不等于连续轮廓全局无干涉或制造认证。

## 五个可运行案例

| 输入文件 | 用途 | 预期结果 |
| --- | --- | --- |
| `examples/workshop.json` | 20 mm 升程、40 mm 基圆、4 mm 滚轮 | 最大压力角约 27.61°，满足所设 30°限制 |
| `examples/pressure-limit.json` | 将基圆缩小到 5 mm | 局部约束不满足，CLI 返回 2 |
| `examples/crossing-profile.json` | 1 mm 基圆、20 mm 滚轮、72 分辨率的诊断反例 | 采样轮廓有 2 组确定交叉边对，CLI 返回 2 |
| `examples/offset-follower.json` | 从动件偏置 10 mm | 正负压力角及轮廓随偏置变化 |
| `examples/size-search.json` | 在 5～100 mm 内按 1 mm 步长搜索 | 得到 36 mm 候选，复核压力角约 29.52° |

```sh
node bin/mooncam.mjs examples/size-search.json --out artifacts/search
```

36 mm 是有限网格与采样条件下的结果，不代表连续参数空间中的最小可行尺寸。

## 看懂检查结果

网页在“检查原因与位置”中显示压力角与偏置因子的余量，点击定位可同步选中运动段、采样接触点和曲线转角。发生交叉或几何不确定时，可选择相关边对，查看两条边的角度范围。程序段在网页从 1 展示，JSON 段下标、点号与边号从 0 编号。

勾选“比较三档采样”可对同一机构尺寸比较指标、最差位置和检查状态；默认不开启。无 Worker 的主线程兼容模式会取消并禁用比较，单档计算与导出仍可使用。JSON 对应 `compare_sampling: true`，结果保存在 `sampling_comparison`。每档独立编号，比较表的点号不能直接用于当前轮廓；状态相同和数值稳定都不构成连续证明。

操作步骤、字段含义与验收见[位置、诊断与采样比较](docs/位置诊断与采样比较.md)。

## 在 MoonBit 中调用

完整签名与错误约定见 [公共 API](docs/公共API.md)。根目录是可复用库，`examples/library/` 是完整调用示例。模块名为 `huahai29/mooncam`，已发布版本为 [0.3.0](https://mooncakes.io/docs/huahai29/mooncam@0.3.0)：

```sh
moon add huahai29/mooncam@0.3.0
```

在消费方 moon.pkg 中导入：

```moonbit
import {
  "huahai29/mooncam" @cam,
  "moonbitlang/core/math",
}
```

Mooncakes 发布包包含核心库、核心测试、纯 MoonBit 示例与文档；CLI、网页宿主及其构建工具保留在 GitHub 仓库，使用它们仍按上文克隆构建。发布与独立安装验证步骤见[发布流程](docs/发布流程.md)，本版变化见[0.3.0 版本说明](docs/releases/0.3.0.md)。

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

## 实现与验证

运动学、接触几何、采样、搜索、交叉判定、输入校验与导出均由 MoonBit 实现。JavaScript 负责浏览器和 Node.js 宿主对接，Python 仅用于独立开发验证。

- [架构说明](docs/架构说明.md)：模块职责、数据流、状态与资源边界。
- [验证记录](docs/验证记录.md)：测试方法和独立数值验证。
- [设计取舍](docs/设计取舍.md)：采样、搜索、容差、输出和兼容策略。
- [判定验收](docs/判定验收.md)：固定几何案例、预期状态和验收命令。

截至 2026-10-26 的验证记录：

| 验证 | 已通过的范围 |
| --- | --- |
| MoonBit 单元与性质测试 | 54 组，JS、Wasm、Wasm-GC、Native 四后端分别执行 |
| 接口、CLI 与导出 | 23 组集成测试 |
| 浏览器操作 | 13 组，覆盖桌面、手机、兼容模式、表格、定位、比较与完整导出流程 |
| 独立数值对照 | 18 组参数、432 个接触点 |

GitHub Actions 还检查格式、公共接口快照和 DXF 独立读取，并保存性能观测。当前状态见 [Actions](https://github.com/huahai29/mooncam/actions/workflows/ci.yml)，具体方法与适用范围见[验证记录](docs/验证记录.md)。

## 引擎版本与性能护栏

网页页脚显示实际计算引擎的包版本、schema 版本和源码指纹；JSON 报告与 CLI 保存的报告保留完整 generator 信息。指纹标识计算源码，不等于 Git 提交；线上 main 分支可能含尚未进入 Mooncakes 0.3.0 归档的更新，复算时应同时核对版本与指纹。

CI 在四后端检查高分辨率交叉候选访问量、128 段标量路径不保留坐标及固定网格搜索结果，另以 npm run performance:check 检查摘要体积和宽松耗时上限。方法、阈值和局限见[版本追溯与性能护栏](docs/版本追溯与性能护栏.md)。

## 适用边界

`sampled_local_feasible` 只表示局部条件；`sampled_feasible` 还要求折线交叉检查完成且计数为零。`crossing_check` 明确区分完成、不确定、失败和未检查。折线判定不代表连续轮廓没有采样间回环或非局部滚轮干涉。可以提高分辨率比较采样敏感性；数值稳定不构成收敛证明，采样不能替代连续极值求解。

当前不包含强度、载荷、弹簧预紧、磨损、弹性和公差分析。DXF 是离散轮廓交换文件，未承诺可直接加工。详见 [算法与适用范围](docs/算法与适用范围.md)。

## 来源和后续工作

按公开机械运动学公式独立编写，未复制第三方凸轮实现代码。参考项目与来源见 [参考与来源](THIRD_PARTY_NOTICES.md)，采用 [MIT 许可证](LICENSE)。已有数学方法不作为原创理论申报；项目贡献是 MoonBit 实现、组合接口、验证和工作流。

[后续改进清单](docs/后续改进清单.md) 已区分已完成交付、原十项的部分进展与尚未实现的研究目标，避免把已交付功能继续列为待办。

## 0.3.0 与接口兼容

当前包版本为 0.3.0，JSON schema 仍为 2。相比 0.2 开发阶段，新增统一位置、诊断余量、采样比较、边对证据和分段校验；手工构造公共结构的调用方需补齐新增字段，详见版本说明。

0.2 开发阶段已引入的 JSON 行为继续保留：默认只返回点数据和摘要；通过 `outputs` 选择 points / csv / svg / dxf，空数组仅返回摘要，`include_input` 控制输入回显。CLI 自动按需请求格式，报告只保存摘要与文件引用。响应中的名义分辨率改为 `sampling.nominal_resolution`（请求仍使用 `resolution`），实际点数另行报告；JSON 根切角字段改名为 `min_offset_factor_angle_rad`。旧版本调用方需按 [输入输出说明](docs/输入输出说明.md) 迁移。

历史优化核查见 [优化核查记录](docs/优化核查记录.md)；当前接口与状态以 [接口契约](docs/接口契约.md) 为准。
