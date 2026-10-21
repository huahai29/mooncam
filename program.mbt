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
  for segment in segments {
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
  Ok({ segments: segments.map(fn(s) { s }), })
}

///|
/// Angular derivatives ds/dtheta, d2s/dtheta2 and d3s/dtheta3.
pub fn evaluate(p : Program, theta : Double) -> Result[Motion, String] {
  if !finite(theta) || theta.abs() > 1.0e12 {
    return Err("angle must be finite and within +/- 1e12 radians")
  }
  let tau = 2.0 * @math.PI
  let t = theta - @math.floor(theta / tau) * tau
  let mut begin = 0.0
  let mut height = 0.0
  for i = 0; i < p.segments.length(); i = i + 1 {
    let seg = p.segments[i]
    if t < begin + seg.angle || i == p.segments.length() - 1 {
      let u = ((t - begin) / seg.angle).clamp(min=0.0, max=1.0)
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
        return Err(
          "angular derivatives overflow; revise segment lengths or angles",
        )
      }
      return Ok(value)
    }
    begin = begin + seg.angle
    height = height + seg.lift
  }
  Err("unreachable empty program")
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
    Ok(m) => {
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
