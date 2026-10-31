///|
/// Randomized property tests for the core library.
///
/// The generator is a fixed-seed xorshift32 stream, so a failure reproduces on
/// every machine and on every backend (js, wasm, wasm-gc, native).  The
/// properties are invariants that must hold for any valid program, not
/// snapshots of particular numbers: periodicity, scale invariance, offset
/// antisymmetry, monotonicity in the base radius, shaft-speed scaling and
/// acceptance monotonicity in the pressure limit.
///
/// These check relationships between results, so they catch defects that a
/// pointwise oracle misses: a wrong branch that is still self-consistent, an
/// offset sign error, or a limit that is compared in the wrong direction.
struct PropertyRng {
  state : Array[UInt32]
}

///|
fn property_rng(seed : UInt32) -> PropertyRng {
  { state: [seed], }
}

///|
fn PropertyRng::next_uint(self : PropertyRng) -> UInt32 {
  let mut x = self.state[0]
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state[0] = x
  x
}

///|
/// Uniform-ish double in [0, 1) from the top 24 bits, avoiding typed literals.
fn PropertyRng::unit(self : PropertyRng) -> Double {
  (self.next_uint() >> 8).to_double() / 16777216.0
}

///|
fn PropertyRng::between(
  self : PropertyRng,
  low : Double,
  high : Double,
) -> Double {
  low + (high - low) * self.unit()
}

///|
fn close_enough(actual : Double, expected : Double, relative : Double) -> Bool {
  (actual - expected).abs() <= relative * expected.abs().max(1.0)
}

///|
fn close_within(actual : Double, expected : Double, absolute : Double) -> Bool {
  (actual - expected).abs() <= absolute
}

///|
fn laws() -> Array[Law] {
  [Cycloidal, Polynomial345, Polynomial4567]
}

///|
/// Alternating rise/fall pairs keep the running lift non-negative and return
/// to zero at one revolution, which is exactly what `program` requires.
fn random_program(rng : PropertyRng, pairs : Int32) -> Program {
  let weights : Array[Double] = []
  let mut total = 0.0
  for i = 0; i < pairs * 2; i = i + 1 {
    let weight = rng.between(0.05, 1.0)
    weights.push(weight)
    total = total + weight
  }
  let segments : Array[Segment] = []
  for pair = 0; pair < pairs; pair = pair + 1 {
    let lift = rng.between(1.0, 20.0)
    let up_law = laws()[(rng.next_uint() >> 30).reinterpret_as_int() % 3]
    let down_law = laws()[(rng.next_uint() >> 30).reinterpret_as_int() % 3]
    segments.push({
      angle: 2.0 * @math.PI * weights[pair * 2] / total,
      lift,
      law: up_law,
    })
    segments.push({
      angle: 2.0 * @math.PI * weights[pair * 2 + 1] / total,
      lift: -lift,
      law: down_law,
    })
  }
  program(segments).unwrap()
}

///|
fn random_geometry(rng : PropertyRng) -> Geometry {
  let base = rng.between(10.0, 200.0)
  let roller = rng.between(1.0, base * 0.3)
  let limit = base + roller
  {
    base_radius: base,
    roller_radius: roller,
    offset: rng.between(-0.6, 0.6) * limit,
  }
}

///|
test "P1 random programs are periodic and repeat exactly" {
  let rng = property_rng(0x20261021U)
  for round = 0; round < 24; round = round + 1 {
    let p = random_program(rng, 1 + round % 4)
    let g = random_geometry(rng)
    for i = 0; i < 6; i = i + 1 {
      let theta = rng.between(0.0, 2.0 * @math.PI)
      let here = evaluate(p, theta).unwrap()
      let next = evaluate(p, theta + 2.0 * @math.PI).unwrap()
      assert_true(
        close_within(here.s, next.s, 1.0e-9),
        msg="lift is not periodic",
      )
      assert_true(
        close_within(here.v, next.v, 1.0e-9),
        msg="velocity is not periodic",
      )
    }
    let first = measure(p, g, 720, @math.PI / 6.0, 2.0 * @math.PI).unwrap()
    let second = measure(p, g, 720, @math.PI / 6.0, 2.0 * @math.PI).unwrap()
    assert_eq(first.max_pressure, second.max_pressure)
    assert_eq(first.min_offset_factor, second.min_offset_factor)
    assert_eq(first.sample_count, second.sample_count)
  }
}

