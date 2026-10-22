///|
/// Broad-phase work counters permit regression tests without wall-clock claims.
pub(all) struct CrossingReport {
  crossings : Int32
  pair_visits : Int32
  uncertain_pairs : Int32
}

///|
/// A filtered orientation: zero means the floating-point sign is uncertain.
/// Local normalization avoids coupling the predicate to world coordinates.
fn orientation(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> Int32 {
  let dx = bx - ax
  let dy = by - ay
  let ex = cx - ax
  let ey = cy - ay
  let scale = dx.abs().max(dy.abs()).max(ex.abs()).max(ey.abs())
  if scale == 0.0 {
    return 0
  }
  let left = dx / scale * (ey / scale)
  let right = dy / scale * (ex / scale)
  let det = left - right
  let error = (left.abs() + right.abs()) * 2.0e-15
  if det > error {
    1
  } else if det < -error {
    -1
  } else {
    0
  }
}

///|
priv struct EdgeBounds {
  min_x : Double
  max_x : Double
  min_y : Double
  max_y : Double
  first_bin : Int32
}

///| Conservative dominant-axis spatial buckets. Each edge covers its full AABB span.

///| A pair belongs to its first common bucket, so it is never counted twice.

///|
/// Adversarial overlap has a bounded work budget and returns an incomplete check.
pub fn crossing_report(
  points : Array[CamPoint],
) -> Result[CrossingReport, String] {
  if points.length() < 4 || points.length() > 25000 {
    return Err("crossing check requires 4..25000 closed profile points")
  }
  let mut extent = 1.0
  let mut min_y = points[0].y
  let mut max_y = points[0].y
  let mut min_x = points[0].x
  let mut max_x = points[0].x
  for p in points {
    if !finite(p.x) || !finite(p.y) {
      return Err("non-finite profile coordinates")
    }
    extent = extent.max(p.x.abs()).max(p.y.abs())
    min_y = min_y.min(p.y)
    max_y = max_y.max(p.y)
    min_x = min_x.min(p.x)
    max_x = max_x.max(p.x)
  }
  if extent > 1.0e150 {
    return Err("profile coordinate scale exceeds safe crossing range")
  }
  let first = points[0]
  let last = points[points.length() - 1]
  if @math.hypot(first.x - last.x, first.y - last.y) >
    (max_x - min_x).max(max_y - min_y) * 1.0e-10 + extent * 2.0e-15 {
    return Err("profile polyline must be closed")
  }
  let n = points.length() - 1
  let use_y = max_y - min_y > max_x - min_x
  let origin = if use_y { min_y } else { min_x }
  let span = if use_y { max_y - min_y } else { max_x - min_x }
  if span == 0.0 {
    return Err("collapsed profile")
  }
  let bin_count = (n / 16).clamp(min=1, max=2048)
  let bin_of = fn(x : Double) {
    @math.floor((x - origin) / span * bin_count.to_double())
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
    if a.x == b.x && a.y == b.y {
      return Err("zero-length profile edge")
    }
    let lo = bin_of(if use_y { a.y.min(b.y) } else { left })
    let hi = bin_of(if use_y { a.y.max(b.y) } else { right })
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
  let mut uncertain_pairs = 0
  // Adjacent edges share a vertex legitimately, but must not reverse and overlap.
  for i = 0; i < n; i = i + 1 {
    let a = points[(i + n - 1) % n]
    let b = points[i]
    let c = points[(i + 1) % n]
    if orientation(a.x, a.y, b.x, b.y, c.x, c.y) == 0 {
      let ux = b.x - a.x
      let uy = b.y - a.y
      let vx = c.x - b.x
      let vy = c.y - b.y
      let scale = ux.abs().max(uy.abs()).max(vx.abs()).max(vy.abs())
      if scale > 0.0 &&
        ux / scale * (vx / scale) + uy / scale * (vy / scale) < 0.0 {
        uncertain_pairs = uncertain_pairs + 1
      }
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
        if pair_visits > 4000000 {
          return Err(
            "crossing work budget exceeded; geometry remains unchecked",
          )
        }
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
        let t1 = orientation(a.x, a.y, b.x, b.y, c.x, c.y)
        let t2 = orientation(a.x, a.y, b.x, b.y, d.x, d.y)
        let t3 = orientation(c.x, c.y, d.x, d.y, a.x, a.y)
        let t4 = orientation(c.x, c.y, d.x, d.y, b.x, b.y)
        if t1 * t2 > 0 || t3 * t4 > 0 {
          continue
        }
        if t1 * t2 < 0 && t3 * t4 < 0 {
          count = count + 1
        } else {
          uncertain_pairs = uncertain_pairs + 1
        }
      }
    }
  }
  Ok({ crossings: count, pair_visits, uncertain_pairs, })
}

///|
/// A complete Result is required; errors must not be interpreted as zero.
pub fn profile_crossings(points : Array[CamPoint]) -> Result[Int32, String] {
  match crossing_report(points) {
    Ok(r) =>
      if r.uncertain_pairs > 0 {
        Err("touching, overlapping or numerically uncertain profile edges")
      } else {
        Ok(r.crossings)
      }
    Err(e) => Err(e)
  }
}
