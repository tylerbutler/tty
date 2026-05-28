//// TTY and ANSI color-support detection.
////
//// This module answers two questions a CLI program asks at startup:
//// 1. Is this stream connected to a terminal? (`is_tty`)
//// 2. What level of ANSI color does it support? (`detect_color_level`)

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
import gleam/int
import gleam/order
import tty/resolve_color_level as resolver

/// The standard I/O streams of the running process.
/// This variant set is intentionally stable for 1.x.
pub type Stream {
  /// Standard input.
  Stdin
  /// Standard output.
  Stdout
  /// Standard error.
  Stderr
}

/// Level of ANSI color support detected for a stream.
/// This variant set is intentionally stable for 1.x.
///
/// ```gleam
/// case tty.detect_color_level(Stdout) {
///   NoColor -> render_plain_text()
///   Basic -> render_basic_ansi()
///   Ansi256 -> render_256_color()
///   TrueColor -> render_rgb_color()
/// }
/// ```
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
/// let level = tty.detect_color_level(Stdout)
/// case tty.color_level_at_least(actual: level, at_least: Ansi256) {
///   True -> render_256_color()
///   False -> render_basic()
/// }
/// ```
pub fn color_level_at_least(
  actual actual: ColorLevel,
  at_least required: ColorLevel,
) -> Bool {
  case color_level_compare(actual, required) {
    order.Lt -> False
    order.Eq | order.Gt -> True
  }
}

/// Orders two color levels by capability, where
/// `NoColor` < `Basic` < `Ansi256` < `TrueColor`. Returns a `gleam/order`
/// `Order`, so it composes with `list.sort`, `order.reverse`, and friends.
///
/// ```gleam
/// tty.color_level_compare(Basic, Ansi256)
/// // -> order.Lt
/// ```
pub fn color_level_compare(a: ColorLevel, b: ColorLevel) -> order.Order {
  int.compare(color_level_rank(a), color_level_rank(b))
}

/// Internal capability rank for a `ColorLevel` (`NoColor`=0 .. `TrueColor`=3).
/// The numeric values are an implementation detail, not part of the public
/// 1.x API — callers should use `color_level_compare`/`color_level_at_least`.
fn color_level_rank(level: ColorLevel) -> Int {
  case level {
    NoColor -> 0
    Basic -> 1
    Ansi256 -> 2
    TrueColor -> 3
  }
}

/// Inverse of `color_level_rank`: maps a `0..3` rank back to a `ColorLevel`,
/// returning `Error(Nil)` for any out-of-range value. Used to convert the
/// internal resolver's rank into a `ColorLevel`.
fn color_level_from_rank(rank: Int) -> Result(ColorLevel, Nil) {
  case rank {
    0 -> Ok(NoColor)
    1 -> Ok(Basic)
    2 -> Ok(Ansi256)
    3 -> Ok(TrueColor)
    _ -> Error(Nil)
  }
}

/// Returns `True` if the given stream is connected to a terminal.
///
/// On the Erlang target this uses `io:getopts/1` (requires OTP 26+). If
/// terminal options cannot be read, this returns `False`.
/// On the JavaScript target this uses `process.stdin.isTTY`,
/// `process.stdout.isTTY`, or `process.stderr.isTTY`, so it requires a
/// Node-style runtime with those streams.
///
/// ```gleam
/// case tty.is_tty(Stdout) {
///   True -> show_spinner()
///   False -> print_plain_progress()
/// }
/// ```
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
///
/// When a JavaScript runtime does not provide `process` or `process.env`,
/// environment variables are treated as unset and this function falls back to
/// `NoColor` unless other forced inputs are available.
///
/// ```gleam
/// case tty.detect_color_level(Stdout) {
///   NoColor -> render_without_ansi()
///   Basic -> render_with_basic_ansi()
///   Ansi256 -> render_with_256_colors()
///   TrueColor -> render_with_truecolor()
/// }
/// ```
pub fn detect_color_level(stream: Stream) -> ColorLevel {
  let rank = resolver.resolve_color_level(is_tty: is_tty(stream), env: get_env)
  // The resolver is statically guaranteed to return a rank in 0..3, so this
  // can only fail if that internal invariant is ever broken. Crashing loudly
  // is preferable to silently degrading color detection to NoColor.
  let assert Ok(level) = color_level_from_rank(rank)
    as "resolve_color_level must return a rank in 0..3"
  level
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
