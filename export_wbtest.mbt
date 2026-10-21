///|
test "exports contain closed profile and explicit coordinate conventions" {
  let a = sample(
    example_program(Cycloidal),
    { base_radius: 40.0, roller_radius: 4.0, offset: 0.0, },
    360,
  ).unwrap()
  assert_true(csv(a).starts_with("theta_rad,lift"))
  assert_true(svg(a).contains("<polyline"))
  let d = dxf_mm(a)
  assert_true(d.contains("LWPOLYLINE"))
  assert_true(d.contains("$INSUNITS\n70\n4"))
  assert_true(d.ends_with("0\nEOF\n"))
}
