@target(erlang)
import startest/expect

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_name_returns_error")
fn invalid_env_name_returns_error() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_value_returns_error")
fn invalid_env_value_returns_error() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "osc_non_tty_has_no_side_effects")
fn osc_non_tty_has_no_side_effects() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "osc_success_restores_and_stops_at_terminator")
fn osc_success_restores_and_stops_at_terminator() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "osc_timeout_is_bounded_and_restores")
fn osc_timeout_is_bounded_and_restores() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "osc_failures_and_exception_restore")
fn osc_failures_and_exception_restore() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "osc_whole_call_timeout_is_bounded")
fn osc_whole_call_timeout_is_bounded() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "osc_real_tty_handles_bare_reply")
fn osc_real_tty_handles_bare_reply() -> Bool

@target(erlang)
pub fn invalid_env_name_returns_error_test() {
  invalid_env_name_returns_error()
  |> expect.to_be_true
}

@target(erlang)
pub fn invalid_env_value_returns_error_test() {
  invalid_env_value_returns_error()
  |> expect.to_be_true
}

@target(erlang)
pub fn osc_non_tty_has_no_side_effects_test() {
  osc_non_tty_has_no_side_effects()
  |> expect.to_be_true
}

@target(erlang)
pub fn osc_success_restores_and_stops_at_terminator_test() {
  osc_success_restores_and_stops_at_terminator()
  |> expect.to_be_true
}

@target(erlang)
pub fn osc_timeout_is_bounded_and_restores_test() {
  osc_timeout_is_bounded_and_restores()
  |> expect.to_be_true
}

@target(erlang)
pub fn osc_failures_and_exception_restore_test() {
  osc_failures_and_exception_restore()
  |> expect.to_be_true
}

@target(erlang)
pub fn osc_whole_call_timeout_is_bounded_test() {
  osc_whole_call_timeout_is_bounded()
  |> expect.to_be_true
}

@target(erlang)
pub fn osc_real_tty_handles_bare_reply_test() {
  osc_real_tty_handles_bare_reply()
  |> expect.to_be_true
}

@target(javascript)
pub fn erlang_ffi_contract_tests_are_not_available() -> Nil {
  Nil
}
