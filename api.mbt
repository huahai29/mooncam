///|
const Schema_version : Int32 = 2

///|
priv suberror InputError {
  InputError(String)
}

///|
priv suberror FieldError {
  FieldError(String, String)
}

///|
fn obj(value : Json, allowed : Array[String]) -> Map[String, Json] raise {
  guard value is Object(fields) else { raise InputError("expected object") }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise FieldError(key, "unknown field: " + key)
    }
  }
  fields
}

///|
fn required(fields : Map[String, Json], key : String) -> Json raise {
  match fields.get(key) {
    Some(v) => v
    None => raise FieldError(key, "missing field: " + key)
  }
}

///|
fn num(fields : Map[String, Json], key : String) -> Double raise {
  match required(fields, key) {
    Number(n, ..) =>
      if finite(n) {
        n
      } else {
        raise FieldError(key, "non-finite field: " + key)
      }
    _ => raise FieldError(key, "expected number: " + key)
  }
}

///|
fn integer(
  fields : Map[String, Json],
  key : String,
  low : Int32,
  high : Int32,
) -> Int32 raise {
  let n = num(fields, key)
  if n < low.to_double() || n > high.to_double() || @math.floor(n) != n {
    raise FieldError(key, "integer out of range: " + key)
  }
  n.to_int()
}

///|
fn text(fields : Map[String, Json], key : String) -> String raise {
  match required(fields, key) {
    String(s) => s
    _ => raise FieldError(key, "expected string: " + key)
  }
}

///|
fn[T] checked(value : Result[T, String]) -> T raise {
  match value {
    Ok(v) => v
    Err(e) => raise InputError(e)
  }
}

///|
fn checked_search(
  value : Result[SearchResult, SearchError],
) -> SearchResult raise {
  match value {
    Ok(v) => v
    Err(InvalidInput(e)) => raise InputError(e)
    Err(IndeterminateGeometry(e)) =>
      raise RequestError("check_indeterminate", e)
    Err(NumericalFailure(e)) => raise RequestError("calculation_failed", e)
    Err(NoCandidate(_)) =>
      raise RequestError(
        "no_candidate", "no sampled-accepted grid candidate found; this is not proof of continuous infeasibility",
      )
  }
}

///|
fn decode_program(value : Json) -> Program raise {
  guard value is Array(items) else {
    raise InputError("segments must be an array")
  }
  if items.length() > 128 {
    raise InputError("too many segments")
  }
  let segments : Array[Segment] = []
  for item in items {
    let f = obj(item, ["angle_deg", "lift_mm", "law"])
    let law = match text(f, "law") {
      "cycloidal" => Cycloidal
      "345" => Polynomial345
      "4567" => Polynomial4567
      _ => raise InputError("law must be cycloidal, 345 or 4567")
    }
    let lift = num(f, "lift_mm")
    if lift.abs() > 1.0e6 {
      raise InputError("lift magnitude exceeds 1e6 mm")
    }
    segments.push({ angle: num(f, "angle_deg") * @math.PI / 180.0, lift, law, })
  }
  checked(program(segments))
}

///|
/// Shared wire limit in UTF-8 bytes, exported to CLI hosts.
pub fn input_limit_bytes() -> Int32 {
  200000
}

///|
priv suberror RequestError {
  RequestError(String, String)
}

///|
fn selected_outputs(f : Map[String, Json]) -> Array[String] raise {
  let choices : Array[String] = []
  let value = f.get("outputs").unwrap_or(Json(["points"]))
  guard value is Array(items) else {
    raise FieldError("outputs", "outputs must be an array")
  }
  for item in items {
    guard item is String(name) else {
      raise FieldError("outputs", "output names must be strings")
    }
    if !["points", "csv", "svg", "dxf"].contains(name) || choices.contains(name) {
      raise FieldError("outputs", "unknown or duplicate output: " + name)
    }
    choices.push(name)
  }
  choices
}

///|
fn error_json(code : String, message : String) -> String {
  field_error_json(code, message, Json(null))
}

