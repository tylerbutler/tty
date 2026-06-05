import gleam/int
import gleam/string

/// Internal terminal background resolution logic.
///
/// Returns a stable rank (`0..2`) where:
/// - `0` => Unknown
/// - `1` => Dark
/// - `2` => Light
pub fn resolve_background(env env: fn(String) -> Result(String, Nil)) -> Int {
  case env("COLORFGBG") {
    Ok("") | Error(_) -> 0
    Ok(value) -> resolve_colorfgbg(value)
  }
}

fn resolve_colorfgbg(value: String) -> Int {
  case string.split(value, ";") {
    [_, bg, ..] -> classify_background(string.trim(bg))
    _ -> 0
  }
}

fn classify_background(bg: String) -> Int {
  case int.parse(bg) {
    Ok(bg) if bg >= 0 && bg <= 6 -> 1
    Ok(8) -> 1
    Ok(7) -> 2
    Ok(bg) if bg >= 9 && bg <= 15 -> 2
    _ -> 0
  }
}
