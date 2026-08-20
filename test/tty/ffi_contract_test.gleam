import startest/expect

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_name_returns_error")
fn invalid_env_name_returns_error() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_value_returns_error")
fn invalid_env_value_returns_error() -> Bool

@target(javascript)
@external(javascript, "./osc_transport_probe_ffi.mjs", "rejectsUnsupportedTransportsWithoutMutation")
fn rejects_unsupported_transports_without_mutation() -> Bool

@target(javascript)
@external(javascript, "./osc_transport_probe_ffi.mjs", "readsTerminatedResponsesAndRestoresMode")
fn reads_terminated_responses_and_restores_mode() -> Bool

@target(javascript)
@external(javascript, "./osc_transport_probe_ffi.mjs", "restoresModeOnEveryFailure")
fn restores_mode_on_every_failure() -> Bool

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

@target(javascript)
pub fn unsupported_js_osc_transports_do_not_mutate_terminal_test() {
  rejects_unsupported_transports_without_mutation()
  |> expect.to_be_true
}

@target(javascript)
pub fn js_osc_transport_reads_to_terminator_and_restores_mode_test() {
  reads_terminated_responses_and_restores_mode()
  |> expect.to_be_true
}

@target(javascript)
pub fn js_osc_transport_restores_mode_on_failure_test() {
  restores_mode_on_every_failure()
  |> expect.to_be_true
}
