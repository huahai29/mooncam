///|
test "JSON boundary rejects malformed and unknown inputs without panic" {
  for input in ["{", "null", "{}", "{\"action\":\"analyze\",\"unexpected\":1}"] {
    let result = @json.parse(run_json(input))
    guard result is Object(fields) else { fail("expected error object") }
    assert_eq(fields.get("ok"), Some(Json(false)))
  }
}

///|
test "segment validation shares decoder, totals and row field locations" {
  let valid = "[{\"angle_deg\":180,\"lift_mm\":20,\"law\":\"345\"},{\"angle_deg\":180,\"lift_mm\":-20,\"law\":\"cycloidal\"}]"
  guard @json.parse(validate_segments_json(valid)) is Object(fields) else {
    fail("object")
  }
  assert_eq(fields.get("ok"), Some(Json(true)))
  assert_eq(fields.get("total_angle_deg"), Some(Json(360)))
  assert_eq(fields.get("total_lift_mm"), Some(Json(0)))
  let invalid = "[{\"angle_deg\":360,\"lift_mm\":-1,\"law\":\"4567\"}]"
  guard @json.parse(validate_segments_json(invalid)) is Object(error) else {
    fail("object")
  }
  assert_eq(error.get("ok"), Some(Json(false)))
  assert_eq(error.get("field"), Some(Json("segments[0].lift_mm")))
  assert_eq(error.get("total_lift_mm"), Some(Json(-1)))
}

///|
test "segment validation rejects malformed, oversized and unclosed arrays" {
  for
    input in [
      "{", "null", "[]", "[{\"angle_deg\":90,\"lift_mm\":0,\"law\":\"345\"}]", "[{\"angle_deg\":360,\"lift_mm\":0,\"law\":\"invalid\"}]",
      "[{\"angle_deg\":null,\"lift_mm\":0,\"law\":\"345\"}]",
    ] {
    guard @json.parse(validate_segments_json(input)) is Object(fields) else {
      fail("object")
    }
    assert_eq(fields.get("ok"), Some(Json(false)))
  }
  guard @json.parse(validate_segments_json(" ".repeat(Input_bytes_max + 1)))
    is Object(fields) else {
    fail("object")
  }
  assert_eq(fields.get("error_code"), Some(Json("input_too_large")))
}

///|
fn api_test_request(patch : Map[String, Json]) -> String {
  let fields : Map[String, Json] = {
    "action": "analyze",
    "units": "mm",
    "base_radius_mm": 40,
    "roller_radius_mm": 4,
    "offset_mm": 0,
    "rpm": 60,
    "resolution": 72,
    "pressure_limit_deg": 30,
    "segments": [
      { "angle_deg": Json(360), "lift_mm": Json(0), "law": Json("4567") },
    ],
    "outputs": [],
  }
  for key, value in patch {
    fields.set(key, value)
  }
  Json(fields).stringify()
}

///|
fn api_test_fields(text : String) -> Map[String, Json] raise {
  guard @json.parse(text) is Object(fields) else { fail("expected object") }
  fields
}

///|
test "API invalid scalar fields retain exact field paths" {
  let cases : Array[(String, Json)] = [
    ("units", Json("inch")),
    ("units", Json(1)),
    ("action", Json("unknown")),
    ("resolution", Json(72.5)),
    ("rpm", Json(0)),
    ("rpm", Json("fast")),
    ("roller_radius_mm", Json(0)),
    ("roller_radius_mm", Json(1000001)),
    ("base_radius_mm", Json(0)),
    ("base_radius_mm", Json(1000001)),
    ("offset_mm", Json(44)),
    ("pressure_limit_deg", Json(90)),
    ("include_input", Json(1)),
    ("compare_sampling", Json("yes")),
  ]
  for (key, value) in cases {
    let patch : Map[String, Json] = Map([])
    patch.set(key, value)
    let fields = api_test_fields(run_json(api_test_request(patch)))
    assert_eq(fields.get("ok"), Some(Json(false)))
    assert_eq(fields.get("error_code"), Some(Json("invalid_input")))
    assert_eq(fields.get("field"), Some(Json(key)))
  }
}

