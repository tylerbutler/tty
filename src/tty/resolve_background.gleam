import gleam/int
import gleam/list
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

// COLORFGBG is `fg;bg` or, in rxvt's extended form, `fg;xpm;bg` — the
// background is always the LAST `;`-separated field (vim parses it the same
// way). A value with no `;` carries no background field at all.
fn resolve_colorfgbg(value: String) -> Int {
  case string.split(value, ";") {
    [_, ..rest] ->
      case list.last(rest) {
        Ok(bg) -> classify_background(string.trim(bg))
        Error(Nil) -> 0
      }
    [] -> 0
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
