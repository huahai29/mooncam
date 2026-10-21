///|
test "closed motion wraps angles and scales time derivatives" {
  let p = example_program(Polynomial4567)
  let m = evaluate(p, @math.PI / 4.0).unwrap()
  near(m.s, 10.0, 1.0e-10)
  near(evaluate(p, @math.PI * 2.25).unwrap().s, 10.0, 1.0e-10)
  near(evaluate(p, -@math.PI / 2.0).unwrap().s, 0.0, 1.0e-10)
  let t = timed(p, @math.PI / 4.0, 2.0).unwrap()
  near(t.v, m.v * 2.0, 1.0e-10)
  near(t.j, m.j * 8.0, 1.0e-10)
}

///|
test "invalid cycles cannot become programs" {
  assert_true(program([]) is Err(_))
  assert_true(
    program([{ angle: 2.0 * @math.PI, lift: 1.0, law: Cycloidal, }]) is Err(_),
  )
  assert_true(program([{ angle: 1.0, lift: 0.0, law: Cycloidal, }]) is Err(_))
  assert_true(
    program([
      { angle: @math.PI, lift: -1.0, law: Cycloidal, },
      { angle: @math.PI, lift: 1.0, law: Cycloidal, },
    ])
    is Err(_),
  )
  assert_true(timed(example_program(Cycloidal), 0.0, 0.0) is Err(_))
}
