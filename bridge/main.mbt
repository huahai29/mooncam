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

///|
pub fn contract() -> String {
  @cam.contract_json()
}

///|
pub fn error_exit_code(code : String) -> Int32 {
  @cam.error_exit_code(code)
}

///|
pub fn result_exit_code(state : String) -> Int32 {
  @cam.result_exit_code(state)
}

///|
pub fn validate_segments(input : String) -> String {
  @cam.validate_segments_json(input)
}
