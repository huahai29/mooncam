///|
fn polygon(coords : Array[(Double, Double)]) -> Array[CamPoint] {
  let seed = contact(
    example_program(Cycloidal),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    0.0,
  ).unwrap()
  coords.map(fn(xy) { { ..seed, x: xy.0, y: xy.1, } })
}

///|
test "crossing signs survive scaling and translation" {
  for scale in [1.0e-100, 1.0e-7, 1.0, 1.0e100] {
    for shift in [0.0, scale * 1.0e6] {
      let pts = polygon([
        (0.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
        (1.0, 0.0),
        (0.0, 0.0),
      ]).map(fn(p) { { ..p, x: p.x * scale + shift, y: p.y * scale - shift, } })
      assert_eq(profile_crossings(pts).unwrap(), 1)
    }
  }
}

///|
test "touching and overlapping edges cannot produce acceptance" {
  let points = polygon([
    (0.0, 0.0),
    (2.0, 0.0),
    (1.0, 0.0),
    (1.0, 2.0),
    (0.0, 0.0),
  ])
  let info = crossing_report(points).unwrap()
  assert_true(info.uncertain_pairs > 0)
  assert_true(profile_crossings(points) is Err(_))
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let metrics = measure(example_program(Cycloidal), g, 72, 0.6, 1.0).unwrap()
  let a = finish_scan({ metrics, points, })
  assert_true(a.crossings is Indeterminate(_, _))
  assert_true(!a.sampled_feasible)
  assert_true(!sampled_acceptance(true, Indeterminate(0, 1)))
  guard crossing_json(a.crossings) is Object(fields) else {
    fail("expected object")
  }
  assert_eq(fields.get("status"), Some(Json("indeterminate")))
  assert_eq(fields.get("count"), Some(Json(null)))
}

///|
test "large narrow profiles retain bounded broad-phase work on either axis" {
  for vertical in [true, false] {
    let points : Array[CamPoint] = []
    let seed = polygon([(0.0, 0.0)])[0]
    for i = 0; i < 24000; i = i + 1 {
      let t = i.to_double() * 2.0 * @math.PI / 24000.0
      let x = @math.cos(t)
      let y = @math.sin(t)
      points.push({
        ..seed,
        x: x * (if vertical { 1.0e-9 } else { 1.0 }),
        y: y * (if vertical { 1.0 } else { 1.0e-9 }),
      })
    }
    points.push(points[0])
    let info = crossing_report(points).unwrap()
    assert_eq(info.crossings, 0)
    assert_eq(info.uncertain_pairs, 0)
    assert_true(info.pair_visits < 24000 * 100)
  }
}

///|
test "seeded polygons agree with exact integer determinant oracle" {
  let mut state = 107
  for _case = 0; _case < 80; _case = _case + 1 {
    let coords : Array[(Double, Double)] = []
    for i = 0; i < 32; i = i + 1 {
      state = (state * 37 + 19) % 100003
      coords.push((i.to_double(), (state % 1000).to_double()))
    }
    coords.push(coords[0])
    let points = polygon(coords)
    let info = crossing_report(points).unwrap()
    assert_eq(info.crossings, brute_crossings(points).unwrap())
  }
}

///|
test "checked exporters reject malformed point arrays and handle zero extent" {
  let one = polygon([(0.0, 0.0)])
  for format in ["svg", "dxf", "csv"] {
    assert_true(checked_export([], format) is Err(_))
    assert_true(checked_export(one, format) is Err(_))
    assert_true(checked_export([one[0], one[0]], format) is Err(_))
    let zeros = [one[0], one[0], one[0], one[0]]
    assert_true(checked_export(zeros, format) is Ok(_))
    let huge = zeros.map(fn(p) { { ..p, x: 1.0e200, } })
    assert_true(checked_export(huge, format) is Err(_))
  }
}

///|
test "adversarial bucket overlap terminates with an explicit incomplete check" {
  let points : Array[CamPoint] = []
  let seed = polygon([(0.0, 0.0)])[0]
  for i = 0; i < 4000; i = i + 1 {
    let theta = (i * 2001 % 4000).to_double() * 2.0 * @math.PI / 4000.0
    points.push({ ..seed, x: @math.cos(theta), y: @math.sin(theta), })
  }
  points.push(points[0])
  assert_true(
    crossing_report(points)
    is Err("crossing work budget exceeded; geometry remains unchecked"),
  )
}

///|
test "seeded analysis acceptance implies completed zero-crossing verification" {
  let mut state = 191
  for i = 0; i < 60; i = i + 1 {
    state = (state * 37 + 19) % 100003
    let radius = 5.0 + (state % 120).to_double()
    let g : Geometry = {
      base_radius: radius,
      roller_radius: 4.0,
      offset: (state % 7).to_double() - 3.0,
    }
    let law = [Cycloidal, Polynomial345, Polynomial4567][i % 3]
    let p = example_program(law)
    let a = analyze(p, g, 120, 0.6, 1.0).unwrap()
    let m = measure(p, g, 120, 0.6, 1.0).unwrap()
    near(a.min_offset_factor, m.min_offset_factor, 1.0e-12)
    if a.sampled_feasible {
      assert_true(a.sampled_local_feasible)
      assert_true(a.crossings is Checked(0))
    }
  }
}
