import startest/expect
import tty.{Ansi256, NoColor, Stdout, TrueColor}
import tty/env_mutate

// End-to-end test of the real environment-variable FFI: this drives
// `tty.detect_color_level` through the production `get_env` (Erlang
// `os:getenv` / JS `process.env` + Dynamic decode) rather than an injected
// stub. NO_COLOR and FORCE_COLOR both override the TTY check, so the outcomes
// are deterministic whether or not the test runner is attached to a terminal.
//
// All scenarios live in one test so the global env mutations cannot interleave
// with each other under a concurrent runner. The environment is restored at
// the end.
pub fn detect_color_level_honors_real_env_test() {
  // NO_COLOR (non-empty) wins over everything else.
  env_mutate.unset_env("FORCE_COLOR")
  env_mutate.set_env("NO_COLOR", "1")
  tty.detect_color_level(Stdout)
  |> expect.to_equal(NoColor)

  // FORCE_COLOR overrides the TTY check; the level follows its value.
  env_mutate.unset_env("NO_COLOR")
  env_mutate.set_env("FORCE_COLOR", "2")
  tty.detect_color_level(Stdout)
  |> expect.to_equal(Ansi256)

  env_mutate.set_env("FORCE_COLOR", "3")
  tty.detect_color_level(Stdout)
  |> expect.to_equal(TrueColor)

  // Restore a pristine environment for other tests.
  env_mutate.unset_env("FORCE_COLOR")
  env_mutate.unset_env("NO_COLOR")
}
