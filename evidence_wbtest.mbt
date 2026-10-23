///|
test "topology witnesses identify actual edge pairs without intersection coordinates" {
  let points = polygon([
    (0.0, 0.0),
    (2.0, 2.0),
    (0.0, 2.0),
    (2.0, 0.0),
    (0.0, 0.0),
  ])
  let r = crossing_report(points).unwrap()
  assert_eq(r.crossings, 1)
  assert_eq(r.witnesses.length(), 1)
  assert_eq(r.witnesses[0].kind, "proper_crossing")
  assert_eq(r.witnesses[0].edge_a, 0)
  assert_eq(r.witnesses[0].edge_b, 2)
  assert_true(!r.witnesses_truncated)
  let uncertain = crossing_report(
    polygon([(0.0, 0.0), (2.0, 0.0), (1.0, 0.0), (1.0, 2.0), (0.0, 0.0)]),
  ).unwrap()
  assert_true(uncertain.uncertain_pairs > 0)
  assert_true(uncertain.witnesses.any(fn(w) { w.kind == "adjacent_reversal" }))
}

///|
test "bounded evidence retains full counts after truncation and indices remain valid" {
  let points : Array[CamPoint] = []
  let seed = polygon([(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (0.0, 0.0)])[0]
  let n = 71
  for i = 0; i < n; i = i + 1 {
    let t = (i * 31 % n).to_double() / n.to_double() * 2.0 * @math.PI
    points.push({
      ..seed,
      x: @math.cos(t),
      y: @math.sin(t),
      theta: i.to_double() / n.to_double() * 2.0 * @math.PI,
    })
  }
  points.push({ ..points[0], theta: 2.0 * @math.PI, })
  let r = crossing_report(points).unwrap()
  assert_true(r.crossings > Crossing_witnesses_max)
  assert_eq(r.crossings, brute_crossings(points).unwrap())
  assert_eq(r.witnesses.length(), Crossing_witnesses_max)
  assert_true(r.witnesses_truncated)
  for w in r.witnesses {
    assert_true(w.edge_a >= 0 && w.edge_a < n)
    assert_true(w.edge_b >= 0 && w.edge_b < n)
    assert_true(
      locate_edge(example_program(Polynomial4567), points, w.edge_a) is Ok(_),
    )
  }
}

///|
test "uncertain evidence is located in JSON without claiming exact intersection points" {
  let p = example_program(Polynomial4567)
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let points = polygon([
    (0.0, 0.0),
    (2.0, 0.0),
    (1.0, 0.0),
    (1.0, 2.0),
    (0.0, 0.0),
  ]).mapi(fn(i, point) { { ..point, theta: i.to_double() * @math.PI / 2.0, } })
  let original = measure(p, g, 72, 0.6, 1.0).unwrap()
  let metrics = {
    ..original,
    pressure_sample_index: 0,
    offset_factor_sample_index: 0,
  }
  let a = finish_scan({ metrics, points, })
  assert_eq(a.crossings.status(), "indeterminate")
  assert_true(!a.sampled_feasible)
  guard report(a, g, 1.0, [], p, 0.6) is Object(fields) else { fail("report") }
  assert_eq(fields.get("state"), Some(Json("incomplete")))
  guard fields.get("crossing_evidence") is Some(Object(evidence)) else {
    fail("evidence")
  }
  guard evidence.get("witnesses") is Some(Array(witnesses)) else {
    fail("witnesses")
  }
  assert_true(witnesses.length() > 0)
  for witness in witnesses {
    guard witness is Object(w) else { fail("witness") }
    assert_true(w.get("intersection") is None)
    for name in ["edge_a", "edge_b"] {
      guard w.get(name) is Some(Object(edge)) else { fail("edge") }
      guard edge.get("edge_index") is Some(Number(index, ..)) else {
        fail("index")
      }
      let location = locate_edge(p, points, index.to_int()).unwrap()
      assert_eq(edge.get("start"), Some(location_json(location.start)))
      assert_eq(edge.get("end"), Some(location_json(location.end)))
      assert_eq(edge.get("segment_index"), Some(Json(location.segment_index)))
    }
  }
}
