@target(erlang)
@external(erlang, "tty_env_probe_ffi", "reset")
fn do_reset() -> Nil

@target(javascript)
@external(javascript, "./env_probe_ffi.mjs", "reset")
fn do_reset() -> Nil

@target(erlang)
@external(erlang, "tty_env_probe_ffi", "record")
fn do_record(name: String) -> Nil

@target(javascript)
@external(javascript, "./env_probe_ffi.mjs", "record")
fn do_record(name: String) -> Nil

@target(erlang)
@external(erlang, "tty_env_probe_ffi", "seen")
fn do_seen(name: String) -> Bool

@target(javascript)
@external(javascript, "./env_probe_ffi.mjs", "seen")
fn do_seen(name: String) -> Bool

pub fn reset() -> Nil {
  do_reset()
}

pub fn record(name: String) -> Nil {
  do_record(name)
}

pub fn seen(name: String) -> Bool {
  do_seen(name)
}
