import gleam/list
import startest/expect
import tty.{Ansi256, Basic, NoColor, TrueColor, resolve_color_level}
import tty/env_probe

// Helper: build an env-lookup function from a list of pairs.
fn env(pairs: List(#(String, String))) -> fn(String) -> Result(String, Nil) {
  fn(name) { list.key_find(pairs, name) }
}

fn probed_env(
  pairs: List(#(String, String)),
) -> fn(String) -> Result(String, Nil) {
  fn(name) {
    env_probe.record(name)
    list.key_find(pairs, name)
  }
}

pub fn no_color_disables_everything_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("NO_COLOR", "1"), #("FORCE_COLOR", "3")]),
  )
  |> expect.to_equal(NoColor)
}

pub fn empty_no_color_falls_through_to_default_test() {
  // Per no-color.org, only NON-empty NO_COLOR disables. With no other hints
  // we fall to the default (rule 8) which is now NoColor.
  resolve_color_level(is_tty: True, env: env([#("NO_COLOR", "")]))
  |> expect.to_equal(NoColor)
}

pub fn force_color_zero_disables_test() {
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "0")]))
  |> expect.to_equal(NoColor)
}

pub fn force_color_one_enables_basic_even_without_tty_test() {
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "1")]))
  |> expect.to_equal(Basic)
}

pub fn force_color_empty_enables_basic_test() {
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "")]))
  |> expect.to_equal(Basic)
}

pub fn force_color_two_enables_256_test() {
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "2")]))
  |> expect.to_equal(Ansi256)
}

pub fn force_color_three_enables_truecolor_test() {
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "3")]))
  |> expect.to_equal(TrueColor)
}

pub fn non_tty_yields_no_color_test() {
  resolve_color_level(is_tty: False, env: env([]))
  |> expect.to_equal(NoColor)
}

pub fn term_dumb_yields_no_color_test() {
  resolve_color_level(is_tty: True, env: env([#("TERM", "dumb")]))
  |> expect.to_equal(NoColor)
}

pub fn colorterm_truecolor_yields_truecolor_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("COLORTERM", "truecolor"), #("TERM", "xterm")]),
  )
  |> expect.to_equal(TrueColor)
}

pub fn colorterm_24bit_yields_truecolor_test() {
  resolve_color_level(is_tty: True, env: env([#("COLORTERM", "24bit")]))
  |> expect.to_equal(TrueColor)
}

pub fn colorterm_truecolor_is_case_insensitive_test() {
  resolve_color_level(is_tty: True, env: env([#("COLORTERM", "TrueColor")]))
  |> expect.to_equal(TrueColor)
}

pub fn term_with_256_yields_ansi256_test() {
  resolve_color_level(is_tty: True, env: env([#("TERM", "xterm-256color")]))
  |> expect.to_equal(Ansi256)
}

pub fn ci_yields_basic_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("CI", "true"), #("TERM", "xterm")]),
  )
  |> expect.to_equal(Basic)
}

pub fn ci_rule_is_checked_before_default_basic_test() {
  env_probe.reset()

  resolve_color_level(
    is_tty: True,
    env: probed_env([#("CI", "true"), #("TERM", "vt100")]),
  )
  |> expect.to_equal(Basic)

  env_probe.seen("CI")
  |> expect.to_equal(True)
}

pub fn ci_does_not_override_no_color_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("CI", "true"), #("NO_COLOR", "1")]),
  )
  |> expect.to_equal(NoColor)
}

pub fn ci_does_not_override_force_color_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("CI", "true"), #("FORCE_COLOR", "2")]),
  )
  |> expect.to_equal(Ansi256)
}

pub fn ci_does_not_override_non_tty_test() {
  resolve_color_level(is_tty: False, env: env([#("CI", "true")]))
  |> expect.to_equal(NoColor)
}

pub fn ci_does_not_override_term_dumb_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("CI", "true"), #("TERM", "dumb")]),
  )
  |> expect.to_equal(NoColor)
}

pub fn ci_does_not_override_truecolor_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("CI", "true"), #("COLORTERM", "truecolor")]),
  )
  |> expect.to_equal(TrueColor)
}

pub fn ci_does_not_override_256_test() {
  resolve_color_level(
    is_tty: True,
    env: env([#("CI", "true"), #("TERM", "xterm-256color")]),
  )
  |> expect.to_equal(Ansi256)
}

pub fn default_tty_with_no_hints_is_no_color_test() {
  // Rule 8: an unknown TTY without CI, TERM, or COLORTERM hints is treated
  // as colorless. This matches chalk/supports-color and errs on the side of
  // safety vs. emitting escapes a terminal might not handle.
  resolve_color_level(is_tty: True, env: env([]))
  |> expect.to_equal(NoColor)
}

pub fn ci_distinguishes_from_default_test() {
  // Rule 7 (CI -> Basic) must produce a DIFFERENT outcome from rule 8
  // (default -> NoColor), otherwise the CI check is a no-op.
  let with_ci = resolve_color_level(is_tty: True, env: env([#("CI", "true")]))
  let without_ci = resolve_color_level(is_tty: True, env: env([]))
  expect.to_equal(with_ci, Basic)
  expect.to_equal(without_ci, NoColor)
}

pub fn force_color_false_disables_test() {
  resolve_color_level(is_tty: True, env: env([#("FORCE_COLOR", "false")]))
  |> expect.to_equal(NoColor)
}

pub fn force_color_true_enables_basic_test() {
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "true")]))
  |> expect.to_equal(Basic)
}

pub fn force_color_is_case_insensitive_test() {
  resolve_color_level(is_tty: True, env: env([#("FORCE_COLOR", "FALSE")]))
  |> expect.to_equal(NoColor)
  resolve_color_level(is_tty: False, env: env([#("FORCE_COLOR", "True")]))
  |> expect.to_equal(Basic)
}