///|
test "numeric decoder refuses nonfinite Json values before conversion" {
  for n in [1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0] {
    try {
      ignore(num({ "rpm": Json(n) }, "rpm"))
      fail("expected nonfinite rejection")
    } catch {
      FieldError(field, _) => assert_eq(field, "rpm")
      _ => fail("wrong error type")
    }
  }
}

///|
test "located prefixes input errors but preserves foreign typed errors" {
  try {
    located("search", fn() raise { raise InputError("bad bounds") })
    fail("expected input error")
  } catch {
    FieldError(field, message) => {
      assert_eq(field, "search")
      assert_eq(message, "bad bounds")
    }
    _ => fail("wrong error type")
  }
  try {
    located("search", fn() raise {
      raise RequestError(CalculationFailed, "overflow")
    })
    fail("expected calculation error")
  } catch {
    RequestError(code, message) => {
      assert_true(code is CalculationFailed)
      assert_eq(message, "overflow")
    }
    _ => fail("foreign error was rewritten")
  }
}

///|
test "search errors preserve classification without treating failure as no candidate" {
  let errors : Array[SearchError] = [
    InvalidInput("bounds"),
    IndeterminateGeometry("touching"),
    NumericalFailure("overflow"),
    NoCandidate(2),
  ]
  let expected = [
    "invalid_input", "check_indeterminate", "calculation_failed", "no_candidate",
  ]
  for i = 0; i < errors.length(); i = i + 1 {
    let code = try {
      ignore(checked_search(Err(errors[i])))
      "unexpected_success"
    } catch {
      InputError(_) => "invalid_input"
      RequestError(code, _) => code.code()
      _ => "unexpected_error"
    }
    assert_eq(code, expected[i])
  }
}

///|
test "session exports requested formats and clears cached success after invalid requests" {
  let s = session()
  assert_eq(
    api_test_fields(s.export_profile("csv")).get("error_code"),
    Some(Json("no_result")),
  )
  let response = api_test_fields(
    s.run(
      api_test_request({
        "outputs": ["points", "csv", "svg", "dxf"],
        "include_input": true,
        "compare_sampling": true,
      }),
    ),
  )
  assert_eq(response.get("ok"), Some(Json(true)))
  assert_true(response.contains("input"))
  guard response.get("result") is Some(Object(result)) else { fail("result") }
  assert_true(result.contains("sampling_comparison"))
  for format in ["csv", "svg", "dxf"] {
    assert_eq(
      api_test_fields(s.export_profile(format)).get("content"),
      result.get(format),
    )
  }
  assert_eq(
    api_test_fields(s.export_profile("bad")).get("error_code"),
    Some(Json("invalid_input")),
  )
  ignore(s.run(" ".repeat(Input_bytes_max + 1)))
  assert_eq(
    api_test_fields(s.export_profile("csv")).get("error_code"),
    Some(Json("no_result")),
  )
  ignore(s.run(api_test_request({})))
  ignore(s.run(api_test_request({ "rpm": 0 })))
  assert_eq(
    api_test_fields(s.export_profile("csv")).get("error_code"),
    Some(Json("no_result")),
  )
}

///|
test "search JSON validates nested bounds and distinguishes empty grids" {
  for
    (key, value) in [
      ("lower_mm", Json(0)),
      ("upper_mm", Json(30)),
      ("intervals", Json(0)),
    ] {
    let search : Map[String, Json] = {
      "lower_mm": 40,
      "upper_mm": 40,
      "intervals": 1,
    }
    search.set(key, value)
    let result = api_test_fields(
      run_json(api_test_request({ "action": "search", "search": Json(search) })),
    )
    assert_eq(result.get("field"), Some(Json("search." + key)))
  }
  let request : Map[String, Json] = {
    "action": "search",
    "search": { "lower_mm": 40, "upper_mm": 40, "intervals": 1 },
  }
  assert_eq(
    api_test_fields(run_json(api_test_request(request))).get("ok"),
    Some(Json(true)),
  )
  request.set("resolution", Json(Search_resolution_max + 1))
  assert_eq(
    api_test_fields(run_json(api_test_request(request))).get("field"),
    Some(Json("resolution")),
  )
  request.set("resolution", Json(72))
  request.set("offset_mm", Json(44))
  assert_eq(
    api_test_fields(run_json(api_test_request(request))).get("field"),
    Some(Json("offset_mm")),
  )
  request.set("offset_mm", Json(0))
  request.set(
    "segments",
    Json([
      { "angle_deg": Json(180), "lift_mm": Json(20), "law": Json("4567") },
      { "angle_deg": Json(180), "lift_mm": Json(-20), "law": Json("4567") },
    ]),
  )
  request.set("pressure_limit_deg", Json(0.01))
  assert_eq(
    api_test_fields(run_json(api_test_request(request))).get("error_code"),
    Some(Json("no_candidate")),
  )
}

