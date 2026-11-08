import gleam/list
import tty.{Ansi256, Basic, NoColor, TrueColor}
import tty/env_probe
import tty/resolve_color_level

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

fn resolve(
  is_tty is_tty: Bool,
  env env: fn(String) -> Result(String, Nil),
) -> tty.ColorLevel {
  case resolve_color_level.resolve_color_level(is_tty: is_tty, env: env) {
    0 -> NoColor
    1 -> Basic
    2 -> Ansi256
    3 -> TrueColor
    _ -> panic as "resolver returned a rank outside the documented 0..3 range"
  }
}

pub fn no_color_disables_everything_test() {
  assert resolve(
      is_tty: True,
      env: env([#("NO_COLOR", "1"), #("FORCE_COLOR", "3")]),
    )
    == NoColor
}

pub fn empty_no_color_falls_through_to_default_test() {
  // Per no-color.org, only NON-empty NO_COLOR disables. With no other hints
  // we fall to the default (rule 8) which is now NoColor.
  assert resolve(is_tty: True, env: env([#("NO_COLOR", "")])) == NoColor
}

pub fn force_color_zero_disables_test() {
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "0")])) == NoColor
}

pub fn force_color_one_enables_basic_even_without_tty_test() {
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "1")])) == Basic
}

pub fn force_color_empty_enables_basic_test() {
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "")])) == Basic
}

pub fn force_color_two_enables_256_test() {
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "2")])) == Ansi256
}

pub fn force_color_three_enables_truecolor_test() {
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "3")])) == TrueColor
}

pub fn non_tty_yields_no_color_test() {
  assert resolve(is_tty: False, env: env([])) == NoColor
}

pub fn term_dumb_yields_no_color_test() {
  assert resolve(is_tty: True, env: env([#("TERM", "dumb")])) == NoColor
}

pub fn colorterm_truecolor_yields_truecolor_test() {
  assert resolve(
      is_tty: True,
      env: env([#("COLORTERM", "truecolor"), #("TERM", "xterm")]),
    )
    == TrueColor
}

pub fn colorterm_24bit_yields_truecolor_test() {
  assert resolve(is_tty: True, env: env([#("COLORTERM", "24bit")])) == TrueColor
}

pub fn colorterm_truecolor_is_case_insensitive_test() {
  assert resolve(is_tty: True, env: env([#("COLORTERM", "TrueColor")]))
    == TrueColor
}

pub fn colorterm_non_truecolor_falls_through_to_256_test() {
  // A COLORTERM that is neither `truecolor` nor `24bit` must NOT imply
  // truecolor; resolution falls through to the TERM/CI rules. Here TERM
  // contains 256, so the result is Ansi256.
  assert resolve(
      is_tty: True,
      env: env([#("COLORTERM", "8bit"), #("TERM", "xterm-256color")]),
    )
    == Ansi256
}

pub fn colorterm_non_truecolor_falls_through_to_ci_test() {
  // COLORTERM is non-truecolor and TERM lacks 256, so resolution continues to
  // the CI rule (Basic).
  assert resolve(
      is_tty: True,
      env: env([#("COLORTERM", "8bit"), #("TERM", "xterm"), #("CI", "true")]),
    )
    == Basic
}

pub fn colorterm_non_truecolor_with_no_hints_is_no_color_test() {
  // COLORTERM non-truecolor, TERM present but not 256, no CI: falls through to
  // the safe default (NoColor).
  assert resolve(
      is_tty: True,
      env: env([#("COLORTERM", "8bit"), #("TERM", "xterm")]),
    )
    == NoColor
}

pub fn term_with_256_yields_ansi256_test() {
  assert resolve(is_tty: True, env: env([#("TERM", "xterm-256color")]))
    == Ansi256
}

pub fn ci_yields_basic_test() {
  assert resolve(is_tty: True, env: env([#("CI", "true"), #("TERM", "xterm")]))
    == Basic
}

pub fn ci_rule_is_checked_before_default_basic_test() {
  env_probe.reset()

  assert resolve(
      is_tty: True,
      env: probed_env([#("CI", "true"), #("TERM", "vt100")]),
    )
    == Basic

  assert env_probe.seen("CI")
}

pub fn ci_does_not_override_no_color_test() {
  assert resolve(is_tty: True, env: env([#("CI", "true"), #("NO_COLOR", "1")]))
    == NoColor
}

pub fn ci_does_not_override_force_color_test() {
  assert resolve(
      is_tty: True,
      env: env([#("CI", "true"), #("FORCE_COLOR", "2")]),
    )
    == Ansi256
}

pub fn ci_does_not_override_non_tty_test() {
  assert resolve(is_tty: False, env: env([#("CI", "true")])) == NoColor
}

pub fn ci_does_not_override_term_dumb_test() {
  assert resolve(is_tty: True, env: env([#("CI", "true"), #("TERM", "dumb")]))
    == NoColor
}

pub fn ci_does_not_override_truecolor_test() {
  assert resolve(
      is_tty: True,
      env: env([#("CI", "true"), #("COLORTERM", "truecolor")]),
    )
    == TrueColor
}

pub fn ci_does_not_override_256_test() {
  assert resolve(
      is_tty: True,
      env: env([#("CI", "true"), #("TERM", "xterm-256color")]),
    )
    == Ansi256
}

pub fn default_tty_with_no_hints_is_no_color_test() {
  // Rule 8: an unknown TTY without CI, TERM, or COLORTERM hints is treated
  // as colorless. This matches chalk/supports-color and errs on the side of
  // safety vs. emitting escapes a terminal might not handle.
  assert resolve(is_tty: True, env: env([])) == NoColor
}

pub fn ci_distinguishes_from_default_test() {
  // Rule 7 (CI -> Basic) must produce a DIFFERENT outcome from rule 8
  // (default -> NoColor), otherwise the CI check is a no-op.
  let with_ci = resolve(is_tty: True, env: env([#("CI", "true")]))
  let without_ci = resolve(is_tty: True, env: env([]))
  assert with_ci == Basic
  assert without_ci == NoColor
}

pub fn force_color_false_disables_test() {
  assert resolve(is_tty: True, env: env([#("FORCE_COLOR", "false")])) == NoColor
}

pub fn force_color_true_enables_basic_test() {
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "true")])) == Basic
}

pub fn force_color_is_case_insensitive_test() {
  assert resolve(is_tty: True, env: env([#("FORCE_COLOR", "FALSE")])) == NoColor
  assert resolve(is_tty: False, env: env([#("FORCE_COLOR", "True")])) == Basic
}
