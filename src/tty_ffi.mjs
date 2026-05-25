// FFI for the JavaScript target.
//
// Each export guards against `process` being undefined (Deno without
// node-compat, browsers, Workers) so failures degrade to "not a TTY" /
// "env unset" rather than throwing a ReferenceError into Gleam code.

function hasProcess() {
  return typeof process !== "undefined" && process !== null;
}

function streamIsTty(name) {
  return hasProcess() && Boolean(process[name] && process[name].isTTY);
}

export function stdinIsTty() {
  return streamIsTty("stdin");
}

export function stdoutIsTty() {
  return streamIsTty("stdout");
}

export function stderrIsTty() {
  return streamIsTty("stderr");
}

// Returns the env-var value or `undefined`. The Gleam side decodes this
// `Dynamic` into a `Result(String, Nil)`.
export function getEnv(name) {
  if (!hasProcess() || !process.env) return undefined;
  return process.env[name];
}
