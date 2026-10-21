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

///|
/// Broad-phase work counters permit regression tests without wall-clock claims.
pub(all) struct CrossingReport {
  crossings : Int32
  pair_visits : Int32
}

///|
priv struct EdgeBounds {
  min_x : Double
  max_x : Double
  min_y : Double
  max_y : Double
  first_bin : Int32
}

///| Conservative x-axis spatial buckets. Each edge covers its full AABB span.

///| A pair belongs to its first common bucket, so it is never counted twice.

///|
/// Worst-case quadratic behavior remains possible for heavily overlapping AABBs.
pub fn crossing_report(
  points : Array[CamPoint],
) -> Result[CrossingReport, String] {
  if points.length() < 4 || points.length() > 25000 {
    return Err("crossing check requires 4..25000 closed profile points")
  }
  let mut extent = 1.0
  let mut min_x = points[0].x
  let mut max_x = points[0].x
  for p in points {
    if !finite(p.x) || !finite(p.y) {
      return Err("non-finite profile coordinates")
    }
    extent = extent.max(p.x.abs()).max(p.y.abs())
    min_x = min_x.min(p.x)
    max_x = max_x.max(p.x)
  }
  if extent > 1.0e150 {
    return Err("profile coordinate scale exceeds safe crossing range")
  }
  let first = points[0]
  let last = points[points.length() - 1]
  if @math.hypot(first.x - last.x, first.y - last.y) > extent * 1.0e-8 {
    return Err("profile polyline must be closed")
  }
  let eps = extent * extent * 1.0e-12
  let n = points.length() - 1
  let bin_count = n.to_double().sqrt().to_int().clamp(min=1, max=128)
  let span = (max_x - min_x).max(1.0e-15)
  let bin_of = fn(x : Double) {
    @math.floor((x - min_x) / span * bin_count.to_double())
    .to_int()
    .clamp(min=0, max=bin_count - 1)
  }
  let buckets : Array[Array[Int32]] = Array::makei(bin_count, fn(_) { [] })
  let bounds : Array[EdgeBounds] = []
  for i = 0; i < n; i = i + 1 {
    let a = points[i]
    let b = points[i + 1]
    let left = a.x.min(b.x)
    let right = a.x.max(b.x)
    let lo = bin_of(left)
    let hi = bin_of(right)
    bounds.push({
      min_x: left,
      max_x: right,
      min_y: a.y.min(b.y),
      max_y: a.y.max(b.y),
      first_bin: lo,
    })
    for cell = lo; cell <= hi; cell = cell + 1 {
      buckets[cell].push(i)
    }
  }
  let mut count = 0
  let mut pair_visits = 0
  for cell = 0; cell < bin_count; cell = cell + 1 {
    let bucket = buckets[cell]
    for u = 0; u < bucket.length(); u = u + 1 {
      let i = bucket[u]
      let ab = bounds[i]
      for v = u + 1; v < bucket.length(); v = v + 1 {
        pair_visits = pair_visits + 1
        let j = bucket[v]
        let cd = bounds[j]
        if cell != ab.first_bin.max(cd.first_bin) ||
          j == i + 1 ||
          (i == 0 && j == n - 1) {
          continue
        }
        if ab.max_x < cd.min_x ||
          cd.max_x < ab.min_x ||
          ab.max_y < cd.min_y ||
          cd.max_y < ab.min_y {
          continue
        }
        let a = points[i]
        let b = points[i + 1]
        let c = points[j]
        let d = points[j + 1]
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
  }
  Ok({ crossings: count, pair_visits, })
}

///|
/// A complete Result is required; errors must not be interpreted as zero.
pub fn profile_crossings(points : Array[CamPoint]) -> Result[Int32, String] {
  match crossing_report(points) {
    Ok(r) => Ok(r.crossings)
    Err(e) => Err(e)
  }
}
