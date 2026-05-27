import gleam/string

/// Internal color resolution logic.
///
/// Returns a stable rank (`0..3`) where:
/// - `0` => NoColor
/// - `1` => Basic
/// - `2` => Ansi256
/// - `3` => TrueColor
pub fn resolve_color_level(
  is_tty is_tty: Bool,
  env env: fn(String) -> Result(String, Nil),
) -> Int {
  case env("NO_COLOR") {
    Ok(value) if value != "" -> 0
    _ -> resolve_forced_or_tty(is_tty, env)
  }
}

fn resolve_forced_or_tty(
  is_tty: Bool,
  env: fn(String) -> Result(String, Nil),
) -> Int {
  case env("FORCE_COLOR") {
    Ok(value) -> force_color_level(value)
    Error(_) ->
      case is_tty {
        True -> resolve_tty_color(env)
        False -> 0
      }
  }
}

fn force_color_level(value: String) -> Int {
  case string.lowercase(value) {
    "0" | "false" -> 0
    "2" -> 2
    "3" -> 3
    _ -> 1
  }
}

fn resolve_tty_color(env: fn(String) -> Result(String, Nil)) -> Int {
  let term = env("TERM")

  case term {
    Ok("dumb") -> 0
    _ ->
      case env("COLORTERM") {
        Ok(colorterm) ->
          case string.lowercase(colorterm) {
            "truecolor" -> 3
            "24bit" -> 3
            _ -> resolve_by_term_or_ci(term, env)
          }
        Error(_) -> resolve_by_term_or_ci(term, env)
      }
  }
}

fn resolve_by_term_or_ci(
  term: Result(String, Nil),
  env: fn(String) -> Result(String, Nil),
) -> Int {
  case term {
    Ok(term) ->
      case string.contains(term, "256") {
        True -> 2
        False -> resolve_ci(env)
      }
    Error(_) -> resolve_ci(env)
  }
}

fn resolve_ci(env: fn(String) -> Result(String, Nil)) -> Int {
  case env("CI") {
    Ok(_) -> 1
    Error(_) -> 0
  }
}
