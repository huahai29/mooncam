///|
fn main {
  let p = @cam.example_program(@cam.Polynomial4567)
  let g : @cam.Geometry = {
    base_radius: 40.0,
    roller_radius: 4.0,
    offset: 0.0,
  }
  match @cam.analyze(p, g, 720, @math.PI / 6.0, 2.0 * @math.PI) {
    Ok(a) => {
      println(a.max_pressure * 180.0 / @math.PI)
      println(a.min_offset_factor)
      println(a.points.length())
    }
    Err(message) => println(message)
  }
}
