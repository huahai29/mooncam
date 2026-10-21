///|
test "JSON boundary rejects malformed and unknown inputs without panic" {
  for input in ["{", "null", "{}", "{\"action\":\"analyze\",\"unexpected\":1}"] {
    let result = @json.parse(run_json(input))
    guard result is Object(fields) else { fail("expected error object") }
    assert_eq(fields.get("ok"), Some(Json(false)))
  }
}
