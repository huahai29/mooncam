///| Geometry in consistent length units. Positive offset is along the x axis

///|
/// at zero cam angle. Cam coordinates use a clockwise angular parameter.
pub(all) struct Geometry {
  base_radius : Double
  roller_radius : Double
  offset : Double
}

///|
/// Pitch center, cam contact, outward normal and differential geometry.
pub(all) struct CamPoint {
  theta : Double
  motion : Motion
  pitch_x : Double
  pitch_y : Double
  x : Double
  y : Double
  normal_x : Double
  normal_y : Double
  pressure : Double
  curvature : Double
  offset_factor : Double
}

///|
pub fn validate_geometry(g : Geometry) -> Result[Unit, String] {
  if !finite(g.base_radius) || !finite(g.roller_radius) || !finite(g.offset) {
    return Err("geometry must be finite")
  }
  if g.base_radius < 1.0e-6 ||
    g.base_radius > 1.0e6 ||
    g.roller_radius <= 0.0 ||
    g.roller_radius > 1.0e6 {
    return Err("base radius must be in [1e-6, 1e6]; roller radius in (0, 1e6]")
  }
  if g.offset.abs() >= g.base_radius + g.roller_radius {
    return Err("offset magnitude must be smaller than prime-circle radius")
  }
  Ok(())
}

///|
/// Synthesize the roller-envelope contact point, not a radial subtraction.
pub fn contact(
  p : Program,
  g : Geometry,
  theta : Double,
) -> Result[CamPoint, String] {
  match validate_geometry(g) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let m = match evaluate(p, theta) {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  let r = g.base_radius + g.roller_radius
  let q = ((r - g.offset) * (r + g.offset)).sqrt() + m.s
  let sn = @math.sin(theta)
  let cs = @math.cos(theta)
  let px = q * sn + g.offset * cs
  let py = q * cs - g.offset * sn
  let dx = m.v * sn + q * cs - g.offset * sn
  let dy = m.v * cs - q * sn - g.offset * cs
  let ddx = m.a * sn + 2.0 * m.v * cs - q * sn - g.offset * cs
  let ddy = m.a * cs - 2.0 * m.v * sn - q * cs + g.offset * sn
  let speed = @math.hypot(dx, dy)
  let nx = -dy / speed
  let ny = dx / speed
  let k = (dy * ddx - dx * ddy) / (speed * speed * speed)
  let x = px - g.roller_radius * nx
  let y = py - g.roller_radius * ny
  let factor = 1.0 - g.roller_radius * k
  if !finite(x) || !finite(y) || !finite(k) || !finite(factor) || speed <= 0.0 {
    return Err("non-finite or singular contact geometry")
  }
  Ok({
    theta,
    motion: m,
    pitch_x: px,
    pitch_y: py,
    x,
    y,
    normal_x: nx,
    normal_y: ny,
    pressure: @math.atan2(m.v - g.offset, q),
    curvature: k,
    offset_factor: factor,
  })
}
