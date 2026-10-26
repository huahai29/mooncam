///|
/// Deterministic topology work budget, independent of runner wall-clock speed.
test "performance guard high resolution topology stays below quadratic work" {
  let p = example_program(Polynomial4567)
  let seed = contact(
    p,
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    0.0,
  ).unwrap()
  for n in [4000, 20000] {
    for vertical in [false, true] {
      let points : Array[CamPoint] = []
      for i = 0; i < n; i = i + 1 {
        let theta = 2.0 * @math.PI * i.to_double() / n.to_double()
        let x = @math.cos(theta)
        let y = @math.sin(theta)
        points.push({ ..seed, x: if vertical { x * 0.000001 } else { x }, y, })
      }
      points.push(points[0])
      let report = crossing_report(points).unwrap()
      assert_eq(report.crossings, 0)
      assert_eq(report.uncertain_pairs, 0)
      // Current broad-phase is far below this linear envelope on these shapes.
      // A quadratic all-pairs regression exceeds it at both resolutions.
      assert_true(report.pair_visits < n * 100)
    }
  }
}

///|
test "performance guard 128 segments metrics scan retains no coordinates" {
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
  let mesh = motion_mesh(p, 4000).unwrap()
  assert_true(mesh.samples.length() >= 4001)
  assert_true(mesh.samples.length() <= 4129)
  let scan = scan_mesh(
    mesh,
    { base_radius: 200.0, roller_radius: 4.0, offset: 0.0, },
    0.6,
    1.0,
    false,
  ).unwrap()
  assert_eq(scan.points.length(), 0)
  assert_eq(scan.metrics.sample_count, mesh.samples.length())
  let found = search_base(
    example_program(Polynomial4567),
    4.0,
    0.0,
    5.0,
    100.0,
    95,
    360,
    @math.PI / 6.0,
    2.0 * @math.PI,
  ).unwrap()
  assert_eq(found.tested, 32)
  assert_eq(found.analysis.points.length(), 721)
  assert_eq(found.verification_resolution, 720)
}
