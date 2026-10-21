///|
test "all segment joins preserve position velocity and acceleration" {
  let h = 1.0e-7
  for law in [Cycloidal, Polynomial345, Polynomial4567] {
    let p = example_program(law)
    for boundary in [0.0, @math.PI / 2.0, @math.PI, 1.5 * @math.PI] {
      let l = evaluate(p, boundary - h).unwrap()
      let r = evaluate(p, boundary + h).unwrap()
      near(l.s, r.s, 1.0e-8)
      near(l.v, r.v, 1.0e-8)
      near(l.a, r.a, 0.0001)
    }
  }
}

///|
test "excessive derivatives are returned as errors" {
  let p = program([
    { angle: 0.00001, lift: 1.0e300, law: Polynomial345, },
    { angle: 2.0 * @math.PI - 0.00001, lift: -1.0e300, law: Polynomial345, },
  ]).unwrap()
  assert_true(evaluate(p, 0.000005) is Err(_))
  assert_true(timed(example_program(Cycloidal), 0.5, 1.0e300) is Err(_))
}

///|
test "profile topology identifies bow-tie crossings and excludes adjacent edges" {
  let c = contact(
    example_program(Cycloidal),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    0.0,
  ).unwrap()
  let points : Array[CamPoint] = []
  for xy in [(0.0, 0.0), (2.0, 2.0), (0.0, 2.0), (2.0, 0.0), (0.0, 0.0)] {
    points.push({ ..c, x: xy.0, y: xy.1, })
  }
  assert_eq(profile_crossings(points).unwrap(), 1)
  let a = sample(
    example_program(Polynomial4567),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    720,
  ).unwrap()
  assert_eq(profile_crossings(a).unwrap(), 0)
}
