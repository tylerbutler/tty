//// TTY and ANSI color-support detection.
////
//// This module answers two questions a CLI program asks at startup:
//// 1. Is this stream connected to a terminal? (`is_tty`)
//// 2. What level of ANSI color does it support? (`detect_color_level`)

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
import tty/resolve_color_level as resolver

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
  resolver.resolve_color_level(is_tty: is_tty(stream), env: get_env)
  |> color_level_from_int
}

fn color_level_from_int(value: Int) -> ColorLevel {
  case value {
    0 -> NoColor
    1 -> Basic
    2 -> Ansi256
    _ -> TrueColor
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
