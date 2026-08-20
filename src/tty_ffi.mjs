// FFI for the JavaScript target.
//
// Each export guards against `process` being undefined (Deno without
// node-compat, browsers, Workers) so failures degrade to "not a TTY" /
// "env unset" rather than throwing a ReferenceError into Gleam code.

import { Error as GleamError, Ok } from "./gleam.mjs";

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

// Returns a Gleam Result(String, Nil), matching the Erlang FFI contract.
export function getEnv(name) {
  if (!hasProcess() || !process.env) return new GleamError(undefined);

  const value = process.env[name];
  return typeof value === "string"
    ? new Ok(value)
    : new GleamError(undefined);
}
