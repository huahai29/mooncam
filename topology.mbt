///|
/// Orientation with a scale-relative tolerance for sampled line segments.
fn turn(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> Double {
  (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

///| Count proper crossings of nonadjacent sampled profile edges.

///|
/// Tangencies, collinear overlaps and between-sample loops are not certified.
pub fn profile_crossings(points : Array[CamPoint]) -> Result[Int32, String] {
  if points.length() < 4 || points.length() > 5000 {
    return Err("crossing check requires 4..5000 closed profile points")
  }
  let mut extent = 1.0
  for p in points {
    if !finite(p.x) || !finite(p.y) {
      return Err("non-finite profile coordinates")
    }
    extent = extent.max(p.x.abs()).max(p.y.abs())
  }
  let first = points[0]
  let last = points[points.length() - 1]
  if @math.hypot(first.x - last.x, first.y - last.y) > extent * 1.0e-8 {
    return Err("profile polyline must be closed")
  }
  let eps = extent * extent * 1.0e-12
  let mut count = 0
  let n = points.length() - 1
  for i = 0; i < n; i = i + 1 {
    let a = points[i]
    let b = points[i + 1]
    for j = i + 2; j < n; j = j + 1 {
      if i == 0 && j == n - 1 {
        continue
      }
      let c = points[j]
      let d = points[j + 1]
      if a.x.max(b.x) < c.x.min(d.x) ||
        c.x.max(d.x) < a.x.min(b.x) ||
        a.y.max(b.y) < c.y.min(d.y) ||
        c.y.max(d.y) < a.y.min(b.y) {
        continue
      }
      let t1 = turn(a.x, a.y, b.x, b.y, c.x, c.y)
      let t2 = turn(a.x, a.y, b.x, b.y, d.x, d.y)
      let t3 = turn(c.x, c.y, d.x, d.y, a.x, a.y)
      let t4 = turn(c.x, c.y, d.x, d.y, b.x, b.y)
      if ((t1 > eps && t2 < -eps) || (t1 < -eps && t2 > eps)) &&
        ((t3 > eps && t4 < -eps) || (t3 < -eps && t4 > eps)) {
        count = count + 1
      }
    }
  }
  Ok(count)
}
