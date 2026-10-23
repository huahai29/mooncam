///|
/// Zero-based IDs. Sample IDs are local to one mesh, never cross-resolution IDs.
pub(all) struct Location {
  sample_index : Int32?
  segment_index : Int32
  theta_rad : Double
  segment_start_rad : Double
  segment_end_rad : Double
  law : String
  periodic_endpoint : Bool
}

///|
pub(all) struct EdgeLocation {
  edge_index : Int32
  segment_index : Int32
  start : Location
  end : Location
}

///|
fn law_name(law : Law) -> String {
  match law {
    Cycloidal => "cycloidal"
    Polynomial345 => "345"
    Polynomial4567 => "4567"
  }
}

///|
/// Shared right-side segment lookup, also used by the motion evaluator.
fn segment_at(p : Program, t : Double) -> Int32 {
  let mut lo = 0
  let mut hi = p.segments.length()
  while lo + 1 < hi {
    let mid = (lo + hi) / 2
    if p.starts[mid] <= t {
      lo = mid
    } else {
      hi = mid
    }
  }
  lo
}

///|
fn location_at(p : Program, theta : Double, index : Int32?) -> Location {
  let endpoint = theta == 2.0 * @math.PI
  let k = segment_at(p, if endpoint { 0.0 } else { theta })
  {
    sample_index: index,
    segment_index: k,
    theta_rad: theta,
    segment_start_rad: p.starts[k],
    segment_end_rad: if k + 1 == p.segments.length() {
      2.0 * @math.PI
    } else {
      p.starts[k + 1]
    },
    law: law_name(p.segments[k].law),
    periodic_endpoint: endpoint,
  }
}

///|
/// Exact angle query in [0, 2pi]; no implied nearest sample. 2pi uses segment 0.
pub fn locate_angle(p : Program, theta : Double) -> Result[Location, String] {
  if !finite(theta) || theta < 0.0 || theta > 2.0 * @math.PI {
    return Err("location angle must be in [0, 2pi]")
  }
  Ok(location_at(p, theta, None))
}

///|
pub fn locate_sample(
  p : Program,
  points : Array[CamPoint],
  index : Int32,
) -> Result[Location, String] {
  if index < 0 || index >= points.length() {
    return Err("sample index out of range")
  }
  match locate_angle(p, points[index].theta) {
    Err(e) => Err(e)
    Ok(location) => Ok({ ..location, sample_index: Some(index), })
  }
}

///|
/// Edge i connects samples i and i+1; its owning segment is the start's segment.
pub fn locate_edge(
  p : Program,
  points : Array[CamPoint],
  index : Int32,
) -> Result[EdgeLocation, String] {
  if index < 0 || index >= points.length() - 1 {
    return Err("edge index out of range")
  }
  let start = match locate_sample(p, points, index) {
    Ok(l) => l
    Err(e) => return Err(e)
  }
  let end = match locate_sample(p, points, index + 1) {
    Ok(l) => l
    Err(e) => return Err(e)
  }
  if start.periodic_endpoint || end.theta_rad < start.theta_rad {
    return Err("edge requires increasing one-revolution sample angles")
  }
  Ok({ edge_index: index, segment_index: start.segment_index, start, end, })
}
