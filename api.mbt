///|
priv suberror InputError {
  InputError(String)
}

///|
priv suberror FieldError {
  FieldError(String, String)
}

///|
/// Prefix nested field paths without parsing human-readable messages.
fn[T] located(path : String, action : () -> T raise) -> T raise {
  action() catch {
    FieldError(field, message) => raise FieldError(path + "." + field, message)
    InputError(message) => raise FieldError(path, message)
    e => raise e
  }
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
    Err(IndeterminateGeometry(e)) => raise RequestError(CheckIndeterminate, e)
    Err(NumericalFailure(e)) => raise RequestError(CalculationFailed, e)
    Err(NoCandidate(_)) =>
      raise RequestError(
        NoCandidateFound,
        "no sampled-accepted grid candidate found; this is not proof of continuous infeasibility",
      )
  }
}

///|
fn decode_program(value : Json) -> Program raise {
  guard value is Array(items) else {
    raise FieldError("segments", "segments must be an array")
  }
  if items.length() > Segments_max {
    raise FieldError("segments", "too many segments")
  }
  let segments : Array[Segment] = []
  for i = 0; i < items.length(); i = i + 1 {
    located("segments[\{i}]", fn() raise {
      let f = obj(items[i], ["angle_deg", "lift_mm", "law"])
      let law = match text(f, "law") {
        "cycloidal" => Cycloidal
        "345" => Polynomial345
        "4567" => Polynomial4567
        _ => raise FieldError("law", "law must be cycloidal, 345 or 4567")
      }
      let lift = num(f, "lift_mm")
      if lift.abs() > Geometry_length_max {
        raise FieldError(
          "lift_mm",
          "lift magnitude exceeds \{Geometry_length_max} mm",
        )
      }
      let angle = num(f, "angle_deg") * @math.PI / 180.0
      if !finite(angle) || angle < Segment_angle_min {
        raise FieldError(
          "angle_deg",
          "segment angle must be finite and >= \{Segment_angle_min} rad",
        )
      }
      segments.push({ angle, lift, law, })
    })
  }
  located("segments", fn() raise { checked(program(segments)) })
}

///|
/// Shared wire limit in UTF-8 bytes, exported to CLI hosts.
pub fn input_limit_bytes() -> Int32 {
  Input_bytes_max
}

///|
priv suberror RequestError {
  RequestError(ErrorCode, String)
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
fn error_json(code : ErrorCode, message : String) -> String {
  field_error_json(code, message, Json(null))
}

///|
fn field_error_json(code : ErrorCode, message : String, field : Json) -> String {
  let err : Json = {
    "ok": false,
    "schema_version": Json(Schema_version),
    "error_code": Json(code.code()),
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
        "status": Json(check.status()),
        "count": Json(null),
        "confirmed_crossings": Json(n),
        "uncertain_pairs": Json(pairs),
      }
    Checked(n) => { "status": Json(check.status()), "count": Json(n) }
    NotChecked => { "status": Json(check.status()), "count": Json(null) }
    Failed(message) =>
      { "status": Json(check.status()), "count": Json(null), "error": message }
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
  let state = a.state()
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
      raise RequestError(
        InputTooLarge,
        "input exceeds \{Input_bytes_max} UTF-8 bytes",
      )
    }
    let value = @json.parse(input) catch {
      _ => raise RequestError(InvalidJson, "invalid JSON")
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
    let action = text(f, "action")
    if action != "analyze" && action != "search" {
      raise FieldError("action", "action must be analyze or search")
    }
    let roller = num(f, "roller_radius_mm")
    if roller <= 0.0 || roller > Geometry_length_max {
      raise FieldError(
        "roller_radius_mm",
        "roller radius must be in (0, \{Geometry_length_max}]",
      )
    }
    let offset = num(f, "offset_mm")
    let omega = num(f, "rpm") * (2.0 * @math.PI / 60.0)
    if !finite(omega) || omega <= 0.0 {
      raise FieldError("rpm", "speed must be finite and positive")
    }
    let resolution = integer(
      f,
      "resolution",
      Resolution_min,
      Json_resolution_max,
    )
    if action == "search" && resolution > Search_resolution_max {
      raise FieldError(
        "resolution",
        "search resolution must be <= \{Search_resolution_max}",
      )
    }
    let pressure = num(f, "pressure_limit_deg") * (@math.PI / 180.0)
    if pressure <= 0.0 || pressure >= @math.PI / 2.0 {
      raise FieldError(
        "pressure_limit_deg", "pressure limit must be in (0, 90) degrees",
      )
    }
    let result : Json = match action {
      "analyze" => {
        let radius = num(f, "base_radius_mm")
        if radius < Base_radius_min || radius > Geometry_length_max {
          raise FieldError("base_radius_mm", "base radius out of range")
        }
        if offset.abs() >= radius + roller {
          raise FieldError(
            "offset_mm", "offset magnitude must be smaller than prime-circle radius",
          )
        }
        let g : Geometry = {
          base_radius: radius,
          roller_radius: roller,
          offset,
        }
        let a = match analyze(p, g, resolution, pressure, omega) {
          Ok(a) => a
          Err(e) => raise RequestError(CalculationFailed, e)
        }
        cache.push(a.points)
        {
          "ok": true,
          "schema_version": Json(Schema_version),
          "result": report(a, g, omega, outputs),
        }
      }
      "search" => {
        let search_value = required(f, "search")
        let (lower, upper, intervals) = located("search", fn() raise {
          let s = obj(search_value, ["lower_mm", "upper_mm", "intervals"])
          let lower = num(s, "lower_mm")
          let upper = num(s, "upper_mm")
          if lower < Base_radius_min || lower > Geometry_length_max {
            raise FieldError("lower_mm", "search lower radius out of range")
          }
          if upper < lower || upper > Geometry_length_max {
            raise FieldError(
              "upper_mm", "search upper radius out of range or below lower bound",
            )
          }
          (lower, upper, integer(s, "intervals", 1, Search_intervals_max))
        })
        if offset.abs() >= upper + roller {
          raise FieldError(
            "offset_mm", "offset magnitude must be smaller than upper prime-circle radius",
          )
        }
        let found = checked_search(
          search_base(
            p, roller, offset, lower, upper, intervals, resolution, pressure, omega,
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
      field_error_json(InvalidRequest, message, Json(field))
    }
    InputError(message) => {
      cache.clear()
      error_json(InvalidRequest, message)
    }
    RequestError(code, message) => {
      cache.clear()
      error_json(code, message)
    }
    _ => {
      cache.clear()
      error_json(InternalError, "unexpected calculation failure")
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
    return error_json(NoResult, "calculate before exporting")
  }
  let points = self.points[0]
  let content = match checked_export(points, format) {
    Ok(value) => value
    Err(message) => return error_json(InvalidRequest, message)
  }
  let result : Json = {
    "ok": true,
    "schema_version": Json(Schema_version),
    "format": Json(format),
    "content": Json(content),
  }
  result.stringify()
}