///|
fn field_error_json(code : String, message : String, field : Json) -> String {
  let err : Json = {
    "ok": false,
    "schema_version": Json(Schema_version),
    "error_code": code,
    "field": field,
    "error": message,
  }
  err.stringify()
}

///|
fn crossing_json(check : CrossingCheck) -> Json {
  match check {
    Indeterminate(n, pairs) =>
      {
        "status": "indeterminate",
        "count": Json(null),
        "confirmed_crossings": Json(n),
        "uncertain_pairs": Json(pairs),
      }
    Checked(n) => { "status": "complete", "count": Json(n) }
    NotChecked => { "status": "not_checked", "count": Json(null) }
    Failed(message) =>
      { "status": "failed", "count": Json(null), "error": message }
  }
}

///|
/// Summaries are always present; heavy outputs are generated only on request.
fn report(
  a : Analysis,
  g : Geometry,
  omega : Double,
  outputs : Array[String],
) -> Json {
  let state = match a.crossings {
    Checked(_) =>
      if a.sampled_feasible {
        "accepted_sampled"
      } else {
        "rejected"
      }
    _ => "incomplete"
  }
  let fields : Map[String, Json] = {
    "schema_version": Json(Schema_version),
    "units": Json("mm"),
    "state": Json(state),
    "sampled_local_feasible": Json(a.sampled_local_feasible),
    "sampled_feasible": Json(a.sampled_feasible),
    "crossing_check": crossing_json(a.crossings),
    "base_radius_mm": Json(g.base_radius),
    "roller_radius_mm": Json(g.roller_radius),
    "offset_mm": Json(g.offset),
    "omega_rad_s": Json(omega),
    "sample_count": Json(a.points.length()),
    "sampling": Json({
      "nominal_resolution": Json(a.nominal_resolution),
      "actual_intervals": Json(a.points.length() - 1),
      "sample_count": Json(a.points.length()),
      "preserves_segment_boundaries": true,
    }),
    "max_pressure_deg": Json(a.max_pressure * 180.0 / @math.PI),
    "worst_pressure_angle_deg": Json(a.pressure_angle * 180.0 / @math.PI),
    "min_offset_factor": Json(a.min_offset_factor),
    "min_offset_factor_angle_rad": Json(a.min_offset_factor_angle),
    "max_velocity_mm_s": Json(a.max_velocity),
    "max_acceleration_mm_s2": Json(a.max_acceleration),
    "max_jerk_mm_s3": Json(a.max_jerk),
    "jerk_jumps": Json(a.jerk_jumps),
    "scope": Json(
      "Sampled local constraints plus filtered polyline crossing check; uncertain contacts never accepted; no continuous or global collision certification.",
    ),
  }
  if outputs.contains("points") {
    fields.set(
      "points",
      Json(
        a.points.map(fn(c) {
          {
            "theta_rad": Json(c.theta),
            "lift_mm": Json(c.motion.s),
            "velocity_mm_s": Json(c.motion.v * omega),
            "acceleration_mm_s2": Json(c.motion.a * omega * omega),
            "jerk_mm_s3": Json(c.motion.j * omega * omega * omega),
            "pitch_x": Json(c.pitch_x),
            "pitch_y": Json(c.pitch_y),
            "x": Json(c.x),
            "y": Json(c.y),
            "pressure_deg": Json(c.pressure * 180.0 / @math.PI),
            "pitch_curvature": Json(c.curvature),
            "offset_factor": Json(c.offset_factor),
          }
        }),
      ),
    )
  }
  if outputs.contains("csv") {
    fields.set("csv", Json(csv(a.points)))
  }
  if outputs.contains("svg") {
    fields.set("svg", Json(svg(a.points)))
  }
  if outputs.contains("dxf") {
    fields.set("dxf", Json(dxf_mm(a.points)))
  }
  Json(fields)
}

