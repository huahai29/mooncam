///|
/// Sampled evidence, not a continuous-time proof of manufacturability.
pub(all) struct Analysis {
  points : Array[CamPoint]
  max_pressure : Double
  pressure_angle : Double
  min_offset_factor : Double
  undercut_angle : Double
  max_velocity : Double
  max_acceleration : Double
  max_jerk : Double
  jerk_jumps : Int32
  sampled_feasible : Bool
}

///|
/// Segment-aware mesh contains every boundary and the final closure point.
pub fn sample(
  p : Program,
  g : Geometry,
  resolution : Int32,
) -> Result[Array[CamPoint], String] {
  if resolution < 36 || resolution > 20000 {
    return Err("resolution must be between 36 and 20000 samples per revolution")
  }
  match validate_geometry(g) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let out : Array[CamPoint] = []
  let mut start = 0.0
  for seg in p.segments {
    let n = @math.ceil(seg.angle / (2.0 * @math.PI) * resolution.to_double()).to_int()
    for i = 0; i < n; i = i + 1 {
      let theta = start + seg.angle * i.to_double() / n.to_double()
      match contact(p, g, theta) {
        Err(e) => return Err(e)
        Ok(c) => out.push(c)
      }
    }
    start = start + seg.angle
  }
  match contact(p, g, 2.0 * @math.PI) {
    Err(e) => Err(e)
    Ok(c) => {
      out.push(c)
      Ok(out)
    }
  }
}

///|
/// Count finite jerk discontinuities, including the revolution seam.
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
/// Pressure limit is a user choice in radians, not a universal standard.
pub fn analyze(
  p : Program,
  g : Geometry,
  resolution : Int32,
  pressure_limit : Double,
  omega : Double,
) -> Result[Analysis, String] {
  if !finite(pressure_limit) ||
    pressure_limit <= 0.0 ||
    pressure_limit >= @math.PI / 2.0 {
    return Err("pressure limit must be in (0, pi/2) radians")
  }
  if !finite(omega) || omega <= 0.0 {
    return Err("speed must be finite and positive")
  }
  let points = match sample(p, g, resolution) {
    Err(e) => return Err(e)
    Ok(a) => a
  }
  let mut pressure = 0.0
  let mut pa = 0.0
  let mut factor = 1.0
  let mut ua = 0.0
  let mut velocity = 0.0
  let mut acceleration = 0.0
  let mut jerk = 0.0
  for c in points {
    if c.pressure.abs() > pressure {
      pressure = c.pressure.abs()
      pa = c.theta
    }
    if c.offset_factor < factor {
      factor = c.offset_factor
      ua = c.theta
    }
    let t = match timed(p, c.theta, omega) {
      Err(e) => return Err(e)
      Ok(m) => m
    }
    velocity = velocity.max(t.v.abs())
    acceleration = acceleration.max(t.a.abs())
    jerk = jerk.max(t.j.abs())
  }
  // Include both one-sided endpoint jerk values even when a dwell follows.
  for seg in p.segments {
    for u in [0.0, 1.0] {
      let j = (seg.lift *
      normalized(seg.law, u).unwrap().j /
      (seg.angle * seg.angle * seg.angle) *
      omega *
      omega *
      omega).abs()
      if !finite(j) {
        return Err("jerk overflow")
      }
      jerk = jerk.max(j)
    }
  }
  Ok({
    points,
    max_pressure: pressure,
    pressure_angle: pa,
    min_offset_factor: factor,
    undercut_angle: ua,
    max_velocity: velocity,
    max_acceleration: acceleration,
    max_jerk: jerk,
    jerk_jumps: jerk_jumps(p),
    sampled_feasible: pressure <= pressure_limit && factor > 1.0e-6,
  })
}
