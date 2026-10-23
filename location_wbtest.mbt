///|
test "location queries share right-side segment boundaries and closure convention" {
  let p = program([
    { angle: 0.3, lift: 2.0, law: Polynomial345, },
    { angle: 1.1, lift: -2.0, law: Cycloidal, },
    { angle: 2.0 * @math.PI - 1.4, lift: 0.0, law: Polynomial4567, },
  ]).unwrap()
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let points = sample(p, g, 73).unwrap()
  assert_eq(locate_angle(p, 0.3).unwrap().segment_index, 1)
  assert_eq(locate_angle(p, 0.3).unwrap().law, "cycloidal")
  assert_eq(locate_angle(p, 0.3).unwrap().sample_index, None)
  assert_eq(locate_angle(p, 0.3 - 1.0e-12).unwrap().segment_index, 0)
  for i = 0; i < points.length(); i = i + 1 {
    let l = locate_sample(p, points, i).unwrap()
    assert_eq(l.sample_index, Some(i))
    near(l.theta_rad, points[i].theta, 0.0)
    let expected = segment_motion(
      p.segments[l.segment_index],
      p.heights[l.segment_index],
      if l.periodic_endpoint {
        0.0
      } else {
        (l.theta_rad - l.segment_start_rad) /
        (l.segment_end_rad - l.segment_start_rad)
      },
    ).unwrap()
    near(evaluate(p, points[i].theta).unwrap().s, expected.s, 1.0e-10)
  }
  let last = locate_sample(p, points, points.length() - 1).unwrap()
  assert_true(last.periodic_endpoint)
  assert_eq(last.segment_index, 0)
  near(last.theta_rad, 2.0 * @math.PI, 0.0)
  let edge = locate_edge(p, points, points.length() - 2).unwrap()
  assert_eq(edge.segment_index, 2)
  assert_eq(edge.end.segment_index, 0)
  assert_true(edge.end.periodic_endpoint)
  for angle in [-0.01, 2.0 * @math.PI + 0.01, 0.0 / 0.0] {
    assert_true(locate_angle(p, angle) is Err(_))
  }
  for index in [-1, points.length()] {
    assert_true(locate_sample(p, points, index) is Err(_))
  }
  for index in [-1, points.length() - 1] {
    assert_true(locate_edge(p, points, index) is Err(_))
  }
}

///|
test "all segment boundary samples and outgoing edges use the same segment ID" {
  let p = example_program(Polynomial4567)
  let points = sample(
    p,
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    720,
  ).unwrap()
  for k = 0; k < 4; k = k + 1 {
    let l = locate_sample(p, points, k * 180).unwrap()
    assert_eq(l.segment_index, k)
    assert_eq(locate_edge(p, points, k * 180).unwrap().segment_index, k)
    near(l.segment_start_rad, p.starts[k], 0.0)
  }
}
