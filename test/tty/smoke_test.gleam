import startest/expect
import tty.{Ansi256, Basic, NoColor, Stderr, Stdin, Stdout, TrueColor}

// Smoke tests: assert FFI calls don't crash and return values of the
// expected types. Exact booleans/levels depend on the runtime environment.

fn expect_bool(value: Bool) {
  case value {
    True | False -> expect.to_be_true(True)
  }
}

pub fn is_tty_stdin_returns_bool_test() {
  tty.is_tty(Stdin)
  |> expect_bool
}

pub fn is_tty_stdout_returns_bool_test() {
  tty.is_tty(Stdout)
  |> expect_bool
}

pub fn is_tty_stderr_returns_bool_test() {
  tty.is_tty(Stderr)
  |> expect_bool
}

pub fn detect_color_level_returns_a_level_test() {
  case tty.detect_color_level(Stdout) {
    NoColor | Basic | Ansi256 | TrueColor -> expect.to_be_true(True)
  }
}
