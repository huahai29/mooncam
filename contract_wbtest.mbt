///|
test "typed error categories map to stable wire codes and host exits" {
  for item in error_codes() {
    let text = error_json(item, "acceptance fixture")
    guard @json.parse(text) is Object(fields) else {
      fail("expected error object")
    }
    assert_eq(fields.get("error_code"), Some(Json(item.code())))
    assert_eq(fields.get("schema_version"), Some(Json(Schema_version)))
    assert_eq(error_exit_code(item.code()), item.exit_code())
  }
  assert_eq(error_exit_code("unknown_future_error"), 1)
  assert_eq(result_exit_code("accepted_sampled"), 0)
  assert_eq(result_exit_code("rejected"), 2)
  assert_eq(result_exit_code("incomplete"), 4)
  assert_eq(result_exit_code("unknown_future_state"), 1)
  try {
    ignore(checked_search(Err(IndeterminateGeometry("fixture"))))
    fail("expected typed indeterminate error")
  } catch {
    RequestError(code, _) => assert_true(code is CheckIndeterminate)
    _ => fail("wrong error category")
  }
}

///|
test "library resolution limits use the same published contract" {
  let p = example_program(Polynomial4567)
  let g : Geometry = { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, }
  assert_true(sample(p, g, Resolution_min - 1) is Err(_))
  assert_true(sample(p, g, Library_resolution_max + 1) is Err(_))
  assert_true(measure(p, g, Library_resolution_max, 0.6, 1.0) is Ok(_))
  assert_true(analyze(p, g, Library_resolution_max, 0.6, 1.0) is Ok(_))
  assert_true(
    search_base(p, 4.0, 0.0, 40.0, 40.0, 1, Search_resolution_max + 1, 0.6, 1.0)
    is Err(InvalidInput(_)),
  )
  assert_eq(Search_resolution_max * Search_refinement, Json_resolution_max)
}
