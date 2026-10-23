///|
test "diagnostic locations reference actual extrema and signed margins" {
  let p = example_program(Polynomial4567)
  let pressure = @math.PI / 6.0
  for base in [5.0, 40.0] {
    let a = analyze(
      p,
      { base_radius: base, roller_radius: 4.0, offset: 0.0, },
      720,
      pressure,
      1.0,
    ).unwrap()
    let d = diagnose(p, a, pressure).unwrap()
    let index = d.pressure.location.sample_index.unwrap()
    assert_eq(index, a.pressure_sample_index)
    near(a.points[index].theta, a.pressure_angle, 0.0)
    near(a.points[index].pressure.abs(), d.pressure.value, 0.0)
    near(d.pressure.margin, pressure - a.max_pressure, 0.0)
    near(d.offset_factor.margin, a.min_offset_factor - Offset_factor_min, 0.0)
    assert_eq(d.pressure.passed, base == 40.0)
    assert_eq(
      d.pressure.location.segment_index,
      locate_sample(p, a.points, index).unwrap().segment_index,
    )
    let equality = diagnose(
      p,
      { ..a, max_pressure: pressure, min_offset_factor: Offset_factor_min, },
      pressure,
    ).unwrap()
    assert_true(equality.pressure.passed)
    assert_true(!equality.offset_factor.passed)
  }
}

///|
test "sampling comparison equals independent analyses and rejects ambiguous level requests" {
  let p = example_program(Polynomial4567)
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let resolutions = [72, 144, 288]
  let c = compare_sampling(p, g, resolutions, 0.6, 1.0).unwrap()
  assert_eq(c.levels.length(), 3)
  for i = 0; i < resolutions.length(); i = i + 1 {
    let a = analyze(p, g, resolutions[i], 0.6, 1.0).unwrap()
    let l = c.levels[i]
    near(l.pressure.value, a.max_pressure, 0.0)
    near(l.offset_factor.value, a.min_offset_factor, 0.0)
    assert_eq(l.sample_count, a.points.length())
    assert_eq(l.state, a.state())
    assert_eq(l.pressure.location.sample_index, Some(a.pressure_sample_index))
  }
  near(
    c.pressure_change,
    (c.levels[2].pressure.value - c.levels[1].pressure.value).abs(),
    0.0,
  )
  for
    invalid in [
      [],
      [72],
      [72, 72],
      [144, 72],
      [35, 72],
      [72, 20001],
      [36, 72, 144, 288, 576],
    ] {
    assert_true(compare_sampling(p, g, invalid, 0.6, 1.0) is Err(_))
  }
  for resolution in [36, 720, 1000, 1001, 1440, 4000] {
    let levels = comparison_resolutions(resolution)
    assert_eq(levels.length(), 3)
    assert_true(levels.contains(resolution))
    assert_true(levels[0] >= Resolution_min && levels[2] <= Json_resolution_max)
    assert_true(levels[0] < levels[1] && levels[1] < levels[2])
  }
}

///|
test "comparison cannot turn incomplete or rejected sampled levels into acceptance" {
  let p = example_program(Polynomial4567)
  let c = compare_sampling(
    p,
    { base_radius: 5.0, roller_radius: 4.0, offset: 0.0, },
    [72, 144, 288],
    @math.PI / 6.0,
    1.0,
  ).unwrap()
  assert_true(c.state_consistent)
  assert_true(c.levels.all(fn(l) { l.state == "rejected" }))
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let coarse = analyze(p, g, 72, 0.6, 1.0).unwrap()
  let fine = analyze(p, g, 288, 0.6, 1.0).unwrap()
  assert_true(fine.max_pressure > coarse.max_pressure)
  let boundary = (coarse.max_pressure + fine.max_pressure) / 2.0
  let sensitive = compare_sampling(p, g, [72, 144, 288], boundary, 1.0).unwrap()
  assert_true(!sensitive.state_consistent)
  assert_eq(sensitive.levels[0].state, "accepted_sampled")
  assert_eq(sensitive.levels[2].state, "rejected")
}