///|
test "P2 uniform scaling scales the profile and leaves angles invariant" {
  let rng = property_rng(0x51a7eU)
  for round = 0; round < 12; round = round + 1 {
    let p = random_program(rng, 1 + round % 3)
    let g = random_geometry(rng)
    let k = [0.25, 0.5, 3.0, 40.0][round % 4]
    let scaled_geometry : Geometry = {
      base_radius: g.base_radius * k,
      roller_radius: g.roller_radius * k,
      offset: g.offset * k,
    }
    let scaled_program = program(
      p.segments.map(fn(segment) { { ..segment, lift: segment.lift * k, } }),
    ).unwrap()
    for i = 0; i < 5; i = i + 1 {
      let theta = rng.between(0.0, 2.0 * @math.PI)
      let base_point = contact(p, g, theta).unwrap()
      let scaled_point = contact(scaled_program, scaled_geometry, theta).unwrap()
      assert_true(
        close_enough(scaled_point.x, base_point.x * k, 1.0e-11),
        msg="contact x does not scale with the length unit",
      )
      assert_true(
        close_enough(scaled_point.y, base_point.y * k, 1.0e-11),
        msg="contact y does not scale with the length unit",
      )
      assert_true(
        close_within(scaled_point.pressure, base_point.pressure, 1.0e-12),
        msg="pressure angle changed under uniform scaling",
      )
      assert_true(
        close_enough(
          scaled_point.offset_factor,
          base_point.offset_factor,
          1.0e-11,
        ),
        msg="offset factor changed under uniform scaling",
      )
      assert_true(
        close_enough(scaled_point.curvature * k, base_point.curvature, 1.0e-10),
        msg="curvature does not scale as 1/length",
      )
    }
  }
}

///|
test "P3 only the prime-circle radius reaches the pressure angle" {
  let rng = property_rng(0x0ff5e7U)
  for round = 0; round < 12; round = round + 1 {
    let p = random_program(rng, 1 + round % 3)
    let base = rng.between(20.0, 150.0)
    let roller = rng.between(3.0, base * 0.25)
    let offset = rng.between(-0.6, 0.6) * (base + roller)
    let reference : Geometry = {
      base_radius: base,
      roller_radius: roller,
      offset,
    }
    // Moving length from the base circle to the roller keeps the prime circle
    // radius r_base + r_roller unchanged, so the pitch curve and the pressure
    // angle must not move; only the contact offset changes.
    let shifted : Array[Geometry] = [
      { base_radius: base - 1.0, roller_radius: roller + 1.0, offset, },
      { base_radius: base + 2.0, roller_radius: roller - 2.0, offset, },
    ]
    for candidate in shifted {
      for i = 0; i < 5; i = i + 1 {
        let theta = rng.between(0.0, 2.0 * @math.PI)
        let a = contact(p, reference, theta).unwrap()
        let b = contact(p, candidate, theta).unwrap()
        assert_true(
          close_within(a.pressure, b.pressure, 1.0e-12),
          msg="pressure angle changed when only the prime-circle split moved",
        )
        assert_true(
          close_enough(a.pitch_x, b.pitch_x, 1.0e-12) &&
          close_enough(a.pitch_y, b.pitch_y, 1.0e-12),
          msg="pitch curve moved when the prime-circle split changed",
        )
        assert_true(
          close_enough(
            @math.hypot(b.pitch_x - b.x, b.pitch_y - b.y),
            candidate.roller_radius,
            1.0e-11,
          ),
          msg="contact point is not one roller radius away from the pitch point",
        )
      }
    }
  }
}

///|
test "P4 a larger base radius never increases the maximum pressure angle" {
  let rng = property_rng(0x9a5e1U)
  for round = 0; round < 16; round = round + 1 {
    let p = random_program(rng, 1 + round % 3)
    let base = rng.between(15.0, 80.0)
    let roller = rng.between(1.0, base * 0.2)
    let offset = rng.between(-0.4, 0.4) * (base + roller)
    let mut previous = 0.0
    let mut first = true
    for step = 0; step < 6; step = step + 1 {
      let g : Geometry = {
        base_radius: base * (1.0 + step.to_double() * 0.35),
        roller_radius: roller,
        offset,
      }
      let value = measure(p, g, 360, @math.PI / 3.0, 2.0 * @math.PI).unwrap().max_pressure
      if !first {
        assert_true(
          value <= previous + 1.0e-12,
          msg="maximum pressure angle increased with the base radius",
        )
      }
      first = false
      previous = value
    }
  }
}

