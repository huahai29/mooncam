///|
/// Angular extent in radians; signed lift in the chosen length unit.
pub(all) struct Segment {
  angle : Double
  lift : Double
  law : Law
}

///|
/// Validated closed program. Constructor owns a copy of the segment array.
pub struct Program {
  segments : Array[Segment]
  starts : Array[Double]
  heights : Array[Double]
}

///|
/// Build a closed one-revolution program starting at zero lift.
pub fn program(segments : Array[Segment]) -> Result[Program, String] {
  if segments.length() == 0 || segments.length() > 128 {
    return Err("program requires 1 to 128 segments")
  }
  let mut angle = 0.0
  let mut lift = 0.0
  let mut travel = 0.0
  let starts : Array[Double] = []
  let heights : Array[Double] = []
  for segment in segments {
    starts.push(angle)
    heights.push(lift)
    if !finite(segment.angle) || segment.angle < 1.0e-6 || !finite(segment.lift) {
      return Err(
        "segment angle must be finite and >= 1e-6 rad; lift must be finite",
      )
    }
    angle = angle + segment.angle
    lift = lift + segment.lift
    travel = travel + segment.lift.abs()
    if !finite(lift) || !finite(travel) || lift < -1.0e-9 {
      return Err("program must keep lift nonnegative and finite")
    }
  }
  if (angle - 2.0 * @math.PI).abs() > 1.0e-9 {
    return Err("segment angles must sum to one revolution")
  }
  if lift.abs() > 1.0e-9 {
    return Err("program must return to zero lift")
  }
  Ok({ segments: segments.map(fn(s) { s }), starts, heights, })
}

///|
/// Angular derivatives ds/dtheta, d2s/dtheta2 and d3s/dtheta3.
pub fn evaluate(p : Program, theta : Double) -> Result[Motion, String] {
  if !finite(theta) || theta.abs() > 1.0e12 {
    return Err("angle must be finite and within +/- 1e12 radians")
  }
  let tau = 2.0 * @math.PI
  let t = theta - @math.floor(theta / tau) * tau
  let mut lo = 0
  let mut hi = p.segments.length()
  while lo + 1 < hi {
    let mid = (lo + hi) / 2
    if p.starts[mid] <= t {
      lo = mid
    } else {
      hi = mid
    }
  }
  let seg = p.segments[lo]
  segment_motion(
    seg,
    p.heights[lo],
    ((t - p.starts[lo]) / seg.angle).clamp(min=0.0, max=1.0),
  )
}

///|
/// Internal segment evaluation; callers own phase bounds and validation.
fn segment_motion(
  seg : Segment,
  height : Double,
  u : Double,
) -> Result[Motion, String] {
  let n = normalized(seg.law, u).unwrap()
  let value : Motion = {
    s: height + seg.lift * n.s,
    v: seg.lift * n.v / seg.angle,
    a: seg.lift * n.a / (seg.angle * seg.angle),
    j: seg.lift * n.j / (seg.angle * seg.angle * seg.angle),
  }
  if !finite(value.s) ||
    !finite(value.v) ||
    !finite(value.a) ||
    !finite(value.j) {
    return Err("angular derivatives overflow; revise segment lengths or angles")
  }
  Ok(value)
}

///|
/// Scale cached angular derivatives. Omega is validated by the public boundary.
fn scale_motion(m : Motion, omega : Double) -> Result[Motion, String] {
  let value : Motion = {
    s: m.s,
    v: m.v * omega,
    a: m.a * omega * omega,
    j: m.j * omega * omega * omega,
  }
  if !finite(value.v) || !finite(value.a) || !finite(value.j) {
    Err("time derivatives overflow; reduce speed or revise motion")
  } else {
    Ok(value)
  }
}

///|
/// Physical time derivatives for a positive constant shaft speed in rad/s.
pub fn timed(
  p : Program,
  theta : Double,
  omega : Double,
) -> Result[Motion, String] {
  if !finite(omega) || omega <= 0.0 {
    return Err("angular speed must be finite and positive")
  }
  match evaluate(p, theta) {
    Err(e) => Err(e)
    Ok(m) => scale_motion(m, omega)
  }
}

///|
/// A 20-unit rise / dwell / return / dwell example.
pub fn example_program(law : Law) -> Program {
  let q = @math.PI / 2.0
  program([
    { angle: q, lift: 20.0, law, },
    { angle: q, lift: 0.0, law, },
    { angle: q, lift: -20.0, law, },
    { angle: q, lift: 0.0, law, },
  ]).unwrap()
}
