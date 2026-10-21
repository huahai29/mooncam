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
fn report(
  a : Analysis,
  g : Geometry,
  omega : Double,
  resolution : Int32,
) -> Json {
  let pts = a.points.map(fn(c) {
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
  })
  {
    "schema_version": 1,
    "units": "mm",
    "sampled_local_feasible": Json(a.sampled_feasible),
    "base_radius_mm": Json(g.base_radius),
    "roller_radius_mm": Json(g.roller_radius),
    "offset_mm": Json(g.offset),
    "omega_rad_s": Json(omega),
    "resolution": Json(resolution),
    "sample_count": Json(a.points.length()),
    "max_pressure_deg": Json(a.max_pressure * 180.0 / @math.PI),
    "worst_pressure_angle_deg": Json(a.pressure_angle * 180.0 / @math.PI),
    "min_offset_factor": Json(a.min_offset_factor),
    "max_velocity_mm_s": Json(a.max_velocity),
    "max_acceleration_mm_s2": Json(a.max_acceleration),
    "max_jerk_mm_s3": Json(a.max_jerk),
    "jerk_jumps": Json(a.jerk_jumps),
    "sampled_profile_crossings": Json(profile_crossings(a.points).unwrap_or(-1)),
    "scope": "Sampled local kinematic and geometric checks; no global collision or strength certification.",
    "points": Json(pts),
    "csv": csv(a.points),
    "svg": svg(a.points),
    "dxf": dxf_mm(a.points),
  }
}

///|
/// JSON entry point shared by Node CLI and browser. All numeric work is MoonBit.
pub fn run_json(input : String) -> String {
  try {
    if input.length() > 200000 {
      raise InputError("input exceeds 200000 characters")
    }
    let value = @json.parse(input)
    let f = obj(value, [
      "action", "units", "segments", "base_radius_mm", "roller_radius_mm", "offset_mm",
      "rpm", "resolution", "pressure_limit_deg", "search",
    ])
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
          "input": value,
          "result": report(a, g, omega, resolution),
        }
      }
      "search" => {
        let s = obj(required(f, "search"), ["lower_mm", "upper_mm", "intervals"])
        let found = checked(
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
          "input": value,
          "tested": Json(found.tested),
          "grid_step_mm": Json(found.grid_step),
          "search_scope": "First feasible increasing-grid candidate, verified on a doubled angular mesh; not a global minimum.",
          "result": report(
            found.analysis,
            found.geometry,
            omega,
            found.verification_resolution,
          ),
        }
      }
      _ => raise InputError("action must be analyze or search")
    }
    result.stringify()
  } catch {
    InputError(message) => {
      let err : Json = { "ok": false, "error": message }
      err.stringify()
    }
    _ => {
      let err : Json = { "ok": false, "error": "invalid JSON" }
      err.stringify()
    }
  }
}
