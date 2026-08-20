//// TTY and ANSI color-support detection.
////
//// This module answers three questions a CLI program asks at startup:
//// 1. Is this stream connected to a terminal? (`is_tty`)
//// 2. What level of ANSI color does it support? (`detect_color_level`)
//// 3. Is its background light or dark? (`detect_background` and the opt-in
////    `query_background`)

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
import gleam/int
@target(javascript)
import gleam/option.{None, Some}
import gleam/order
import tty/resolve_background as background_resolver
import tty/resolve_color_level as resolver
import tty/resolve_query_background as query_background_resolver

const background_query_timeout_ms = 100

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

/// Detected terminal background.
/// This variant set is intentionally stable for 1.x.
///
/// ```gleam
/// case tty.detect_background(Stdout) {
///   Light -> render_for_light_background()
///   Dark -> render_for_dark_background()
///   Unknown -> render_default_theme()
/// }
/// ```
pub type Background {
  /// Terminal has a light background.
  Light
  /// Terminal has a dark background.
  Dark
  /// Background could not be determined.
  Unknown
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

/// Inverse of the internal background rank: maps a `0..2` rank back to a
/// `Background`, returning `Error(Nil)` for any out-of-range value. Used to
/// convert the internal resolver's rank into a `Background`.
fn background_from_rank(rank: Int) -> Result(Background, Nil) {
  case rank {
    0 -> Ok(Unknown)
    1 -> Ok(Dark)
    2 -> Ok(Light)
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
  // nolint: assert_ok_pattern -- internal 0..3 invariant guard; public fn returns ColorLevel by design (see comment above)
  let assert Ok(level) = color_level_from_rank(rank)
    as "resolve_color_level must return a rank in 0..3"
  level
}

/// Detects whether the terminal background is light or dark from `COLORFGBG`.
///
/// The `stream` argument is accepted for API symmetry with `detect_color_level`
/// and to leave room for future stream-specific detection; the current
/// `COLORFGBG` signal is environment-wide and stream-independent.
///
/// On the JavaScript target this reads `process.env`, so it requires a
/// Node-style runtime. When a JavaScript runtime does not provide `process` or
/// `process.env`, environment variables are treated as unset and this function
/// returns `Unknown`.
///
/// Returns `Unknown` when `COLORFGBG` is unset, malformed, or does not contain a
/// clear background palette index.
///
/// ```gleam
/// case tty.detect_background(Stdout) {
///   Light -> render_dark_text()
///   Dark -> render_light_text()
///   Unknown -> render_default_theme()
/// }
/// ```
pub fn detect_background(_stream: Stream) -> Background {
  let rank = background_resolver.resolve_background(env: get_env)
  // The resolver is statically guaranteed to return a rank in 0..2, so this
  // can only fail if that internal invariant is ever broken. Crashing loudly
  // is preferable to silently degrading background detection to Unknown.
  // nolint: assert_ok_pattern -- internal 0..2 invariant guard; public fn returns Background by design (see comment above)
  let assert Ok(background) = background_from_rank(rank)
    as "resolve_background must return a rank in 0..2"
  background
}

/// Actively queries a terminal for its background color using OSC 11.
///
/// Unlike `detect_background`, this function is impure and opt-in: it writes a
/// query to the selected terminal stream and briefly reads from the terminal in
/// raw mode. The query uses a fixed 100 ms timeout and always restores terminal
/// state before returning.
///
/// Returns `Unknown` immediately when `stream` is not a TTY. It also returns
/// `Unknown` when the runtime does not support a safe bounded query, the
/// terminal does not respond before the timeout, or the response is malformed.
///
/// ```gleam
/// case tty.query_background(Stdout) {
///   Light -> render_for_light_background()
///   Dark -> render_for_dark_background()
///   Unknown -> render_default_theme()
/// }
/// ```
pub fn query_background(stream: Stream) -> Background {
  let rank =
    query_background_resolver.resolve_query_background(
      is_tty: is_tty(stream),
      query: fn() {
        query_background_response(stream, background_query_timeout_ms)
      },
    )

  case background_from_rank(rank) {
    Ok(background) -> background
    Error(Nil) -> Unknown
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

@external(erlang, "tty_ffi", "get_env")
@external(javascript, "./tty_ffi.mjs", "getEnv")
fn get_env(name: String) -> Result(String, Nil)

@target(erlang)
@external(erlang, "tty_ffi", "query_background")
fn query_background_response(
  stream: Stream,
  timeout_ms: Int,
) -> Result(String, Nil)

@target(javascript)
fn query_background_response(
  stream: Stream,
  timeout_ms: Int,
) -> Result(String, Nil) {
  let stream_name = case stream {
    Stdin -> "stdin"
    Stdout -> "stdout"
    Stderr -> "stderr"
  }

  case
    decode.run(
      query_background_javascript(stream_name, timeout_ms),
      decode.optional(decode.string),
    )
  {
    Ok(Some(response)) -> Ok(response)
    Ok(None) | Error(_) -> Error(Nil)
  }
}

@target(javascript)
@external(javascript, "./tty_ffi.mjs", "queryOsc11")
fn query_background_javascript(stream_name: String, timeout_ms: Int) -> Dynamic
