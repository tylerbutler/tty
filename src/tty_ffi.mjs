// FFI for the JavaScript target.
//
// Each export guards against `process` being undefined (Deno without
// node-compat, browsers, Workers) so failures degrade to "not a TTY" /
// "env unset" rather than throwing a ReferenceError into Gleam code.

function hasProcess() {
  return typeof process !== "undefined" && process !== null;
}

export function stdinIsTty() {
  return hasProcess() && Boolean(process.stdin && process.stdin.isTTY);
}

export function stdoutIsTty() {
  return hasProcess() && Boolean(process.stdout && process.stdout.isTTY);
}

export function stderrIsTty() {
  return hasProcess() && Boolean(process.stderr && process.stderr.isTTY);
}

// Returns the env-var value or `undefined`. The Gleam side decodes this
// `Dynamic` into a `Result(String, Nil)`.
export function getEnv(name) {
  if (!hasProcess() || !process.env) return undefined;
  return process.env[name];
}
