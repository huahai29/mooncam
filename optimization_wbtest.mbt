///|
test "streamed segment mesh agrees with arbitrary-angle binary evaluation" {
  let segments : Array[Segment] = []
  for i = 0; i < 128; i = i + 1 {
    segments.push({
      angle: 2.0 * @math.PI / 128.0,
      lift: if i % 2 == 0 {
        1.0
      } else {
        -1.0
      },
      law: Polynomial4567,
    })
  }
  let p = program(segments).unwrap()
  let mesh = motion_mesh(p, 720).unwrap()
  for item in mesh.samples {
    let m = evaluate(p, item.theta).unwrap()
    near(item.motion.s, m.s, 1.0e-10)
    near(item.motion.v, m.v, 1.0e-7)
    near(item.motion.a, m.a, 1.0e-4)
  }
}

///|
test "metrics path matches full scalar analysis without retaining points" {
  for law in [Cycloidal, Polynomial345, Polynomial4567] {
    let p = example_program(law)
    let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: -8.0, }
    let m = measure(p, g, 720, 0.6, 3.0).unwrap()
    let a = analyze(p, g, 720, 0.6, 3.0).unwrap()
    near(m.max_pressure, a.max_pressure, 1.0e-12)
    near(m.min_offset_factor, a.min_offset_factor, 1.0e-12)
    near(m.max_jerk, a.max_jerk, 1.0e-9)
    assert_eq(m.sample_count, a.points.length())
    assert_eq(m.nominal_resolution, 720)
  }
}

///|
test "unchecked failed and crossed profiles cannot be accepted" {
  assert_true(!sampled_acceptance(true, NotChecked))
  assert_true(!sampled_acceptance(true, Failed("limit")))
  assert_true(!sampled_acceptance(true, Checked(1)))
  assert_true(!sampled_acceptance(false, Checked(0)))
  assert_true(sampled_acceptance(true, Checked(0)))
}
