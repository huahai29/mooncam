///|
/// Typed errors distinguish exhausted grids from invalid input and failures.
pub(all) enum SearchError {
  InvalidInput(String)
  NumericalFailure(String)
  IndeterminateGeometry(String)
  NoCandidate(Int32)
}

///|
/// First accepted point on a finite grid, not a continuous optimum.
pub(all) struct SearchResult {
  geometry : Geometry
  analysis : Analysis
  tested : Int32
  grid_step : Double
  verification_resolution : Int32
}

///| Reuse geometry-independent motion meshes; reject candidates by scalar metrics.

///|
/// The coarse pass allocates no coordinates; the fine pass returns the metrics and
/// the coordinates that topology verification consumes.
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
) -> Result[SearchResult, SearchError] {
  if !finite(lower) ||
    !finite(upper) ||
    lower < Base_radius_min ||
    upper > Geometry_length_max ||
    upper < lower ||
    intervals < 1 ||
    intervals > Search_intervals_max ||
    resolution < Resolution_min ||
    resolution > Search_resolution_max {
    return Err(
      InvalidInput(
        "search needs ordered radius bounds in [\{Base_radius_min}, \{Geometry_length_max}], 1..\{Search_intervals_max} intervals and \{Resolution_min}..\{Search_resolution_max} resolution",
      ),
    )
  }
  match validate_analysis(pressure_limit, omega) {
    Err(e) => return Err(InvalidInput(e))
    Ok(_) => ()
  }
  match validate_geometry({ base_radius: upper, roller_radius, offset, }) {
    Err(e) => return Err(InvalidInput(e))
    Ok(_) => ()
  }
  let coarse = match motion_mesh(p, resolution) {
    Ok(m) => m
    Err(e) => return Err(NumericalFailure(e))
  }
  let fine = match motion_mesh(p, resolution * Search_refinement) {
    Ok(m) => m
    Err(e) => return Err(NumericalFailure(e))
  }
  let step = (upper - lower) / intervals.to_double()
  for i = 0; i <= intervals; i = i + 1 {
    let g : Geometry = {
      base_radius: lower + i.to_double() * step,
      roller_radius,
      offset,
    }
    if validate_geometry(g) is Err(_) {
      continue
    }
    let a = match scan_mesh(coarse, g, pressure_limit, omega, false) {
      Ok(a) => a
      Err(e) => return Err(NumericalFailure(e))
    }
    if !a.metrics.sampled_local_feasible {
      continue
    }
    // A retained scan returns the same metrics as a metrics-only scan, so the
    // fine mesh is scanned once. The cost is real: a candidate that passes the
    // coarse filter but fails the fine one builds coordinates it discards.
    let b = match scan_mesh(fine, g, pressure_limit, omega, true) {
      Ok(a) => a
      Err(e) => return Err(NumericalFailure(e))
    }
    if !b.metrics.sampled_local_feasible {
      continue
    }
    let complete = finish_scan(b)
    match complete.crossings {
      Failed(e) => return Err(NumericalFailure(e))
      Indeterminate(_, _) =>
        return Err(IndeterminateGeometry("profile topology is indeterminate"))
      _ => ()
    }
    if complete.sampled_feasible {
      return Ok({
        geometry: g,
        analysis: complete,
        tested: i + 1,
        grid_step: step,
        verification_resolution: resolution * Search_refinement,
      })
    }
  }
  Err(NoCandidate(intervals + 1))
}
