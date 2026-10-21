///|
/// Evaluate a normalized law. Internal callers validate u in [0, 1].
pub fn normalized(law : Law, u : Double) -> Result[Motion, String] {
  if !finite(u) || u < 0.0 || u > 1.0 {
    return Err("normalized phase must be finite and in [0, 1]")
  }
  let u2 = u * u
  let u3 = u2 * u
  let u4 = u3 * u
  let u5 = u4 * u
  let u6 = u5 * u
  let tau = 2.0 * @math.PI
  let result = match law {
    Cycloidal =>
      {
        s: u - @math.sin(tau * u) / tau,
        v: 1.0 - @math.cos(tau * u),
        a: tau * @math.sin(tau * u),
        j: tau * tau * @math.cos(tau * u),
      }
    Polynomial345 =>
      {
        s: 10.0 * u3 - 15.0 * u4 + 6.0 * u5,
        v: 30.0 * u2 - 60.0 * u3 + 30.0 * u4,
        a: 60.0 * u - 180.0 * u2 + 120.0 * u3,
        j: 60.0 - 360.0 * u + 360.0 * u2,
      }
    Polynomial4567 =>
      {
        s: 35.0 * u4 - 84.0 * u5 + 70.0 * u6 - 20.0 * u6 * u,
        v: 140.0 * u3 - 420.0 * u4 + 420.0 * u5 - 140.0 * u6,
        a: 420.0 * u2 - 1680.0 * u3 + 2100.0 * u4 - 840.0 * u5,
        j: 840.0 * u - 5040.0 * u2 + 8400.0 * u3 - 4200.0 * u4,
      }
  }
  Ok(result)
}
