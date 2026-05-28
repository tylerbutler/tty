// Test-only helper to mutate real process environment variables so that the
// production `get_env` FFI can be exercised end-to-end through
// `tty.detect_color_level`.

@target(erlang)
@external(erlang, "tty_env_mutate_ffi", "set_env")
fn do_set_env(name: String, value: String) -> Nil

@target(javascript)
@external(javascript, "./env_mutate_ffi.mjs", "setEnv")
fn do_set_env(name: String, value: String) -> Nil

@target(erlang)
@external(erlang, "tty_env_mutate_ffi", "unset_env")
fn do_unset_env(name: String) -> Nil

@target(javascript)
@external(javascript, "./env_mutate_ffi.mjs", "unsetEnv")
fn do_unset_env(name: String) -> Nil

pub fn set_env(name: String, value: String) -> Nil {
  do_set_env(name, value)
}

pub fn unset_env(name: String) -> Nil {
  do_unset_env(name)
}