///|
/// Schema v2: byte-bounded input, selected outputs, typed errors and check states.
fn run_json_cached(input : String, cache : Array[Array[CamPoint]]) -> String {
  cache.clear()
  try {
    if input.length() > input_limit_bytes() ||
      @utf8.encode(input).length() > input_limit_bytes() {
      raise RequestError("input_too_large", "input exceeds 200000 UTF-8 bytes")
    }
    let value = @json.parse(input) catch {
      _ => raise RequestError("invalid_json", "invalid JSON")
    }
    let f = obj(value, [
      "action", "units", "segments", "base_radius_mm", "roller_radius_mm", "offset_mm",
      "rpm", "resolution", "pressure_limit_deg", "search", "outputs", "include_input",
    ])
    let outputs = selected_outputs(f)
    let include_input = match f.get("include_input") {
      None => false
      Some(True) => true
      Some(False) => false
      _ => raise FieldError("include_input", "include_input must be boolean")
    }
    if text(f, "units") != "mm" {
      raise FieldError("units", "JSON interface requires mm units")
    }
    let p = decode_program(required(f, "segments"))
    let roller = num(f, "roller_radius_mm")
    let offset = num(f, "offset_mm")
    let omega = num(f, "rpm") * 2.0 * @math.PI / 60.0
    let resolution = integer(f, "resolution", 36, 4000)
    let pressure = num(f, "pressure_limit_deg") * @math.PI / 180.0
    let result : Json = match text(f, "action") {
      "analyze" => {
        let g : Geometry = {
          base_radius: num(f, "base_radius_mm"),
          roller_radius: roller,
          offset,
        }
        let a = checked(analyze(p, g, resolution, pressure, omega))
        cache.push(a.points)
        {
          "ok": true,
          "schema_version": Json(Schema_version),
          "result": report(a, g, omega, outputs),
        }
      }
      "search" => {
        let s = obj(required(f, "search"), ["lower_mm", "upper_mm", "intervals"])
        let found = checked_search(
          search_base(
            p,
            roller,
            offset,
            num(s, "lower_mm"),
            num(s, "upper_mm"),
            integer(s, "intervals", 1, 256),
            resolution,
            pressure,
            omega,
          ),
        )
        cache.push(found.analysis.points)
        {
          "ok": true,
          "schema_version": Json(Schema_version),
          "tested": Json(found.tested),
          "grid_step_mm": Json(found.grid_step),
          "search_scope": "First sampled-accepted grid candidate; topology completed on the fine mesh; not a continuous optimum.",
          "result": report(found.analysis, found.geometry, omega, outputs),
        }
      }
      _ => raise FieldError("action", "action must be analyze or search")
    }
    if include_input {
      match result {
        Object(fields) => fields.set("input", value)
        _ => ()
      }
    }
    result.stringify()
  } catch {
    FieldError(field, message) => {
      cache.clear()
      field_error_json("invalid_input", message, Json(field))
    }
    InputError(message) => {
      cache.clear()
      error_json("invalid_input", message)
    }
    RequestError(code, message) => {
      cache.clear()
      error_json(code, message)
    }
    _ => {
      cache.clear()
      error_json("internal_error", "unexpected calculation failure")
    }
  }
}

///|
/// Stateless request API. Use a Session to export a previous result without recomputation.
pub fn run_json(input : String) -> String {
  run_json_cached(input, [])
}

///|
/// One host-owned calculation result; cache lifetime is explicit, not process-global.
pub struct Session {
  points : Array[Array[CamPoint]]
}

///|
pub fn session() -> Session {
  { points: [], }
}

///|
pub fn Session::run(self : Session, input : String) -> String {
  run_json_cached(input, self.points)
}

///|
pub fn Session::export_profile(self : Session, format : String) -> String {
  if self.points.is_empty() {
    return error_json("no_result", "calculate before exporting")
  }
  let points = self.points[0]
  let content = match checked_export(points, format) {
    Ok(value) => value
    Err(message) => return error_json("invalid_input", message)
  }
  let result : Json = {
    "ok": true,
    "schema_version": Json(Schema_version),
    "format": Json(format),
    "content": Json(content),
  }
  result.stringify()
}
