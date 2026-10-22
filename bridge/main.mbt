///|
pub fn run(input : String) -> String {
  browser_session.run(input)
}

///|
fn main {
  ()
}

///|
pub fn input_limit_bytes() -> Int32 {
  @cam.input_limit_bytes()
}

///|
let browser_session : @cam.Session = @cam.session()

///|
pub fn export_profile(format : String) -> String {
  browser_session.export_profile(format)
}
