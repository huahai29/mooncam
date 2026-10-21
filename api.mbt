///|
priv suberror InputError {
  InputError(String)
}

///|
fn obj(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise InputError {
  guard value is Object(fields) else { raise InputError("expected object") }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise InputError("unknown field: " + key)
    }
  }
  fields
}

///|
fn required(fields : Map[String, Json], key : String) -> Json raise InputError {
  match fields.get(key) {
    Some(v) => v
    None => raise InputError("missing field: " + key)
  }
}

///|
fn num(fields : Map[String, Json], key : String) -> Double raise InputError {
  match required(fields, key) {
    Number(n, ..) =>
      if finite(n) {
        n
      } else {
        raise InputError("non-finite field: " + key)
      }
    _ => raise InputError("expected number: " + key)
  }
}

///|
fn integer(
  fields : Map[String, Json],
  key : String,
  low : Int32,
  high : Int32,
) -> Int32 raise InputError {
  let n = num(fields, key)
  if n < low.to_double() || n > high.to_double() || @math.floor(n) != n {
    raise InputError("integer out of range: " + key)
  }
  n.to_int()
}

///|
fn text(fields : Map[String, Json], key : String) -> String raise InputError {
  match required(fields, key) {
    String(s) => s
    _ => raise InputError("expected string: " + key)
  }
}

///|
fn[T] checked(value : Result[T, String]) -> T raise InputError {
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
    Err(NumericalFailure(e)) => raise RequestError("calculation_failed", e)
    Err(NoCandidate(_)) =>
      raise RequestError(
        "no_candidate", "no sampled-accepted grid candidate found; this is not proof of continuous infeasibility",
      )
  }
}

///|
fn decode_program(value : Json) -> Program raise InputError {
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
fn selected_outputs(f : Map[String, Json]) -> Array[String] raise InputError {
  let choices : Array[String] = []
  let value = f.get("outputs").unwrap_or(Json(["points"]))
  guard value is Array(items) else {
    raise InputError("outputs must be an array")
  }
  for item in items {
    guard item is String(name) else {
      raise InputError("output names must be strings")
    }
    if !["points", "csv", "svg", "dxf"].contains(name) || choices.contains(name) {
      raise InputError("unknown or duplicate output: " + name)
    }
    choices.push(name)
  }
  choices
}

///|
fn error_json(code : String, message : String) -> String {
  let err : Json = {
    "ok": false,
    "schema_version": 2,
    "error_code": code,
    "error": message,
  }
  err.stringify()
}

///|
fn crossing_json(check : CrossingCheck) -> Json {
  match check {
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
    "schema_version": Json(2),
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
      "Sampled local constraints plus strict polyline crossing check; no continuous or global collision certification.",
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
pub fn run_json(input : String) -> String {
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
      _ => raise InputError("include_input must be boolean")
    }
    if text(f, "units") != "mm" {
      raise InputError("JSON interface requires mm units")
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
        {
          "ok": true,
          "schema_version": 2,
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
        {
          "ok": true,
          "schema_version": 2,
          "tested": Json(found.tested),
          "grid_step_mm": Json(found.grid_step),
          "search_scope": "First sampled-accepted grid candidate; topology completed on the fine mesh; not a continuous optimum.",
          "result": report(found.analysis, found.geometry, omega, outputs),
        }
      }
      _ => raise InputError("action must be analyze or search")
    }
    if include_input {
      match result {
        Object(fields) => fields.set("input", value)
        _ => ()
      }
    }
    result.stringify()
  } catch {
    InputError(message) => error_json("invalid_input", message)
    RequestError(code, message) => error_json(code, message)
    _ => error_json("internal_error", "unexpected calculation failure")
  }
}
