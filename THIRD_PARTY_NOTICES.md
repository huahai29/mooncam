# 参考与来源

## 实现范围

MoonCam 按公开机械运动学与微分几何公式独立编写，当前未复制第三方凸轮库代码，没有在运行时导入 Python 或调用其服务。已有数学方法不作为原创理论申报。

## 参考项目与理论

- [gabemorris12/mechanism](https://github.com/gabemorris12/mechanism)：Python 机构设计工具，MIT 许可证，原仓库许可证为 license.txt。用于了解运动程序、SVAJ、滚轮轮廓与基圆分析的工作流。本项目数值验证是独立差分程序，未声称已完成与该库的逐项结果对照。
- [quyhoang/CamDesign](https://github.com/quyhoang/CamDesign)：参考其公开展示的凸轮分析与结果组织方式，未复制代码、素材；未来如复用代码，需先核实具体文件许可。
- Robert L. Norton, Design of Machinery、Cam Design and Manufacturing Handbook：运动规律与凸轮设计的理论参考，未复制书籍文字、图表或代码。

## 相邻 MoonBit 能力

[moonbit-easings](https://github.com/Zlj6566/moonbit-easings) 已提供运动曲线、导数和轨迹等能力。MoonCam 的独立范围集中于偏置滚轮接触几何、实际凸轮轮廓、压力角、局部曲率条件、基圆候选搜索和机械轮廓交换。共用数学基础不等于发明新算法；赛事独立性由审核判断。

## 开发与构建依赖

- MoonBit 工具链和 moonbitlang/core：编译、数学及 JSON 基础能力，遵循各自许可证。
- Node.js：可选 CLI 和网页宿主。
- Playwright：Apache-2.0，仅用于浏览器开发测试。
- Python 标准库：仅用于独立验证。

本仓库手写代码使用 MIT 许可证。编译产物在本地或 CI 生成。
