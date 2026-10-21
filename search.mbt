///|
/// First feasible point on a finite increasing grid, not a global optimum.
pub(all) struct SearchResult {
  geometry : Geometry
  analysis : Analysis
  tested : Int32
  grid_step : Double
  verification_resolution : Int32
}

///| Search a bounded grid; recheck candidates at double angular resolution.

///|
/// No monotonicity of curvature feasibility is assumed.
pub fn search_base(
  p : Program,
  roller_radius : Double,
  offset : Double,
  lower : Double,
  upper : Double,
  intervals : Int32,
  resolution : Int32,
  pressure_limit : Double,
  omega : Double,
) -> Result[SearchResult, String] {
  if !finite(lower) ||
    !finite(upper) ||
    lower <= 0.0 ||
    upper < lower ||
    intervals < 1 ||
    intervals > 256 ||
    resolution < 36 ||
    resolution > 2000 {
    return Err(
      "search needs finite ordered positive bounds, 1..256 intervals and 36..2000 resolution",
    )
  }
  let step = (upper - lower) / intervals.to_double()
  for i = 0; i <= intervals; i = i + 1 {
    let g : Geometry = {
      base_radius: lower + i.to_double() * step,
      roller_radius,
      offset,
    }
    // An offset may be unreachable at a small radius, but reachable later.
    if validate_geometry(g) is Err(_) {
      continue
    }
    let a = match analyze(p, g, resolution, pressure_limit, omega) {
      Err(e) => return Err(e)
      Ok(a) => a
    }
    if a.sampled_feasible {
      let verified = match
        analyze(p, g, resolution * 2, pressure_limit, omega) {
        Err(e) => return Err(e)
        Ok(a) => a
      }
      if verified.sampled_feasible {
        return Ok({
          geometry: g,
          analysis: verified,
          tested: i + 1,
          grid_step: step,
          verification_resolution: resolution * 2,
        })
      }
    }
  }
  Err(
    "no feasible grid candidate found; this does not prove continuous infeasibility",
  )
}
