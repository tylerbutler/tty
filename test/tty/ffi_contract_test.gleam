@target(erlang)
import startest/expect

@target(erlang)
@external(erlang, "tty_ffi_contract_probe", "invalid_env_name_returns_error")
fn invalid_env_name_returns_error() -> Bool

@target(erlang)
pub fn invalid_env_name_returns_error_test() {
  invalid_env_name_returns_error()
  |> expect.to_be_true
}

@target(javascript)
pub fn erlang_ffi_contract_tests_are_not_available() -> Nil {
  Nil
}
