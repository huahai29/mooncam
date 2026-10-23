///|
priv struct GeometryCase {
  id : String
  coords : Array[(Double, Double)]
  status : String
  count : Int32
}

///|
/// Fixed, named release acceptance fixtures, independent of generated cam shapes.
test "G01-G12 fixed geometry acceptance matrix" {
  let cases : Array[GeometryCase] = [
    {
      id: "G01 simple square",
      coords: [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)],
      status: "complete",
      count: 0,
    },
    {
      id: "G02 proper crossing",
      coords: [(0.0, 0.0), (1.0, 1.0), (0.0, 1.0), (1.0, 0.0), (0.0, 0.0)],
      status: "complete",
      count: 1,
    },
    {
      id: "G03 nonadjacent endpoint touch",
      coords: [
        (0.0, 0.0),
        (2.0, 0.0),
        (2.0, 2.0),
        (1.0, 0.0),
        (0.0, 2.0),
        (0.0, 0.0),
      ],
      status: "indeterminate",
      count: 0,
    },
    {
      id: "G04 overlap",
      coords: [(0.0, 0.0), (2.0, 0.0), (1.0, 0.0), (1.0, 2.0), (0.0, 0.0)],
      status: "indeterminate",
      count: 0,
    },
    {
      id: "G05 near-collinear crossing",
      coords: [
        (0.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0e-16),
        (1.0, 1.0 - 1.0e-16),
        (0.0, 0.0),
      ],
      status: "indeterminate",
      count: 0,
    },
    {
      id: "G06 adjacent reversal",
      coords: [(0.0, 0.0), (2.0, 0.0), (1.0, 0.0), (0.0, 0.0)],
      status: "indeterminate",
      count: 0,
    },
    {
      id: "G07 zero edge",
      coords: [(0.0, 0.0), (1.0, 0.0), (1.0, 0.0), (0.0, 1.0), (0.0, 0.0)],
      status: "failed",
      count: 0,
    },
    {
      id: "G08 collapsed",
      coords: [(0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0)],
      status: "failed",
      count: 0,
    },
    {
      id: "G09 open profile",
      coords: [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.1)],
      status: "failed",
      count: 0,
    },
    {
      id: "G10 collinear forward edges",
      coords: [
        (0.0, 0.0),
        (0.5, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
        (0.0, 0.0),
      ],
      status: "complete",
      count: 0,
    },
    {
      id: "G11 closure within tolerance",
      coords: [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 1.0e-12)],
      status: "complete",
      count: 0,
    },
    {
      id: "G12 unrepresentable translated detail",
      coords: [
        (1.0e16, 1.0e16),
        (1.0e16 + 1.0, 1.0e16),
        (1.0e16 + 1.0, 1.0e16 + 1.0),
        (1.0e16, 1.0e16),
      ],
      status: "failed",
      count: 0,
    },
  ]
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let metrics = {
    ..measure(example_program(Cycloidal), g, 72, 0.6, 1.0).unwrap(),
    pressure_sample_index: 0,
    offset_factor_sample_index: 0,
  }
  for case in cases {
    let a = finish_scan({ metrics, points: polygon(case.coords), })
    if a.crossings.status() != case.status {
      fail(case.id + ": wrong topology state")
    }
    if a.crossings is Checked(n) {
      assert_eq(n, case.count)
    }
    let accepted = case.status == "complete" && case.count == 0
    assert_eq(a.sampled_feasible, accepted)
    assert_eq(
      a.state(),
      if accepted {
        "accepted_sampled"
      } else if case.status == "complete" {
        "rejected"
      } else {
        "incomplete"
      },
    )
    guard report(a, g, 1.0, [], example_program(Cycloidal), 0.6)
      is Object(fields) else {
      fail(case.id)
    }
    assert_eq(fields.get("state"), Some(Json(a.state())))
    guard fields.get("crossing_check") is Some(Object(check)) else {
      fail(case.id)
    }
    assert_eq(check.get("status"), Some(Json(case.status)))
    if case.status != "complete" {
      assert_eq(check.get("count"), Some(Json(null)))
    }
  }
}

///|
test "G13 closure rejects tiny and translated open profiles for topology and export" {
  for scale in [1.0e-100, 1.0e-7, 1.0, 1.0e100] {
    let points = polygon([
      (0.0, 0.0),
      (1.0, 0.0),
      (1.0, 1.0),
      (0.0, 1.0),
      (0.0, 0.1),
    ]).map(fn(p) { { ..p, x: p.x * scale, y: p.y * scale, } })
    assert_true(
      crossing_report(points) is Err("profile polyline must be closed"),
    )
    for format in ["csv", "svg", "dxf"] {
      assert_true(
        checked_export(points, format) is Err("export polyline must be closed"),
      )
    }
  }
  let shifted = polygon([
    (0.0, 0.0),
    (1.0, 0.0),
    (1.0, 1.0),
    (0.0, 1.0),
    (0.0, 0.125),
  ]).map(fn(p) { { ..p, x: p.x + 1.0e15, y: p.y + 1.0e15, } })
  assert_true(
    crossing_report(shifted) is Err("profile polyline must be closed"),
  )
  assert_true(checked_export(shifted, "dxf") is Err(_))
}

///|
test "G14 subnormal orientation products are uncertain" {
  assert_eq(orientation(0.0, 0.0, 1.0e150, 0.0, 1.0e150, 1.0e-170), 0)
  assert_eq(orientation(0.0, 0.0, 1.0, 0.0, 1.0, 1.0e-100), 1)
}

///|
test "G15 all incomplete states and local rejection fail closed" {
  for
    check in [
      NotChecked,
      Failed("budget"),
      Indeterminate(0, 1),
      Indeterminate(2, 1),
      Checked(1),
    ] {
    assert_true(!sampled_acceptance(true, check))
    assert_true(!sampled_acceptance(false, check))
  }
  assert_true(!sampled_acceptance(false, Checked(0)))
  assert_true(sampled_acceptance(true, Checked(0)))
}

///|
test "G16 invalid coordinates and actual point bounds cannot pass topology or export" {
  let points = polygon([
    (0.0, 0.0),
    (1.0, 0.0),
    (1.0, 1.0),
    (0.0, 1.0),
    (0.0, 0.0),
  ])
  // Deliberately construct invalid floating-point values at the input boundary.
  for bad in [1.0 / 0.0, 0.0 / 0.0, Coordinate_max * 2.0] {
    let invalid = points.map(fn(p) { { ..p, x: bad, } })
    assert_true(crossing_report(invalid) is Err(_))
    assert_true(checked_export(invalid, "svg") is Err(_))
  }
  let excessive = Array::make(Profile_points_max + 1, points[0])
  for invalid in [[], [points[0], points[1], points[0]], excessive] {
    assert_true(crossing_report(invalid) is Err(_))
    assert_true(checked_export(invalid, "dxf") is Err(_))
  }
}
