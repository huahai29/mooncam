///|
/// Export angular derivatives explicitly; time scaling is given in report JSON.
pub fn csv(points : Array[CamPoint]) -> String {
  let lines = [
    "theta_rad,lift,ds_dtheta,d2s_dtheta2,d3s_dtheta3,pitch_x,pitch_y,cam_x,cam_y,pressure_rad,pitch_curvature,offset_factor",
  ]
  for c in points {
    lines.push(
      "\{c.theta},\{c.motion.s},\{c.motion.v},\{c.motion.a},\{c.motion.j},\{c.pitch_x},\{c.pitch_y},\{c.x},\{c.y},\{c.pressure},\{c.curvature},\{c.offset_factor}",
    )
  }
  lines.join("\n") + "\n"
}

///|
/// Font-independent SVG. Model y is up; SVG y is down.
pub fn svg(points : Array[CamPoint]) -> String {
  let mut extent = 1.0
  let path = StringBuilder()
  for c in points {
    let roller = @math.hypot(c.pitch_x - c.x, c.pitch_y - c.y)
    extent = extent
      .max(c.x.abs())
      .max(c.y.abs())
      .max(c.pitch_x.abs() + roller)
      .max(c.pitch_y.abs() + roller)
    path.write_string("\{c.x},\{-c.y} ")
  }
  let margin = extent * 1.15
  let size = margin * 2.0
  let width = extent * 0.008
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\{-margin} \{-margin} \{size} \{size}\" role=\"img\" aria-label=\"Cam contact profile\"><rect x=\"\{-margin}\" y=\"\{-margin}\" width=\"\{size}\" height=\"\{size}\" fill=\"#f5f7fa\"/><polyline fill=\"none\" stroke=\"#087f8c\" stroke-width=\"\{width}\" points=\"" +
  path.to_string() +
  "\"/></svg>"
}

///|
/// ASCII DXF R2000, closed LWPOLYLINE in millimetres. Coordinates are sampled.
pub fn dxf_mm(points : Array[CamPoint]) -> String {
  let n = if points.length() > 1 { points.length() - 1 } else { 0 }
  let lines = [
    "0",
    "SECTION",
    "2",
    "HEADER",
    "9",
    "$ACADVER",
    "1",
    "AC1015",
    "9",
    "$INSUNITS",
    "70",
    "4",
    "0",
    "ENDSEC",
    "0",
    "SECTION",
    "2",
    "ENTITIES",
    "0",
    "LWPOLYLINE",
    "100",
    "AcDbEntity",
    "8",
    "MOONCAM",
    "100",
    "AcDbPolyline",
    "90",
    n.to_string(),
    "70",
    "1",
  ]
  for i = 0; i < n; i = i + 1 {
    lines.push("10")
    lines.push(points[i].x.to_string())
    lines.push("20")
    lines.push(points[i].y.to_string())
  }
  lines.push("0")
  lines.push("ENDSEC")
  lines.push("0")
  lines.push("EOF")
  lines.join("\n") + "\n"
}