///|
test "P5 shaft speed scales the time derivatives by its power" {
  let rng = property_rng(0x5eedU)
  for round = 0; round < 10; round = round + 1 {
    let p = random_program(rng, 1 + round % 3)
    let g = random_geometry(rng)
    let slow = measure(p, g, 240, @math.PI / 6.0, 1.0).unwrap()
    let fast = measure(p, g, 240, @math.PI / 6.0, 4.0).unwrap()
    assert_true(
      close_enough(fast.max_velocity, slow.max_velocity * 4.0, 1.0e-12),
    )
    assert_true(
      close_enough(fast.max_acceleration, slow.max_acceleration * 16.0, 1.0e-11),
    )
    assert_true(close_enough(fast.max_jerk, slow.max_jerk * 64.0, 1.0e-10))
    assert_true(close_within(fast.max_pressure, slow.max_pressure, 1.0e-15))
    assert_true(
      close_enough(fast.min_offset_factor, slow.min_offset_factor, 1.0e-15),
    )
  }
}

///|
test "P6 raising the pressure limit can only widen acceptance" {
  let rng = property_rng(0x11a17U)
  for round = 0; round < 16; round = round + 1 {
    let p = random_program(rng, 1 + round % 3)
    let g = random_geometry(rng)
    let strict = analyze(p, g, 360, @math.PI / 36.0, 2.0 * @math.PI).unwrap()
    let relaxed = analyze(p, g, 360, @math.PI / 2.0 - 1.0e-6, 2.0 * @math.PI).unwrap()
    if strict.sampled_feasible {
      assert_true(
        relaxed.sampled_feasible,
        msg="relaxing the limit rejected a passing profile",
      )
    }
    assert_true(
      strict.sampled_local_feasible <= relaxed.sampled_local_feasible,
      msg="local acceptance is not monotone in the pressure limit",
    )
    assert_eq(strict.points.length(), relaxed.points.length())
  }
}

///|
test "P7 contact points keep the roller distance and segment joins stay continuous" {
  let rng = property_rng(0x3a1cU)
  for round = 0; round < 12; round = round + 1 {
    let p = random_program(rng, 1 + round % 3)
    let g = random_geometry(rng)
    for i = 0; i < 6; i = i + 1 {
      let theta = rng.between(0.0, 2.0 * @math.PI)
      let point = contact(p, g, theta).unwrap()
      let distance = @math.hypot(
        point.pitch_x - point.x,
        point.y - point.pitch_y,
      ).abs()
      assert_true(
        close_enough(distance, g.roller_radius, 1.0e-11),
        msg="contact point is not exactly one roller radius from the pitch point",
      )
    }
    // Joint continuity follows from the laws themselves: every law starts at
    // (0, 0, 0) and ends at (1, 0, 0), so lift, angular velocity and angular
    // acceleration join without a kink even when neighbouring segments use
    // different laws.  The tolerance is 1e-12 rather than 1e-15 because
    // sin(2*pi) is not exactly zero in double, so the cycloidal law ends with a
    // rounding-level acceleration instead of an exact zero.  Sampling near a
    // joint would only measure the slope over the sample step.
    for law in laws() {
      let start = normalized(law, 0.0).unwrap()
      let end = normalized(law, 1.0).unwrap()
      assert_true(
        close_within(start.s, 0.0, 1.0e-12),
        msg="law does not start at zero lift",
      )
      assert_true(
        close_within(start.v, 0.0, 1.0e-12),
        msg="law starts with nonzero velocity",
      )
      assert_true(
        close_within(start.a, 0.0, 1.0e-12),
        msg="law starts with nonzero acceleration",
      )
      assert_true(
        close_within(end.s, 1.0, 1.0e-12),
        msg="law does not end at unit lift",
      )
      assert_true(
        close_within(end.v, 0.0, 1.0e-12),
        msg="law ends with nonzero velocity",
      )
      assert_true(
        close_within(end.a, 0.0, 1.0e-12),
        msg="law ends with nonzero acceleration",
      )
    }
  }
}

///|
test "P8 generated meshes keep the documented interval budget" {
  let rng = property_rng(0x7e5aU)
  for round = 0; round < 12; round = round + 1 {
    let p = random_program(rng, 1 + round % 4)
    let g = random_geometry(rng)
    for resolution in ([36, 120, 720, 2000] : Array[Int32]) {
      let analysis = analyze(p, g, resolution, @math.PI / 6.0, 2.0 * @math.PI).unwrap()
      let intervals = analysis.points.length() - 1
      assert_true(
        intervals >= resolution,
        msg="fewer intervals than the nominal resolution",
      )
      assert_true(
        intervals <= resolution + p.segments.length(),
        msg="interval budget exceeded the segment round-up allowance",
      )
      for index = 0; index + 1 < analysis.points.length(); index = index + 1 {
        assert_true(
          analysis.points[index + 1].theta > analysis.points[index].theta,
          msg="sample angles are not strictly increasing",
        )
      }
      assert_true(
        close_within(
          analysis.points[analysis.points.length() - 1].theta,
          2.0 * @math.PI,
          1.0e-15,
        ),
        msg="the mesh does not close at one revolution",
      )
    }
  }
}
