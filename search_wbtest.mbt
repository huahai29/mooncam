///|
test "size search returns independently rechecked bounded candidate" {
  let p = example_program(Polynomial4567)
  let r = search_base(p, 4.0, 0.0, 5.0, 100.0, 95, 180, @math.PI / 6.0, 1.0).unwrap()
  assert_true(r.geometry.base_radius >= 5.0 && r.geometry.base_radius <= 100.0)
  near(r.grid_step, 1.0, 1.0e-12)
  assert_true(
    analyze(p, r.geometry, 1440, @math.PI / 6.0, 1.0).unwrap().sampled_feasible,
  )
  assert_true(search_base(p, 4.0, 0.0, 1.0, 2.0, 4, 180, 0.01, 1.0) is Err(_))
}

///|
test "invalid search bounds cannot imply success" {
  let p = example_program(Cycloidal)
  assert_true(search_base(p, 4.0, 0.0, 10.0, 1.0, 10, 180, 0.5, 1.0) is Err(_))
  assert_true(search_base(p, 4.0, 0.0, 1.0, 100.0, 0, 180, 0.5, 1.0) is Err(_))
}
