///|
/// Margin is positive on the permitted side. Offset-factor equality is rejected.
pub(all) struct ConstraintDiagnostic {
  code : String
  value : Double
  limit : Double
  margin : Double
  passed : Bool
  location : Location
}

///|
pub(all) struct Diagnostics {
  pressure : ConstraintDiagnostic
  offset_factor : ConstraintDiagnostic
}

///|
/// Analysis and Program must come from the same calculation.
pub fn diagnose(
  p : Program,
  a : Analysis,
  pressure_limit : Double,
) -> Result[Diagnostics, String] {
  if !finite(pressure_limit) ||
    pressure_limit <= 0.0 ||
    pressure_limit >= @math.PI / 2.0 {
    return Err("pressure limit must be in (0, pi/2) radians")
  }
  let pressure_location = match
    locate_sample(p, a.points, a.pressure_sample_index) {
    Ok(l) => l
    Err(e) => return Err(e)
  }
  let factor_location = match
    locate_sample(p, a.points, a.offset_factor_sample_index) {
    Ok(l) => l
    Err(e) => return Err(e)
  }
  Ok({
    pressure: {
      code: "pressure_limit",
      value: a.max_pressure,
      limit: pressure_limit,
      margin: pressure_limit - a.max_pressure,
      passed: a.max_pressure <= pressure_limit,
      location: pressure_location,
    },
    offset_factor: {
      code: "offset_factor_limit",
      value: a.min_offset_factor,
      limit: Offset_factor_min,
      margin: a.min_offset_factor - Offset_factor_min,
      passed: a.min_offset_factor > Offset_factor_min,
      location: factor_location,
    },
  })
}

///|
pub(all) struct SamplingLevel {
  nominal_resolution : Int32
  sample_count : Int32
  pressure : ConstraintDiagnostic
  offset_factor : ConstraintDiagnostic
  crossings : CrossingCheck
  state : String
}

///|
/// Last two levels' absolute metric changes; no convergence verdict or error bound.
pub(all) struct SamplingComparison {
  levels : Array[SamplingLevel]
  pressure_change : Double
  offset_factor_change : Double
  state_consistent : Bool
}

///|
fn comparison_resolutions(resolution : Int32) -> Array[Int32] {
  if resolution <= Json_resolution_max / 4 {
    [resolution, resolution * 2, resolution * 4]
  } else {
    [resolution / 4, resolution / 2, resolution]
  }
}

///|
/// Reuses the current result only at its exact nominal resolution.
fn compare_sampling_cached(
  p : Program,
  g : Geometry,
  resolutions : Array[Int32],
  pressure_limit : Double,
  omega : Double,
  cached : Analysis?,
) -> Result[SamplingComparison, String] {
  if resolutions.length() < 2 || resolutions.length() > Comparison_levels_max {
    return Err(
      "sampling comparison requires 2..\{Comparison_levels_max} levels",
    )
  }
  let mut previous = 0
  for resolution in resolutions {
    if resolution < Resolution_min ||
      resolution > Library_resolution_max ||
      resolution <= previous {
      return Err(
        "comparison resolutions must be strictly increasing and within library limits",
      )
    }
    previous = resolution
  }
  let levels : Array[SamplingLevel] = []
  for resolution in resolutions {
    let a = match cached {
      Some(a) if a.nominal_resolution == resolution => a
      _ =>
        match analyze(p, g, resolution, pressure_limit, omega) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
    }
    let d = match diagnose(p, a, pressure_limit) {
      Ok(d) => d
      Err(e) => return Err(e)
    }
    levels.push({
      nominal_resolution: resolution,
      sample_count: a.points.length(),
      pressure: d.pressure,
      offset_factor: d.offset_factor,
      crossings: a.crossings,
      state: a.state(),
    })
  }
  let last = levels[levels.length() - 1]
  let before = levels[levels.length() - 2]
  Ok({
    levels,
    pressure_change: (last.pressure.value - before.pressure.value).abs(),
    offset_factor_change: (last.offset_factor.value - before.offset_factor.value).abs(),
    state_consistent: levels.all(fn(level) { level.state == last.state }),
  })
}

///|
/// Full independent sampled checks at each level, not continuous certification.
pub fn compare_sampling(
  p : Program,
  g : Geometry,
  resolutions : Array[Int32],
  pressure_limit : Double,
  omega : Double,
) -> Result[SamplingComparison, String] {
  compare_sampling_cached(p, g, resolutions, pressure_limit, omega, None)
}
