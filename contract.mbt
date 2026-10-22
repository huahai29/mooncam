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
