///|
/// Explicit completion state; unchecked and failed are never a zero count.
pub(all) enum CrossingCheck {
  NotChecked
  Checked(Int32)
  Indeterminate(Int32, Int32)
  Failed(String)
}

///|
/// Scalar-only analysis. Local feasibility excludes topology by definition.
pub(all) struct Metrics {
  max_pressure : Double
  pressure_angle : Double
  min_offset_factor : Double
  min_offset_factor_angle : Double
  max_velocity : Double
  max_acceleration : Double
  max_jerk : Double
  jerk_jumps : Int32
  sampled_local_feasible : Bool
  sample_count : Int32
  nominal_resolution : Int32
}

///|
/// Sampled acceptance requires local constraints AND a completed crossing check.
pub(all) struct Analysis {
  points : Array[CamPoint]
  max_pressure : Double
  pressure_angle : Double
  min_offset_factor : Double
  min_offset_factor_angle : Double
  max_velocity : Double
  max_acceleration : Double
  max_jerk : Double
  jerk_jumps : Int32
  sampled_local_feasible : Bool
  crossings : CrossingCheck
  sampled_feasible : Bool
  nominal_resolution : Int32
}

///|
priv struct MotionSample {
  theta : Double
  motion : Motion
}

///|
/// Geometry-independent mesh can be reused across every search candidate.
priv struct MotionMesh {
  samples : Array[MotionSample]
  endpoint_jerk : Double
  jerk_jumps : Int32
  nominal_resolution : Int32
}

///|
/// O(N+S) evaluation: the sampling loop already knows its segment index.
fn motion_mesh(p : Program, resolution : Int32) -> Result[MotionMesh, String] {
  if resolution < 36 || resolution > 20000 {
    return Err("resolution must be between 36 and 20000")
  }
  let out : Array[MotionSample] = []
  let mut endpoint_jerk = 0.0
  for k = 0; k < p.segments.length(); k = k + 1 {
    let seg = p.segments[k]
    let n = @math.ceil(seg.angle / (2.0 * @math.PI) * resolution.to_double())
      .to_int()
      .max(1)
    for i = 0; i < n; i = i + 1 {
      let u = i.to_double() / n.to_double()
      let m = match segment_motion(seg, p.heights[k], u) {
        Ok(m) => m
        Err(e) => return Err(e)
      }
      out.push({ theta: p.starts[k] + seg.angle * u, motion: m, })
    }
    for u in [0.0, 1.0] {
      let m = match segment_motion(seg, p.heights[k], u) {
        Ok(m) => m
        Err(e) => return Err(e)
      }
      endpoint_jerk = endpoint_jerk.max(m.j.abs())
    }
  }
  out.push({ theta: 2.0 * @math.PI, motion: out[0].motion, })
  Ok({
    samples: out,
    endpoint_jerk,
    jerk_jumps: jerk_jumps(p),
    nominal_resolution: resolution,
  })
}

///|
fn jerk_jumps(p : Program) -> Int32 {
  let mut count = 0
  let n = p.segments.length()
  for i = 0; i < n; i = i + 1 {
    let l = p.segments[i]
    let r = p.segments[(i + 1) % n]
    let jl = l.lift *
      normalized(l.law, 1.0).unwrap().j /
      (l.angle * l.angle * l.angle)
    let jr = r.lift *
      normalized(r.law, 0.0).unwrap().j /
      (r.angle * r.angle * r.angle)
    if (jl - jr).abs() > 1.0e-8 * (1.0 + jl.abs() + jr.abs()) {
      count = count + 1
    }
  }
  count
}

///|
fn validate_analysis(pressure : Double, omega : Double) -> Result[Unit, String] {
  if !finite(pressure) || pressure <= 0.0 || pressure >= @math.PI / 2.0 {
    return Err("pressure limit must be in (0, pi/2) radians")
  }
  if !finite(omega) || omega <= 0.0 {
    return Err("speed must be finite and positive")
  }
  Ok(())
}

///|
priv struct Scan {
  metrics : Metrics
  points : Array[CamPoint]
}

