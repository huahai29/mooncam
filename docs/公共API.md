# 公共 API

本页面向直接调用 MoonBit 库或编写宿主的使用者。核心长度单位必须一致，角度为弧度，角速度为 rad/s；JSON 对接固定为毫米、角度、rpm。

## 从任务选择入口

| 任务 | 入口 | 返回与注意事项 |
| --- | --- | --- |
| 构造闭合运动程序 | `program`、`example_program` | `Program` 缓存段界并复制输入；不要绕过构造器修改内部数组 |
| 单独查看归一化规律 | `normalized` | 输入 u∈[0,1]，返回对 u 的前三阶导数 |
| 查询某转角运动 | `evaluate`、`timed` | 前者为角导数，后者为时间导数；evaluate 按周期折返，段界取右侧值 |
| 校验机构和查询接触点 | `validate_geometry`、`contact` | 从滚轮中心法向偏置生成实际接触点 |
| 只要局部指标 | `measure` | 不保留坐标、不做拓扑；不能据此宣称综合通过 |
| 生成采样点 | `sample` | 保留段界和重复闭合点，不自动判断可行性 |
| 完整采样分析 | `analyze` | 返回 `Analysis`；必须检查其状态，而不只检查 Result 是否为 Ok |
| 查询统一位置 | `locate_angle`、`locate_sample`、`locate_edge` | 段、点、边均零基编号；角度查询不隐含最近采样点 |
| 解释局部约束 | `diagnose` | 返回阈值、余量和扫描时直接记录的最差点；压力角采用弧度 |
| 比较采样结果 | `compare_sampling` | 2～4 档严格递增分辨率，逐档完整检查，返回观测变化而非收敛证明 |
| 搜索有限网格首个候选 | `search_base` | `SearchError` 区分非法输入、数值失败、几何不确定与无候选 |
| 检查已有轮廓 | `crossing_report`、`profile_crossings` | 前者保留确定/不确定对数、访问计数和有上限的边对证据；后者有任何不确定项就返回 Err |
| 导出自建点数组 | `checked_export` | 校验数值、实际点数与闭合性，不执行可行性认证；允许导出用于诊断的拒绝轮廓 |
| 格式化已验证样本 | `csv`、`svg`、`dxf_mm` | 低层格式函数不校验；CSV 是角导数，不能用于任意未校验外部点数组 |
| 仅校验分段输入 | `validate_segments_json` | 不采样、不修改会话缓存，复用 JSON 解码与 program 校验，返回总量及首个错误路径 |
| 无状态 JSON 对接 | `run_json` | 返回 JSON 字符串，错误不以抛出异常作为正常接口 |
| 计算一次、按需导出 | `session`、`Session::run`、`Session::export_profile` | 每个用户/任务独立会话；新请求先清空旧缓存，失败后不可下载旧结果 |
| 宿主读取约束与退出码 | `contract_json`、`input_limit_bytes`、`error_exit_code`、`result_exit_code` | 直接读取 MoonBit 定义；未知错误/结果均退出 1 |
| 组合判定和状态 | `sampled_acceptance`、`CrossingCheck::status`、`Analysis::state` | 不确定、失败或未检查一律不接受 |

`finite` 是对外保留的数值辅助函数。普通调用从 program / analyze / run_json 开始即可。

## 推荐调用

```moonbit
let p = @cam.example_program(@cam.Polynomial4567)
let g : @cam.Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0 }
match @cam.analyze(p, g, 720, @math.PI / 6.0, 2.0 * @math.PI) {
  Err(message) => println(message)
  Ok(a) => {
    println(a.state())
    match a.crossings {
      Checked(n) => println(n)
      Indeterminate(confirmed, uncertain) => println("\{confirmed} confirmed; \{uncertain} uncertain pairs")
      Failed(message) => println(message)
      NotChecked => println("not checked")
    }
  }
}
```

## 错误与单位边界

基础数值/几何/采样接口仍使用 `Result[T, String]`，兼容现有调用；这些字符串仅供阅读，不保证文本稳定。需要稳定程序分类时，使用 `SearchError` 或 JSON 的 `error_code`。`ErrorCode::code` 和 `ErrorCode::exit_code` 给出统一的宿主映射。

`Analysis.sampled_feasible` 只有局部条件通过且确定零交叉时才为 true。`Analysis::state()` 将局部条件和拓扑状态组合为综合状态。`Indeterminate` 不等于数值崩溃；`Failed` 则表示检查没能完成。完整状态表、上限与错误码见[接口契约](接口契约.md)。

CSV 含 `ds_dtheta` 等角导数；JSON 的 velocity / acceleration / jerk 已乘转速转换为时间导数。闭合点采用周期右侧值（第零段起点），最大跃度另检查两侧段端点；末行跃度不能解释为末段左极限。

## 两个拓扑入口的区别

`crossing_report` 是需要分类和证据时的首选：`Result` 的 Err 表示检查失败；Ok 中保留 `crossings`、`uncertain_pairs` 及有上限的边对证据。不确定是已完成检查中的一种几何结果，不能当成确定零交叉。

