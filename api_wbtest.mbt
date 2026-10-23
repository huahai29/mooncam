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
