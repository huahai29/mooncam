///|
fn near(a : Double, b : Double, tolerance : Double) -> Unit raise {
  assert_true((a - b).abs() <= tolerance)
}

///|
test "normalized endpoints and symmetry" {
  for law in [Cycloidal, Polynomial345, Polynomial4567] {
    let start = normalized(law, 0.0).unwrap()
    let end = normalized(law, 1.0).unwrap()
    near(start.s, 0.0, 1.0e-12)
    near(end.s, 1.0, 1.0e-12)
    near(start.v, 0.0, 1.0e-12)
    near(end.a, 0.0, 1.0e-10)
    near(normalized(law, 0.5).unwrap().s, 0.5, 1.0e-12)
  }
}

///|
test "analytic derivatives match independent central differences" {
  let h = 1.0e-5
  for law in [Cycloidal, Polynomial345, Polynomial4567] {
    for u in [0.1, 0.3, 0.6, 0.9] {
      let left = normalized(law, u - h).unwrap()
      let mid = normalized(law, u).unwrap()
      let right = normalized(law, u + h).unwrap()
      near((right.s - left.s) / (2.0 * h), mid.v, 1.0e-7)
      near((right.v - left.v) / (2.0 * h), mid.a, 1.0e-6)
      near((right.a - left.a) / (2.0 * h), mid.j, 1.0e-5)
    }
  }
}

///|
test "invalid phases are rejected" {
  assert_true(normalized(Cycloidal, -0.1) is Err(_))
  assert_true(normalized(Cycloidal, 1.1) is Err(_))
  assert_true(normalized(Cycloidal, 0.0 / 0.0) is Err(_))
}