`profile_crossings` 是公开保留的兼容简化入口，并非测试专用。它只在检查确定时返回 `Ok(count)`；不确定和检查失败都返回 `Err(String)`。这是较窄的返回能力，不是另一套几何规则。调用方不得将 Err 当作零，也不应解析字符串区分原因；有分类需求应改用 `crossing_report`。完整分析再由 `CrossingCheck` 表达四种状态。

## 表格编辑与分段校验

`validate_segments_json(input : String) -> String` 接受 JSON **分段数组**，每段含 `angle_deg`、`lift_mm`、`law`，不是完整分析请求。桥接入口名为 `validate_segments`。字节和段数上限与完整请求同源，未知字段同样拒绝。

| 响应字段 | 含义 |
| --- | --- |
| `ok`、`schema_version` | 分段程序是否有效，以及同一接口 schema 版本；不代表机构可行 |
| `segment_count` | 仅成功时返回有效段数 |
| `total_angle_deg`、`total_lift_mm` | 数值数组的总转角与总升程，允许在程序不闭合时返回；类型不合法或总量非有限数时省略 |
| `error_code`、`error`、`field` | 失败时沿用统一错误分类、消息、字段路径；字段路径从零编号，网页显示从 1 编号 |

校验复用 `decode_program` 与 `program`，检查运动规律、数值范围、累计升程非负、总角度和回零。返回首个错误；仅整体闭合错误时，路径为 `segments`。它不会运行几何与采样，不会清空 Session 导出缓存。完整请求的累计升程非法现在同样定位到对应段的 `lift_mm`。

## 位置与诊断的调用约定

`diagnose(p, a, limit)` 中的 `p` 与 `a` 必须来自同一计算。最差指标相等时保留首次扫描到的点；不会声称这个点是唯一极值。位置接口同样要求传入该程序产生的采样点，不推测外部无角度折线对应的运动程序。

`locate_angle` 接受本圈 [0,2π]；`evaluate` 接受周期角度，二者共享段内查询。段界归右侧段；2π 闭合点的位置归首段，最后一条边归末段。点号和边号随分辨率变化，不能作跨网格身份标识。完整约定见[接口契约](接口契约.md)。

MoonBit 的 `ConstraintDiagnostic.value/limit/margin` 对压力角使用弧度，JSON 对应诊断换成度。比较结果中每档的 `location.sample_index` 只指向该档网格。`compare_sampling` 不保留其他档的坐标；若需要绘图，应按其分辨率单独分析，不可用当前点表替代。

## 当前签名

以下签名由 `moon info` 的公共接口快照生成，不能手工修改。完整公开类型定义见根目录 `pkg.generated.mbti`。

<!-- BEGIN GENERATED API -->

```moonbit
pub fn analyze(Program, Geometry, Int, Double, Double) -> Result[Analysis, String]
pub fn checked_export(Array[CamPoint], String) -> Result[String, String]
pub fn compare_sampling(Program, Geometry, Array[Int], Double, Double) -> Result[SamplingComparison, String]
pub fn contact(Program, Geometry, Double) -> Result[CamPoint, String]
pub fn contract_json() -> String
pub fn crossing_report(Array[CamPoint]) -> Result[CrossingReport, String]
pub fn csv(Array[CamPoint]) -> String
pub fn diagnose(Program, Analysis, Double) -> Result[Diagnostics, String]
pub fn dxf_mm(Array[CamPoint]) -> String
pub fn error_exit_code(String) -> Int
pub fn evaluate(Program, Double) -> Result[Motion, String]
pub fn example_program(Law) -> Program
pub fn finite(Double) -> Bool
pub fn generator_json() -> Json
pub fn input_limit_bytes() -> Int
pub fn locate_angle(Program, Double) -> Result[Location, String]
pub fn locate_edge(Program, Array[CamPoint], Int) -> Result[EdgeLocation, String]
pub fn locate_sample(Program, Array[CamPoint], Int) -> Result[Location, String]
pub fn measure(Program, Geometry, Int, Double, Double) -> Result[Metrics, String]
pub fn normalized(Law, Double) -> Result[Motion, String]
pub fn profile_crossings(Array[CamPoint]) -> Result[Int, String]
pub fn program(Array[Segment]) -> Result[Program, String]
pub fn result_exit_code(String) -> Int
pub fn run_json(String) -> String
pub fn sample(Program, Geometry, Int) -> Result[Array[CamPoint], String]
pub fn sampled_acceptance(Bool, CrossingCheck) -> Bool
pub fn search_base(Program, Double, Double, Double, Double, Int, Int, Double, Double) -> Result[SearchResult, SearchError]
pub fn session() -> Session
pub fn svg(Array[CamPoint]) -> String
pub fn timed(Program, Double, Double) -> Result[Motion, String]
pub fn validate_geometry(Geometry) -> Result[Unit, String]
pub fn validate_segments_json(String) -> String
pub fn Analysis::state(Self) -> String
pub fn CrossingCheck::status(Self) -> String
pub fn ErrorCode::code(Self) -> String
pub fn ErrorCode::exit_code(Self) -> Int
pub fn Session::export_profile(Self, String) -> String
pub fn Session::run(Self, String) -> String
```

<!-- END GENERATED API -->
