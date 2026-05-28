@target(javascript)
import startest/expect

@target(javascript)
@external(javascript, "./noprocess_probe_ffi.mjs", "degradesWithoutProcess")
fn degrades_without_process() -> Bool

// Verifies the documented JS fallback: in a runtime without `process`/
// `process.env`, env lookups are treated as unset and `is_tty` returns False
// instead of throwing. This is the main reason the JS FFI guards exist.
@target(javascript)
pub fn js_ffi_degrades_when_process_absent_test() {
  degrades_without_process()
  |> expect.to_be_true
}

@target(erlang)
pub fn js_no_process_probe_is_not_available() -> Nil {
  Nil
}
