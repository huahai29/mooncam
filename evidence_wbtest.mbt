///|
test "G17 topology witnesses identify actual edge pairs without intersection coordinates" {
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
test "G18 bounded evidence retains full counts after truncation and indices remain valid" {
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
    for index in [w.edge_a, w.edge_b] {
      assert_true(
        locate_edge(example_program(Polynomial4567), points, index) is Ok(_),
      )
    }
  }
}

///|
test "G19 uncertain evidence is located in JSON without claiming exact intersection points" {
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

///|
test "report edge encoder preserves invalid index and angle causes without panic" {
  let p = example_program(Polynomial4567)
  let points = sample(
    p,
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    72,
  ).unwrap()
  for index in [-1, points.length() - 1, points.length()] {
    let response = edge_json(p, points, index).stringify() catch {
      RequestError(code, message) => error_json(code, message)
    }
    guard @json.parse(response) is Object(fields) else { fail("error object") }
    assert_eq(fields.get("ok"), Some(Json(false)))
    assert_eq(fields.get("error_code"), Some(Json("internal_error")))
    guard fields.get("error") is Some(String(message)) else { fail("message") }
    assert_true(message.contains("edge index out of range"))
    assert_true(message.contains(index.to_string()))
  }
  let invalid = points.map(fn(point) { { ..point, theta: -1.0, } })
  let response = edge_json(p, invalid, 0).stringify() catch {
    RequestError(code, message) => error_json(code, message)
  }
  guard @json.parse(response) is Object(fields) else { fail("error object") }
  assert_eq(fields.get("error_code"), Some(Json("internal_error")))
  guard fields.get("error") is Some(String(message)) else { fail("message") }
  assert_true(message.contains("cannot encode profile edge 0"))
  assert_true(message.contains("location angle must be in [0, 2pi]"))
}

///|
test "report rejects inconsistent diagnostics and witnesses through typed errors" {
  let p = example_program(Polynomial4567)
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let a = analyze(p, g, 72, 0.6, 1.0).unwrap()
  let broken = [
    { ..a, pressure_sample_index: a.points.length(), },
    {
      ..a,
      crossing_witnesses: [
        { kind: "proper_crossing", edge_a: 0, edge_b: a.points.length(), },
      ],
    },
  ]
  for i = 0; i < broken.length(); i = i + 1 {
    let response = report(broken[i], g, 1.0, [], p, 0.6).stringify() catch {
      RequestError(code, message) => error_json(code, message)
    }
    guard @json.parse(response) is Object(fields) else { fail("error object") }
    assert_eq(fields.get("error_code"), Some(Json("internal_error")))
    guard fields.get("error") is Some(String(message)) else { fail("message") }
    assert_true(
      message.contains(
        if i == 0 {
          "sample index out of range"
        } else {
          "edge index out of range"
        },
      ),
    )
  }
}

///|
test "count convenience API agrees with detailed reports and never hides uncertainty" {
  let square = polygon([
    (0.0, 0.0),
    (1.0, 0.0),
    (1.0, 1.0),
    (0.0, 1.0),
    (0.0, 0.0),
  ])
  let uncertain = polygon([
    (0.0, 0.0),
    (2.0, 0.0),
    (1.0, 0.0),
    (1.0, 2.0),
    (0.0, 0.0),
  ])
  assert_eq(
    profile_crossings(square),
    Ok(crossing_report(square).unwrap().crossings),
  )
  assert_true(crossing_report(uncertain).unwrap().uncertain_pairs > 0)
  assert_true(profile_crossings(uncertain) is Err(_))
  assert_true(crossing_report([]) is Err(_))
  assert_true(profile_crossings([]) is Err(_))
}
