# MoonCam

[![MoonCam 检查](https://github.com/huahai29/mooncam/actions/workflows/ci.yml/badge.svg)](https://github.com/huahai29/mooncam/actions/workflows/ci.yml)

用 MoonBit 编写的凸轮设计工具。输入升程、回程、停歇和机构尺寸，查看接触轮廓、检查压力角，定位问题并导出图形与数据。

适合机械课程设计、教学模型和方案初选。支持平面盘形凸轮、直动滚子从动件、正负偏置与恒定正转速。

**[在线工作台](https://huahai29.github.io/mooncam/web/)** · [完整案例](docs/完整操作案例.md) · [Mooncakes](https://mooncakes.io/docs/huahai29/mooncam@0.4.1)

在线版无需安装，计算在浏览器本地完成，输入参数不发送到服务器。

![MoonCam 工作台](docs/images/workbench.png)

## 先试一次

1. 打开工作台，选择“小基圆 · 压力角不满足”，点击“计算轮廓”。这个例子的最大压力角约 59.02°，超过设置的 30° 限制。
2. 点击诊断中的定位按钮，查看对应运动段和轮廓位置。使用基圆网格搜索，在 5～100 mm、1 mm 间隔下会得到 36 mm 候选。
3. 把左侧基圆改为 36 mm，重新计算，复核压力角约 29.52°。可以勾选三档采样比较，再保存输入、报告或轮廓文件。

调整前后的数值、输入文件和操作步骤见[完整案例](docs/完整操作案例.md)。

## 功能

- 分段编辑运动程序，每段可选摆线、3-4-5 或 4-5-6-7 规律。
- 查看位移、速度、加速度、跃度、压力角和滚轮接触轮廓。
- 检查局部几何条件与折线交叉，显示余量、问题位置和相关边。
- 搜索基圆候选，比较采样结果，导出 JSON、CSV、SVG 和毫米制 DXF。

计算、校验、搜索和导出内容均由 MoonBit 实现；JavaScript 负责网页交互和 Node.js 文件读写。使用时无需 Python 或 CAD。

## 本地运行

需要 [MoonBit](https://www.moonbitlang.com/download/)（moonc ≥ 0.10.16）和 Node.js 22+。CI 固定使用 `0.10.16+b1a0e846e`。

```sh
git clone https://github.com/huahai29/mooncam.git
cd mooncam
npm run build
npm run serve
```

打开 http://127.0.0.1:4173/ ，保持服务终端运行。命令行生成文件：

```sh
node bin/mooncam.mjs examples/workshop.json --out artifacts/workshop
```

输出包含输入配置、JSON 报告、CSV、SVG 和 DXF。更多算例及排错方法见[本地运行说明](docs/本地运行.md)。

## 在 MoonBit 中使用

```sh
moon add huahai29/mooncam@0.4.1
```

在 `moon.pkg` 中导入：

```moonbit
import {
  "huahai29/mooncam" @cam,
  "moonbitlang/core/math",
}
```

调用示例：

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

库使用弧度、rad/s 和一致的长度单位；网页与 JSON 使用毫米、角度和 rpm。[完整示例](examples/library/main.mbt) · [公共 API](docs/公共API.md)

Mooncakes 提供核心库，网页和 CLI 从仓库运行。在线版跟随 main 更新，保存报告时请一并保留引擎版本与源码指纹。

## 使用范围

“通过”表示本次采样满足局部约束，且折线交叉检查完成、确定零交叉；无法确定时会单独提示。加密采样有助于观察变化，但不是连续安全证明。搜索结果是有限网格上的首个通过候选。

当前不包含强度、载荷、磨损、公差或加工分析，DXF 导出也不代表可直接加工。详见[算法与适用范围](docs/算法与适用范围.md)。

## 文档

- 配置与结果：[输入输出](docs/输入输出说明.md)、[诊断与采样比较](docs/位置诊断与采样比较.md)、[状态与错误码](docs/接口契约.md)。
- 实现：[架构说明](docs/架构说明.md)、[设计取舍](docs/设计取舍.md)。
- 验证：[测试与独立对照](docs/验证记录.md)、[CAD 导入](docs/CAD导入验收.md)、[跨平台一致性](docs/跨平台一致性.md)。
- 开发：[更新记录](CHANGELOG.md)、[贡献说明](CONTRIBUTING.md)。

CI 覆盖核心测试、浏览器操作、独立数值对照与 Windows/Linux 一致性检查。[查看运行结果](https://github.com/huahai29/mooncam/actions)

## 许可证

[MIT](LICENSE)。参考资料与依赖见[来源说明](THIRD_PARTY_NOTICES.md)。
