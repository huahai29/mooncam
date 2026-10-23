///|
const Schema_version : Int32 = 2

///|
const Resolution_min : Int32 = 36

///|
const Library_resolution_max : Int32 = 20000

///|
const Json_resolution_max : Int32 = 4000

///|
const Search_refinement : Int32 = 2

///|
const Search_resolution_max : Int32 = Json_resolution_max / Search_refinement

///|
const Segments_max : Int32 = 128

///|
const Search_intervals_max : Int32 = 256

///|
const Profile_points_min : Int32 = 4

///|
const Profile_points_max : Int32 = 25000

///|
const Crossing_pair_budget : Int32 = 4000000

///|
const Input_bytes_max : Int32 = 200000

///|
const Geometry_length_max : Double = 1.0e6

///|
const Base_radius_min : Double = 1.0e-6

///|
const Segment_angle_min : Double = 1.0e-6

///|
const Coordinate_max : Double = 1.0e150

///|
const Closure_relative_tolerance : Double = 1.0e-10

///|
const Offset_factor_min : Double = 1.0e-6

///|
const Crossing_witnesses_max : Int32 = 32

///|
const Comparison_levels_max : Int32 = 4

///|
/// Stable wire categories. Human-readable error messages are not an API.
pub(all) enum ErrorCode {
  InvalidJson
  InvalidRequest
  InputTooLarge
  CalculationFailed
  CheckIndeterminate
  NoCandidateFound
  InternalError
  NoResult
}

///|
pub fn ErrorCode::code(self : ErrorCode) -> String {
  match self {
    InvalidJson => "invalid_json"
    InvalidRequest => "invalid_input"
    InputTooLarge => "input_too_large"
    CalculationFailed => "calculation_failed"
    CheckIndeterminate => "check_indeterminate"
    NoCandidateFound => "no_candidate"
    InternalError => "internal_error"
    NoResult => "no_result"
  }
}

///|
pub fn ErrorCode::exit_code(self : ErrorCode) -> Int32 {
  match self {
    CheckIndeterminate => 4
    NoCandidateFound => 3
    _ => 1
  }
}

///|
/// Host fallback: unknown error codes are errors, never successful completion.
pub fn error_exit_code(code : String) -> Int32 {
  for item in error_codes() {
    if item.code() == code {
      return item.exit_code()
    }
  }
  1
}

///|
fn error_codes() -> Array[ErrorCode] {
  [
    InvalidJson,
    InvalidRequest,
    InputTooLarge,
    CalculationFailed,
    CheckIndeterminate,
    NoCandidateFound,
    InternalError,
    NoResult,
  ]
}

///|
pub fn CrossingCheck::status(self : CrossingCheck) -> String {
  match self {
    NotChecked => "not_checked"
    Checked(_) => "complete"
    Indeterminate(_, _) => "indeterminate"
    Failed(_) => "failed"
  }
}

///|
/// Includes topology completion; an uncertain local pass is still incomplete.
pub fn Analysis::state(self : Analysis) -> String {
  result_state(self.sampled_local_feasible, self.crossings)
}

///|
fn result_state(local_ok : Bool, check : CrossingCheck) -> String {
  match check {
    Checked(_) =>
      if sampled_acceptance(local_ok, check) {
        "accepted_sampled"
      } else {
        "rejected"
      }
    _ => "incomplete"
  }
}

///|
pub fn result_exit_code(state : String) -> Int32 {
  match state {
    "accepted_sampled" => 0
    "rejected" => 2
    "incomplete" => 4
    _ => 1
  }
}

