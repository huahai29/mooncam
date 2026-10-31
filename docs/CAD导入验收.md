# FreeCAD 实际导入验收

日期：2026-10-31。应用：FreeCAD 1.1.4，Windows x86-64 便携版，内置现代 C++ DXF 导入器及 OCCT 几何内核。工具来自 FreeCAD 官方 1.1.4 发布页，便携包 SHA-256 已核对。

## 实际执行了什么

由 MoonCam 的 MoonBit 引擎生成 DXF；使用实际安装的 FreeCADCmd，通过 Import.readDXF 将文件导入原生 CAD 文档，而非用 ezdxf 读取替代。逐项查询 CAD 内部的边、顶点、线框、有效性、包围盒和长度，并保存 FCStd 工程。另在 FreeCAD 图形界面打开了圆形导入工程，切换到 Part 工作台并查看俯视轮廓。

三组完整的图形界面截图尚未完成：桌面控制接口反复报告用户输入及窗口最小化，已停止继续抢占窗口。下表是实际 FreeCAD 原生导入与几何查询的结果，不是以截图推测的结果；不声称完成三组人工界面验收。

## 结果

| 算例 | CAD 顶点 / 边 | 闭合线框 | 外接尺寸 / mm | CAD 形状有效 | MoonCam 状态 |
| --- | --- | --- | --- | --- | --- |
| 零升程圆形，基圆 40 mm | 720 / 720 | 1，闭合 | 80 × 80 | 是 | 采样通过 |
| 20 mm 升程，40 mm 基圆 | 720 / 720 | 1，闭合 | 100 × 100 | 是 | 采样通过 |
| 同一程序，偏置 +10 mm | 720 / 720 | 1，闭合 | 100.829662080234 × 99.639032423766 | 是 | 拒绝 |

三个文件的 CAD 顶点集合与 MoonCam 点表双向最近距离的最大值均为 0 mm（本次 Double 计算结果）；包围盒匹配。周长与包围面积也经 FreeCAD 几何内核核对，误差均在记录的阈值内。面积是从导入闭合线框临时构造平面面得到，并不表示 DXF 本身包含面或实体。

圆形基准的 80 mm 外径用于检查单位尺度；FreeCAD 原生长度以毫米表示，未发现 25.4 倍或 1000 倍缩放。DXF 的毫米声明同时由已有独立读取测试核对。这里不声称所有应用都会自动采用相同单位。

偏置文件能导入且拓扑形状有效，但 MoonCam 的压力角约束仍不通过。“文件可打开”“CAD 形状有效”和“机构采样条件通过”是不同的结论。

## 导入发现并修复的问题

已发布 0.4.0 的 DXF 在实体中引用 MOONCAM 图层，但没有在 TABLES 中声明。FreeCAD 输出 First reference to missing Layer 'MOONCAM' 后自动补建，三组几何检查仍通过。

本轮 main 修复在 MoonBit 导出器中显式声明 MOONCAM 图层及 CONTINUOUS 线型，保留已有单位、坐标、点数和闭合标志。修复后三组重新生成并导入，图层警告不再出现，几何结果不变。集成测试检查图层与线型记录存在。该修复已随 Mooncakes 0.4.1 发布；下方指纹保留当时实际验收的原始信息，不能将修复后的输出归属于既有 0.4.0 发布归档。

原始引擎指纹为 3826c7d0408ff8b23dca5a8f78ddabcb1caa5de91dd9217b5deee1a39b6ce12a；修复后为 17da239e19c102dd22dd852c16145851125175ba6f1a78f004576aafceb715d7。输入、DXF 摘要和原生测量完整数值见 [证据目录](cad/freecad-1.1.4)。

## 如何复算

先安装 FreeCAD 1.1.4 和项目要求的 MoonBit、Node.js。FreeCAD 只用于开发验收，不是 MoonCam 的运行依赖。

```sh
npm run build
node scripts/cad-cases.mjs artifacts/cad-cases
```

在 PowerShell 中将 FREECADCMD 路径替换为自己的安装位置：

```powershell
$env:MOONCAM_CAD_ROOT = (Resolve-Path artifacts/cad-cases).Path
& 'FREECADCMD/bin/freecadcmd.exe' scripts/freecad-audit.py
```

脚本读取 DXF 后写入 freecad-results.json 和每例的 FCStd 文档，打印 ALL_FREECAD_IMPORT_CHECKS_PASS。FreeCADCmd 的进程退出码不能单独当作脚本成功依据，还应确认完成标记、freecad-results.json 中 status 为 passed、三个结果和实际测量值。脚本开始即把结果状态置为 running，失败时不留下上一次的 passed 状态。可在 FreeCAD 中打开导入后的 FCStd，使用俯视、适应全部显示和属性面板复核；也可通过文件菜单直接打开对应 DXF。

## 边界

本记录只覆盖 FreeCAD 1.1.4 的三组毫米制、720 边闭合折线。没有验证 AutoCAD、Fusion、SolidWorks，也没有做草图约束修复、实体加工、刀具补偿或强度载荷验证。不据此宣称所有 DXF 数值范围均可被所有 CAD 接受。
