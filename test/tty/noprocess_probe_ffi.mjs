import { getEnv, stdinIsTty } from "../tty_ffi.mjs";

// Temporarily removes the global `process` to simulate a non-Node runtime
// (browser, Worker, Deno without node-compat) and verifies the FFI degrades to
// "env unset" / "not a TTY" rather than throwing a ReferenceError. The body is
// fully synchronous, so no other test code can observe the swapped-out global,
// and `process` is always restored via `finally`.
export function degradesWithoutProcess() {
  const saved = globalThis.process;
  try {
    globalThis.process = undefined;
    return getEnv("PATH") === undefined && stdinIsTty() === false;
  } finally {
    globalThis.process = saved;
  }
}
