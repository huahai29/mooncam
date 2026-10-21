///|
test "dwell is an exact base circle even with follower offset" {
  let p = program([{ angle: 2.0 * @math.PI, lift: 0.0, law: Cycloidal, }]).unwrap()
  for offset in [0.0, 8.0, -8.0] {
    let g : Geometry = { base_radius: 30.0, roller_radius: 5.0, offset, }
    for t in [0.0, 0.7, 2.0, 5.5] {
      let c = contact(p, g, t).unwrap()
      near(@math.hypot(c.x, c.y), 30.0, 1.0e-10)
      near(c.curvature, 1.0 / 35.0, 1.0e-10)
    }
  }
}

///|
test "contact stays on roller and normal is perpendicular to pitch tangent" {
  let p = example_program(Cycloidal)
  let g : Geometry = { base_radius: 35.0, roller_radius: 4.0, offset: 3.0, }
  let h = 1.0e-5
  for t in [0.3, 0.8, 1.3, 3.7, 4.3] {
    let c = contact(p, g, t).unwrap()
    let l = contact(p, g, t - h).unwrap()
    let r = contact(p, g, t + h).unwrap()
    near(@math.hypot(c.pitch_x - c.x, c.pitch_y - c.y), 4.0, 1.0e-9)
    near(
      c.normal_x * (r.pitch_x - l.pitch_x) / (2.0 * h) +
      c.normal_y * (r.pitch_y - l.pitch_y) / (2.0 * h),
      0.0,
      1.0e-7,
    )
    // The contact normal also annihilates the actual envelope tangent.
    near(
      c.normal_x * (r.x - l.x) / (2.0 * h) +
      c.normal_y * (r.y - l.y) / (2.0 * h),
      0.0,
      1.0e-7,
    )
  }
}

///|
test "impossible offset and zero roller are rejected" {
  assert_true(
    validate_geometry({ base_radius: 10.0, roller_radius: 2.0, offset: 12.0, })
    is Err(_),
  )
  assert_true(
    validate_geometry({ base_radius: 10.0, roller_radius: 0.0, offset: 0.0, })
    is Err(_),
  )
}
