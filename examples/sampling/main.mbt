///|
pub fn sample_case(n : Int32, analytic : Bool) -> String {
  let law = if analytic { @cam.Polynomial345 } else { @cam.Polynomial4567 }
  let p = @cam.example_program(law)
  let g : @cam.Geometry = {
    base_radius: if !analytic {
      40.0
    } else {
      20.0 * 2568.0 / 16807.0 - 0.1
    },
    roller_radius: if !analytic {
      4.0
    } else {
      0.1
    },
    offset: 0.0,
  }
  let a = @cam.analyze(p, g, n, @math.PI / 2.1, 1.0).unwrap()
  "\{a.max_pressure * 180.0 / @math.PI},\{a.pressure_angle * 180.0 / @math.PI}"
}

///|
fn main {
  ()
}