///|
/// Preconditions: geometry, pressure and speed validated once at the boundary.
fn scan_mesh(
  mesh : MotionMesh,
  g : Geometry,
  pressure_limit : Double,
  omega : Double,
  retain : Bool,
) -> Result[Scan, String] {
  let q0 = zero_height(g)
  let points : Array[CamPoint] = []
  let mut pressure = 0.0
  let mut pa = 0.0
  let mut factor = 0.0
  let mut first_factor = true
  let mut fa = 0.0
  let mut velocity = 0.0
  let mut acceleration = 0.0
  let mut jerk = mesh.endpoint_jerk * omega * omega * omega
  if !finite(jerk) {
    return Err("jerk overflow")
  }
  for item in mesh.samples {
    let geom = match local_geometry(g, q0, item.motion) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if geom.pressure.abs() > pressure {
      pressure = geom.pressure.abs()
      pa = item.theta
    }
    if first_factor || geom.factor < factor {
      first_factor = false
      factor = geom.factor
      fa = item.theta
    }
    let t = match scale_motion(item.motion, omega) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    velocity = velocity.max(t.v.abs())
    acceleration = acceleration.max(t.a.abs())
    jerk = jerk.max(t.j.abs())
    if retain {
      match contact_local(g, item.theta, item.motion, geom) {
        Ok(c) => points.push(c)
        Err(e) => return Err(e)
      }
    }
  }
  Ok({
    points,
    metrics: {
      max_pressure: pressure,
      pressure_angle: pa,
      min_offset_factor: factor,
      min_offset_factor_angle: fa,
      max_velocity: velocity,
      max_acceleration: acceleration,
      max_jerk: jerk,
      jerk_jumps: mesh.jerk_jumps,
      sampled_local_feasible: pressure <= pressure_limit && factor > 1.0e-6,
      sample_count: mesh.samples.length(),
      nominal_resolution: mesh.nominal_resolution,
    },
  })
}

///|
/// Pure state combination: a failed or absent check can never accept a profile.
pub fn sampled_acceptance(local_ok : Bool, crossings : CrossingCheck) -> Bool {
  match crossings {
    Checked(0) => local_ok
    _ => false
  }
}

///|
fn finish_scan(scan : Scan) -> Analysis {
  let m = scan.metrics
  let crossings = match crossing_report(scan.points) {
    Ok(r) =>
      if r.uncertain_pairs > 0 {
        Indeterminate(r.crossings, r.uncertain_pairs)
      } else {
        Checked(r.crossings)
      }
    Err(e) => Failed(e)
  }
  {
    points: scan.points,
    max_pressure: m.max_pressure,
    pressure_angle: m.pressure_angle,
    min_offset_factor: m.min_offset_factor,
    min_offset_factor_angle: m.min_offset_factor_angle,
    max_velocity: m.max_velocity,
    max_acceleration: m.max_acceleration,
    max_jerk: m.max_jerk,
    jerk_jumps: m.jerk_jumps,
    sampled_local_feasible: m.sampled_local_feasible,
    crossings,
    sampled_feasible: sampled_acceptance(m.sampled_local_feasible, crossings),
    nominal_resolution: m.nominal_resolution,
  }
}

///|
/// Full sampled analysis, including topology. Not a continuous geometry proof.
pub fn analyze(
  p : Program,
  g : Geometry,
  resolution : Int32,
  pressure_limit : Double,
  omega : Double,
) -> Result[Analysis, String] {
  match validate_analysis(pressure_limit, omega) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_geometry(g) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let mesh = match motion_mesh(p, resolution) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  match scan_mesh(mesh, g, pressure_limit, omega, true) {
    Ok(s) => Ok(finish_scan(s))
    Err(e) => Err(e)
  }
}

///|
/// Metrics only: no CamPoint collection, trigonometry, topology or exports.
pub fn measure(
  p : Program,
  g : Geometry,
  resolution : Int32,
  pressure_limit : Double,
  omega : Double,
) -> Result[Metrics, String] {
  match validate_analysis(pressure_limit, omega) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_geometry(g) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let mesh = match motion_mesh(p, resolution) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  match scan_mesh(mesh, g, pressure_limit, omega, false) {
    Ok(s) => Ok(s.metrics)
    Err(e) => Err(e)
  }
}

///|
/// The nominal resolution sets density; all segment boundaries are preserved.
pub fn sample(
  p : Program,
  g : Geometry,
  resolution : Int32,
) -> Result[Array[CamPoint], String] {
  match validate_geometry(g) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let mesh = match motion_mesh(p, resolution) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let q0 = zero_height(g)
  let out : Array[CamPoint] = []
  for item in mesh.samples {
    match contact_prepared(g, q0, item.theta, item.motion) {
      Ok(c) => out.push(c)
      Err(e) => return Err(e)
    }
  }
  Ok(out)
}
