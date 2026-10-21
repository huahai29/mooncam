///|
/// Motion law on a normalized rise from zero to one.
pub(all) enum Law {
  Cycloidal
  Polynomial345
  Polynomial4567
}

///|
/// Values and derivatives with respect to the independent variable.
pub(all) struct Motion {
  s : Double
  v : Double
  a : Double
  j : Double
}

///|
/// Finite-value predicate shared by public input validation.
pub fn finite(x : Double) -> Bool {
  x == x && x - x == 0.0
}
