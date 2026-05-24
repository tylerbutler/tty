// FFI for the JavaScript target.

export function stdinIsTty() {
  return Boolean(process.stdin.isTTY);
}

export function stdoutIsTty() {
  return Boolean(process.stdout.isTTY);
}

export function stderrIsTty() {
  return Boolean(process.stderr.isTTY);
}

// Returns the env-var value or `undefined`. The Gleam side decodes this
// `Dynamic` into a `Result(String, Nil)`.
export function getEnv(name) {
  return process.env[name];
}
