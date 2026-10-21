///|
test "analysis distinguishes feasible and pressure-limited geometry" {
  let p = example_program(Cycloidal)
  let a = analyze(
    p,
    { base_radius: 80.0, roller_radius: 4.0, offset: 0.0, },
    720,
    @math.PI / 6.0,
    2.0,
  ).unwrap()
  assert_true(a.sampled_feasible)
  assert_eq(a.jerk_jumps, 4)
  let b = analyze(
    p,
    { base_radius: 4.0, roller_radius: 4.0, offset: 0.0, },
    720,
    @math.PI / 6.0,
    2.0,
  ).unwrap()
  assert_true(!b.sampled_feasible)
  assert_true(b.max_pressure > a.max_pressure)
  assert_eq(jerk_jumps(example_program(Polynomial4567)), 0)
}

///|
test "mesh includes nonuniform boundaries and closes exactly" {
  let p = program([
    { angle: 0.01, lift: 1.0, law: Polynomial4567, },
    { angle: 1.0, lift: -1.0, law: Polynomial4567, },
    { angle: 2.0 * @math.PI - 1.01, lift: 0.0, law: Polynomial4567, },
  ]).unwrap()
  let a = sample(
    p,
    { base_radius: 20.0, roller_radius: 1.0, offset: 0.0, },
    360,
  ).unwrap()
  assert_true(a.any(fn(c) { (c.theta - 0.01).abs() < 1.0e-12 }))
  let first = a[0]
  let last = a[a.length() - 1]
  near(first.x, last.x, 1.0e-9)
  near(first.y, last.y, 1.0e-9)
  assert_true(
    sample(p, { base_radius: 20.0, roller_radius: 1.0, offset: 0.0, }, 0)
    is Err(_),
  )
}
