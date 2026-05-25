//// TTY and ANSI color-support detection.
////
//// This module answers two questions a CLI program asks at startup:
//// 1. Is this stream connected to a terminal? (`is_tty`)
//// 2. What level of ANSI color does it support? (`detect_color_level`)

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
import gleam/string

/// The standard I/O streams of the running process.
pub type Stream {
  /// Standard input.
  Stdin
  /// Standard output.
  Stdout
  /// Standard error.
  Stderr
}

/// Level of ANSI color support detected for a stream.
pub type ColorLevel {
  /// No ANSI escape codes should be emitted.
  NoColor
  /// 16-color (basic ANSI) is supported.
  Basic
  /// 256-color (xterm-256) is supported.
  Ansi256
  /// 24-bit truecolor (RGB) is supported.
  TrueColor
}

/// Returns `True` if the actual color level is at least as capable as the
/// required level. Use this to gate features without matching every variant:
///
/// ```gleam
/// case tty.color_level_at_least(tty.detect_color_level(Stdout), Ansi256) {
///   True -> render_256_color()
///   False -> render_basic()
/// }
/// ```
pub fn color_level_at_least(actual: ColorLevel, required: ColorLevel) -> Bool {
  color_level_to_int(actual) >= color_level_to_int(required)
}

/// Maps a `ColorLevel` to a stable integer rank (`NoColor`=0, `Basic`=1,
/// `Ansi256`=2, `TrueColor`=3). This mapping is part of the public API.
pub fn color_level_to_int(level: ColorLevel) -> Int {
  case level {
    NoColor -> 0
    Basic -> 1
    Ansi256 -> 2
    TrueColor -> 3
  }
}

/// Returns `True` if the given stream is connected to a terminal.
///
/// On the Erlang target this uses `io:getopts/1` (requires OTP 26+). If
/// terminal options cannot be read, this returns `False`.
/// On the JavaScript target this uses `process.stdin.isTTY`,
/// `process.stdout.isTTY`, or `process.stderr.isTTY`, so it requires a
/// Node-style runtime with those streams.
pub fn is_tty(stream: Stream) -> Bool {
  case stream {
    Stdin -> stdin_is_tty()
    Stdout -> stdout_is_tty()
    Stderr -> stderr_is_tty()
  }
}

/// Detects color support for a stream, honoring `NO_COLOR`, `FORCE_COLOR`,
/// `CI`, `TERM`, and `COLORTERM` environment variables.
///
/// On the JavaScript target this reads `process.env`, so it requires a
/// Node-style runtime.
pub fn detect_color_level(stream: Stream) -> ColorLevel {
  resolve_color_level(is_tty: is_tty(stream), env: get_env)
}

/// Advanced color-resolution hook. Prefer `detect_color_level` for normal
/// application code.
///
/// This API exists primarily for deterministic tests and custom integrations.
/// The stable entrypoint for most users is `detect_color_level`.
///
/// The `env` callback returns `Ok(value)` for a set environment variable,
/// including `Ok("")` for a set-but-empty variable. Return `Error(Nil)` when
/// the variable is unset.
///
/// Rules (first match wins; later rules apply only when no earlier rule
/// matched):
///   1. `NO_COLOR` set to any non-empty value -> `NoColor`
///   2. `FORCE_COLOR` set (overrides the TTY check below):
///        - `"0"` or `"false"` (case-insensitive) -> `NoColor`
///        - `"2"` -> `Ansi256`
///        - `"3"` -> `TrueColor`
///        - `""`, `"1"`, `"true"`, or any other value -> `Basic`
///   3. `is_tty` is `False` -> `NoColor`
///   4. `TERM=dumb` -> `NoColor`
///   5. `COLORTERM=truecolor` or `COLORTERM=24bit` (case-insensitive)
///      -> `TrueColor`
///   6. `TERM` contains `"256"` -> `Ansi256`
///   7. `CI` set -> `Basic`
///   8. otherwise -> `NoColor`
///
/// The default in rule 8 errs on the side of safety: an unknown TTY with
/// no color hints is treated as colorless, matching the behavior of
/// `chalk/supports-color`.
pub fn resolve_color_level(
  is_tty is_tty: Bool,
  env env: fn(String) -> Result(String, Nil),
) -> ColorLevel {
  case env("NO_COLOR") {
    Ok(value) if value != "" -> NoColor
    _ -> resolve_forced_or_tty(is_tty, env)
  }
}

fn resolve_forced_or_tty(
  is_tty: Bool,
  env: fn(String) -> Result(String, Nil),
) -> ColorLevel {
  case env("FORCE_COLOR") {
    Ok(value) -> force_color_level(value)
    Error(_) ->
      case is_tty {
        True -> resolve_tty_color(env)
        False -> NoColor
      }
  }
}

fn force_color_level(value: String) -> ColorLevel {
  case string.lowercase(value) {
    "0" | "false" -> NoColor
    "2" -> Ansi256
    "3" -> TrueColor
    _ -> Basic
  }
}

fn resolve_tty_color(env: fn(String) -> Result(String, Nil)) -> ColorLevel {
  let term = env("TERM")

  case term {
    Ok("dumb") -> NoColor
    _ ->
      case env("COLORTERM") {
        Ok(colorterm) ->
          case string.lowercase(colorterm) {
            "truecolor" -> TrueColor
            "24bit" -> TrueColor
            _ -> resolve_by_term_or_ci(term, env)
          }
        Error(_) -> resolve_by_term_or_ci(term, env)
      }
  }
}

fn resolve_by_term_or_ci(
  term: Result(String, Nil),
  env: fn(String) -> Result(String, Nil),
) -> ColorLevel {
  case term {
    Ok(term) ->
      case string.contains(term, "256") {
        True -> Ansi256
        False -> resolve_ci(env)
      }
    Error(_) -> resolve_ci(env)
  }
}

fn resolve_ci(env: fn(String) -> Result(String, Nil)) -> ColorLevel {
  case env("CI") {
    Ok(_) -> Basic
    Error(_) -> NoColor
  }
}

@external(erlang, "tty_ffi", "stdin_is_tty")
@external(javascript, "./tty_ffi.mjs", "stdinIsTty")
fn stdin_is_tty() -> Bool

@external(erlang, "tty_ffi", "stdout_is_tty")
@external(javascript, "./tty_ffi.mjs", "stdoutIsTty")
fn stdout_is_tty() -> Bool

@external(erlang, "tty_ffi", "stderr_is_tty")
@external(javascript, "./tty_ffi.mjs", "stderrIsTty")
fn stderr_is_tty() -> Bool

@target(erlang)
@external(erlang, "tty_ffi", "get_env")
fn raw_get_env_erlang(name: String) -> Result(String, Nil)

@target(javascript)
@external(javascript, "./tty_ffi.mjs", "getEnv")
fn raw_get_env_js(name: String) -> Dynamic

@target(erlang)
fn get_env(name: String) -> Result(String, Nil) {
  raw_get_env_erlang(name)
}

@target(javascript)
fn get_env(name: String) -> Result(String, Nil) {
  case decode.run(raw_get_env_js(name), decode.string) {
    Ok(s) -> Ok(s)
    Error(_) -> Error(Nil)
  }
}
