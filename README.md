# MoonCam

[![MoonCam 检查](https://github.com/huahai29/mooncam/actions/workflows/ci.yml/badge.svg)](https://github.com/huahai29/mooncam/actions/workflows/ci.yml)

用 MoonBit 编写的凸轮设计工具。给出升程、回程、停歇和机构尺寸，就能查看凸轮轮廓，检查压力角，找到需要调整的位置，并导出图形和数据。

适合机械课程设计、教学模型和凸轮方案初选。目前支持平面盘形凸轮与直动滚子从动件，可设置正负偏置，转速保持恒定。

**[打开在线工作台](https://huahai29.github.io/mooncam/web/)** · [跟着案例做一遍](docs/完整操作案例.md) · [Mooncakes](https://mooncakes.io/docs/huahai29/mooncam@0.4.0)

在线版无需安装。计算在浏览器本地进行，输入参数不发送到服务器。

![MoonCam 工作台：运动段编辑、凸轮轮廓和分析结果](docs/images/workbench.png)

## 先试一个例子

打开工作台，选择“小基圆 · 压力角不满足”，点击“计算轮廓”。这个例子的升程是 20 mm，基圆半径只有 5 mm，最大压力角约 59.02°，超过设置的 30° 限制。

点击压力角诊断中的定位按钮，可以看到问题所在的运动段和轮廓位置。再使用“基圆网格搜索”，按 1 mm 间隔搜索 5～100 mm，会得到 36 mm 的候选，复核压力角约 29.52°。

把左侧基圆改为 36 mm，勾选“比较三档采样”后重新计算，就能检查采样加密后的变化。最后保存输入和报告，按需要下载 CSV、SVG 或 DXF。

[完整案例](docs/完整操作案例.md)包含调整前后对照、三档采样结果和可重复运行的输入文件。

## 可以用它做什么

- 分段编辑升程、停歇和回程，每段可选摆线、3-4-5 或 4-5-6-7 运动规律。
- 查看位移、速度、加速度、跃度、压力角和实际滚轮接触轮廓。
- 检查局部几何条件和轮廓折线交叉，定位超限点及相关边。
- 搜索基圆候选尺寸，比较不同采样密度下的指标与检查结果。
- 保存 JSON 输入和报告，导出 CSV 数据、SVG 图形及毫米制 DXF 闭合折线。

运动学、接触几何、搜索、判定和导出内容均由 MoonBit 实现；JavaScript 负责网页交互与 Node.js 文件读写。运行时不依赖 Python、CAD 或远程计算服务。

## 怎样理解“通过”

通过表示本次采样满足局部约束，且轮廓折线交叉检查完成、确定零交叉。如果几何关系无法确定，页面会单独提示，不会算作通过。

加密采样可以帮助观察结果是否稳定，但不能证明连续轮廓没有干涉。搜索得到的是有限网格上的首个通过候选。项目尚不包含强度、载荷、磨损、公差或加工分析，导出 DXF 也不代表可以直接加工。详细说明见[算法与适用范围](docs/算法与适用范围.md)。

## 在自己电脑上运行

需要 [MoonBit 工具链](https://www.moonbitlang.com/download/)和 Node.js 22+。最低要求 moonc 0.10.16；仓库固定验证的 MoonBit 版本为 `0.10.16+b1a0e846e`。

```sh
git clone https://github.com/huahai29/mooncam.git
cd mooncam
npm run build
npm run serve
```

终端出现监听地址后，打开 http://127.0.0.1:4173/ 。使用期间保持终端运行；下次打开只需再次执行 `npm run serve`。

也可以直接生成文件：

```sh
node bin/mooncam.mjs examples/workshop.json --out artifacts/workshop
```

输出目录包含输入配置、JSON 报告、CSV、SVG 和 DXF。安装说明、更多算例、退出码及页面打不开时的处理方法见[本地运行](docs/本地运行.md)。

## 在 MoonBit 项目中使用

```sh
moon add huahai29/mooncam@0.4.0
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

库使用弧度、rad/s 和一致的长度单位；网页与 JSON 使用毫米、角度和 rpm。完整示例在 [examples/library](examples/library/main.mbt)，接口签名见[公共 API](docs/公共API.md)。

Mooncakes 0.4.0 提供核心库；网页和 CLI 从仓库运行。在线版跟随 main 分支；发行版本说明见[0.4.0](docs/releases/0.4.0.md)。网页页脚和新报告会记录实际引擎的版本与源码指纹，复算时请一并保留。

## 文档与开发

- [输入输出说明](docs/输入输出说明.md)：JSON 配置、单位和导出字段。
- [位置、诊断与采样比较](docs/位置诊断与采样比较.md)：如何理解余量、点号和交叉证据。
- [接口契约](docs/接口契约.md)：状态、上限与错误码。
- [架构说明](docs/架构说明.md)与[设计取舍](docs/设计取舍.md)：代码组织和算法选择。
- [验证记录](docs/验证记录.md)与[固定验收用例](docs/判定验收.md)：测试方法、独立数值对照和检查命令。
- [CAD 导入验收](docs/CAD导入验收.md)：FreeCAD 原生导入的尺寸、闭合与坐标对照。
- [版本追溯与性能护栏](docs/版本追溯与性能护栏.md)、[更新记录](CHANGELOG.md)与[后续计划](docs/后续改进清单.md)。

当前测试包括四后端各 54 组核心测试、23 组集成测试和 13 组浏览器测试，另有独立数值对照与 DXF 读取验证。对应提交的运行结果见 [GitHub Actions](https://github.com/huahai29/mooncam/actions)。参与开发或反馈问题请看[贡献说明](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)。按公开机械运动学公式独立编写，参考资料与第三方依赖见[来源说明](THIRD_PARTY_NOTICES.md)。
