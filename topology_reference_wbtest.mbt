///|
/// Quadratic oracle retained only in tests.
fn brute_crossings(points : Array[CamPoint]) -> Result[Int32, String] {
  if points.length() < 4 || points.length() > 25000 {
    return Err("crossing check requires 4..25000 closed profile points")
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

///|
test "bucketed crossings match quadratic oracle on deterministic irregular polygons" {
  let seed = contact(
    example_program(Cycloidal),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    0.0,
  ).unwrap()
  for count in [4, 9, 37, 120] {
    for variant = 0; variant < 8; variant = variant + 1 {
      let points : Array[CamPoint] = []
      for i = 0; i < count; i = i + 1 {
        let x = ((i * 37 + variant * 11) % 101).to_double() - 50.0
        let y = ((i * i * 13 + variant * 23) % 97).to_double() - 48.0
        points.push({ ..seed, x, y, })
      }
      points.push(points[0])
      assert_eq(
        profile_crossings(points).unwrap(),
        brute_crossings(points).unwrap(),
      )
    }
  }
}

///|
test "buckets preserve degeneracies boundary spans and translated coordinates" {
  let seed = contact(
    example_program(Cycloidal),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    0.0,
  ).unwrap()
  for scale in [0.00001, 1.0, 1000.0] {
    let points : Array[CamPoint] = []
    for
      xy in [
        (0.0, 0.0),
        (2.0, 2.0),
        (0.0, 2.0),
        (2.0, 0.0),
        (2.0, 2.0),
        (0.0, 0.0),
      ] {
      points.push({ ..seed, x: xy.0 * scale + 3.0, y: xy.1 * scale - 3.0, })
    }
    assert_eq(
      profile_crossings(points).unwrap(),
      brute_crossings(points).unwrap(),
    )
  }
  let points = sample(
    example_program(Polynomial4567),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    4000,
  ).unwrap()
  let info = crossing_report(points).unwrap()
  assert_eq(info.crossings, 0)
  assert_true(info.pair_visits < 4000 * 4000 / 8)
  assert_true(profile_crossings([]) is Err(_))
}
