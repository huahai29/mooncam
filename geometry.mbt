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
  if g.base_radius < Base_radius_min ||
    g.base_radius > Geometry_length_max ||
    g.roller_radius <= 0.0 ||
    g.roller_radius > Geometry_length_max {
    return Err(
      "base radius must be in [\{Base_radius_min}, \{Geometry_length_max}]; roller radius in (0, \{Geometry_length_max}]",
    )
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
  contact_prepared(g, zero_height(g), theta, m)
}

///|
/// Cached once per geometry, shared by sampling and metrics-only search.
fn zero_height(g : Geometry) -> Double {
  let r = g.base_radius + g.roller_radius
  ((r - g.offset) * (r + g.offset)).sqrt()
}

///|
/// No trigonometry or CamPoint allocation is required for scalar checks.
priv struct LocalGeometry {
  q : Double
  speed : Double
  pressure : Double
  curvature : Double
  factor : Double
}

///|
fn local_geometry(
  g : Geometry,
  q0 : Double,
  m : Motion,
) -> Result[LocalGeometry, String] {
  let q = q0 + m.s
  let d = m.v - g.offset
  let speed = @math.hypot(q, d)
  let k = (q * (q - m.a) + d * (2.0 * m.v - g.offset)) / (speed * speed * speed)
  let factor = 1.0 - g.roller_radius * k
  if !finite(q) || !finite(k) || !finite(factor) || speed <= 0.0 {
    return Err("non-finite or singular contact geometry")
  }
  Ok({ q, speed, pressure: @math.atan2(d, q), curvature: k, factor, })
}

///|
fn contact_prepared(
  g : Geometry,
  q0 : Double,
  theta : Double,
  m : Motion,
) -> Result[CamPoint, String] {
  let geom = match local_geometry(g, q0, m) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  contact_local(g, theta, m, geom)
}

///|
/// Construct full coordinates only for retained output points.
fn contact_local(
  g : Geometry,
  theta : Double,
  m : Motion,
  geom : LocalGeometry,
) -> Result[CamPoint, String] {
  let q = geom.q
  let sn = @math.sin(theta)
  let cs = @math.cos(theta)
  let px = q * sn + g.offset * cs
  let py = q * cs - g.offset * sn
  let dx = q * cs + (m.v - g.offset) * sn
  let dy = (m.v - g.offset) * cs - q * sn
  let speed = geom.speed
  let nx = -dy / speed
  let ny = dx / speed
  let x = px - g.roller_radius * nx
  let y = py - g.roller_radius * ny
  if !finite(x) || !finite(y) {
    return Err("non-finite contact coordinates")
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
    pressure: geom.pressure,
    curvature: geom.curvature,
    offset_factor: geom.factor,
  })
}