///|
test "output selection rejects wrong types and duplicates with no stale exports" {
  for outputs in [Json(1), Json([1]), Json(["bad"]), Json(["csv", "csv"])] {
    let result = api_test_fields(
      run_json(api_test_request({ "outputs": outputs })),
    )
    assert_eq(result.get("error_code"), Some(Json("invalid_input")))
    assert_eq(result.get("field"), Some(Json("outputs")))
  }
}

///|
test "segment JSON validation covers object shape magnitude and angle boundaries" {
  let segments : Array[Json] = [
    Json([1]),
    Json([{ "angle_deg": Json(360), "lift_mm": Json(0), "law": Json(1) }]),
    Json([
      { "angle_deg": Json(360), "lift_mm": Json(1000001), "law": Json("345") },
    ]),
    Json([{ "angle_deg": Json(0), "lift_mm": Json(0), "law": Json("345") }]),
    Json([{ "angle_deg": Json("bad"), "lift_mm": Json(0), "law": Json("345") }]),
    Json([
      { "angle_deg": Json(360), "lift_mm": Json("bad"), "law": Json("345") },
    ]),
    Json([
      {
        "angle_deg": Json(360),
        "lift_mm": Json(0),
        "law": Json("345"),
        "extra": Json(1),
      },
    ]),
    Json(
      Array::make(
        Segments_max + 1,
        Json({ "angle_deg": Json(360), "lift_mm": Json(0), "law": Json("345") }),
      ),
    ),
  ]
  for items in segments {
    assert_eq(
      api_test_fields(validate_segments_json(items.stringify())).get("ok"),
      Some(Json(false)),
    )
  }
  assert_eq(
    api_test_fields(run_json(api_test_request({ "segments": Json(null) }))).get(
      "field",
    ),
    Some(Json("segments")),
  )
}

///|
test "finite input overflow is calculation failure and invalidates session" {
  let s = session()
  ignore(s.run(api_test_request({})))
  let result = api_test_fields(
    s.run(
      api_test_request({
        "rpm": 1.0e120,
        "segments": [
          { "angle_deg": 180, "lift_mm": 20, "law": "4567" },
          { "angle_deg": 180, "lift_mm": -20, "law": "4567" },
        ],
      }),
    ),
  )
  assert_eq(result.get("error_code"), Some(Json("calculation_failed")))
  assert_eq(result.get("field"), Some(Json(null)))
  assert_eq(
    api_test_fields(s.export_profile("csv")).get("error_code"),
    Some(Json("no_result")),
  )
}

///|
test "topology JSON preserves uncertainty and failure rather than claiming zero crossings" {
  let p = example_program(Polynomial4567)
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  let a = analyze(p, g, 72, 0.6, 1.0).unwrap()
  let d = diagnose(p, a, 0.6).unwrap()
  let cases : Array[(CrossingCheck, String)] = [
    (NotChecked, "geometry_not_checked"),
    (Failed("budget"), "geometry_failed"),
    (Indeterminate(1, 2), "geometry_indeterminate"),
  ]
  for (check, reason) in cases {
    let changed = { ..a, crossings: check, }
    assert_true(reason_codes(changed, d).contains(reason))
    guard crossing_json(check) is Object(fields) else { fail("object") }
    assert_eq(fields.get("count"), Some(Json(null)))
    assert_true(changed.state() == "incomplete")
  }
  assert_true(
    reason_codes({ ..a, crossings: Indeterminate(1, 2), }, d).contains(
      "profile_crossings",
    ),
  )
}
