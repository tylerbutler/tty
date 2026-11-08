@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_name_returns_error")
fn invalid_env_name_returns_error() -> Bool

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_value_returns_error")
fn invalid_env_value_returns_error() -> Bool

@target(erlang)
pub fn invalid_env_name_returns_error_test() {
  assert invalid_env_name_returns_error()
}

@target(erlang)
pub fn invalid_env_value_returns_error_test() {
  assert invalid_env_value_returns_error()
}

@target(javascript)
pub fn erlang_ffi_contract_tests_are_not_available() -> Nil {
  Nil
}
