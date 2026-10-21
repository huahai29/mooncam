///|
/// Typed errors distinguish exhausted grids from invalid input and failures.
pub(all) enum SearchError {
  InvalidInput(String)
  NumericalFailure(String)
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
    lower < 1.0e-6 ||
    upper > 1.0e6 ||
    upper < lower ||
    intervals < 1 ||
    intervals > 256 ||
    resolution < 36 ||
    resolution > 2000 {
    return Err(
      InvalidInput(
        "search needs ordered radius bounds in [1e-6, 1e6], 1..256 intervals and 36..2000 resolution",
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
  let fine = match motion_mesh(p, resolution * 2) {
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
    // fine mesh is scanned once. Trade-off: a candidate that passes the coarse
    // filter but fails the fine one now builds coordinates it discards.
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
      _ => ()
    }
    if complete.sampled_feasible {
      return Ok({
        geometry: g,
        analysis: complete,
        tested: i + 1,
        grid_step: step,
        verification_resolution: resolution * 2,
      })
    }
  }
  Err(NoCandidate(intervals + 1))
}