///|
/// Machine-readable source for checked-in contract documentation.
pub fn contract_json() -> String {
  let value : Json = {
    "schema_version": Json(Schema_version),
    "limits": {
      "resolution_min": Json(Resolution_min),
      "library_resolution_max": Json(Library_resolution_max),
      "json_resolution_max": Json(Json_resolution_max),
      "search_resolution_max": Json(Search_resolution_max),
      "search_refinement": Json(Search_refinement),
      "segments_max": Json(Segments_max),
      "search_intervals_max": Json(Search_intervals_max),
      "profile_points_min": Json(Profile_points_min),
      "profile_points_max": Json(Profile_points_max),
      "crossing_pair_budget": Json(Crossing_pair_budget),
      "input_bytes_max": Json(Input_bytes_max),
      "base_radius_min": Json(Base_radius_min),
      "geometry_length_max": Json(Geometry_length_max),
      "coordinate_max": Json(Coordinate_max),
      "segment_angle_min": Json(Segment_angle_min),
      "closure_relative_tolerance": Json(Closure_relative_tolerance),
      "offset_factor_min": Json(Offset_factor_min),
      "crossing_witnesses_max": Json(Crossing_witnesses_max),
      "comparison_levels_max": Json(Comparison_levels_max),
    },
    "errors": Json(
      error_codes().map(fn(item) {
        { "code": Json(item.code()), "exit_code": Json(item.exit_code()) }
      }),
    ),
    "result_states": Json(
      [
        result_state(true, Checked(0)),
        result_state(false, Checked(0)),
        result_state(true, NotChecked),
      ].map(fn(state) {
        { "state": Json(state), "exit_code": Json(result_exit_code(state)) }
      }),
    ),
    "crossing_states": Json(
      [NotChecked, Checked(0), Indeterminate(0, 1), Failed("")].map(fn(check) {
        Json(check.status())
      }),
    ),
    "position_contract": {
      "index_base": 0,
      "segment_intervals": "left_closed_right_open",
      "periodic_endpoint_segment": 0,
      "edge_definition": "edge i joins samples i and i+1; N+1 closed samples have N edges",
      "index_scope": "sample and edge indices belong to one sampling result; never compare across levels",
      "fields": {
        "sample_index": "采样点的零基下标；纯角度查询为 null，不隐含最近采样点。",
        "segment_index": "程序段的零基下标；段界归右侧段，网页展示段号时加一。",
        "theta_rad": "本圈角度（弧度），闭合点保留 2π。",
        "segment_start_rad": "所属程序段的起始角度（弧度）。",
        "segment_end_rad": "所属程序段的结束角度（弧度）。",
        "law": "所属段的规律：cycloidal、345 或 4567。",
        "periodic_endpoint": "是否为 2π 周期端点；运动值和点归首段，最后一条边仍归末段。",
        "edge_index": "边的零基下标，连接点 i 与 i+1。",
        "start": "边起点的位置，含该采样点下标。",
        "end": "边终点的位置；段界终点可属于下一段。",
      },
    },
    "diagnostic_contract": {
      "reason_codes": [
        "pressure_limit_exceeded", "offset_factor_rejected", "profile_crossings",
        "geometry_indeterminate", "geometry_failed", "geometry_not_checked",
      ],
      "witness_kinds": [
        "proper_crossing", "uncertain_contact", "adjacent_reversal",
      ],
      "fields": {
        "diagnostics": "局部约束的数值、阈值、余量、通过状态、位置及综合原因码。",
        "margin": "压力角为 limit-value；偏置因子为 value-limit；正数表示有余量，不是安全认证。",
        "comparison": "压力角允许等于上限；偏置因子必须严格大于阈值。",
        "crossing_evidence": "最多保留指定数量的边对，数量达到上限后仍继续统计全部交叉与不确定对。",
        "witnesses": "含 kind、edge_a、edge_b；每条边附位置和端点坐标，不计算或声称精确交点。",
        "truncated": "是否存在未保留的证据；空证据不能单独证明检查完成。",
        "compare_sampling": "可选布尔请求字段，默认 false；true 为最终机构尺寸执行三档完整采样检查。",
        "sampling_comparison": "每档拥有独立点号和边号；包含最差位置、局部余量、拓扑状态和综合状态。",
        "last_pressure_change_deg": "最后两档最大压力角的绝对差（度），不是误差界。",
        "last_offset_factor_change": "最后两档最小偏置因子的绝对差，不是误差界。",
        "state_consistent": "各档综合状态是否相同；即使全部 incomplete 也可为 true，不代表通过。",
      },
    },
  }
  value.stringify()
}

///|
/// Coordinates must already be finite and bounded. No world-origin tolerance.
fn profile_closed(points : Array[CamPoint]) -> Bool {
  let first = points[0]
  let last = points[points.length() - 1]
  let mut min_x = first.x
  let mut max_x = first.x
  let mut min_y = first.y
  let mut max_y = first.y
  for p in points {
    min_x = min_x.min(p.x)
    max_x = max_x.max(p.x)
    min_y = min_y.min(p.y)
    max_y = max_y.max(p.y)
  }
  let span = (max_x - min_x).max(max_y - min_y)
  if span == 0.0 {
    return first.x == last.x && first.y == last.y
  }
  @math.hypot((first.x - last.x) / span, (first.y - last.y) / span) <=
  Closure_relative_tolerance
}
