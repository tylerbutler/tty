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

const OSC_11_QUERY = "\x1b]11;?\x07";
const MAX_OSC_RESPONSE_LENGTH = 4096;
const MAX_OSC_TIMEOUT_MS = 1000;

function isSupportedNode() {
  if (!hasProcess() || typeof process.versions?.node !== "string") return false;
  const match = /^(\d+)\./.exec(process.versions.node);
  return match !== null && Number(match[1]) >= 20;
}

function chunkToString(chunk) {
  if (typeof chunk === "string") return chunk;
  if (!(chunk instanceof Uint8Array)) return undefined;

  let value = "";
  for (const byte of chunk) value += String.fromCharCode(byte);
  return value;
}

function terminatedResponse(response) {
  const bel = response.indexOf("\x07");
  const st = response.indexOf("\x1b\\");
  let end = -1;

  if (bel >= 0 && st >= 0) end = Math.min(bel + 1, st + 2);
  else if (bel >= 0) end = bel + 1;
  else if (st >= 0) end = st + 2;

  return end < 0 ? undefined : response.slice(0, end);
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

// Runs synchronously so the caller never regains control while raw mode is
// active. A paused Node Readable's read() is nonblocking; hosts without that
// bounded path are rejected before terminal state is changed.
export function queryOsc11(streamName, timeoutMs) {
  const clock = globalThis.performance;
  if (
    !isSupportedNode() ||
    !["stdin", "stdout", "stderr"].includes(streamName) ||
    !Number.isFinite(timeoutMs) ||
    timeoutMs < 0 ||
    timeoutMs > MAX_OSC_TIMEOUT_MS ||
    typeof clock?.now !== "function"
  ) {
    return undefined;
  }

  const stdin = process.stdin;
  const output = process[streamName];
  if (
    !stdin ||
    !output ||
    stdin.isTTY !== true ||
    output.isTTY !== true ||
    typeof stdin.isRaw !== "boolean" ||
    typeof stdin.setRawMode !== "function" ||
    typeof stdin.read !== "function" ||
    (stdin.readableFlowing !== false && stdin.readableFlowing !== null) ||
    typeof output.write !== "function"
  ) {
    return undefined;
  }

  const startedAt = clock.now();
  if (!Number.isFinite(startedAt)) return undefined;

  const previousRawMode = stdin.isRaw;
  let response;

  try {
    stdin.setRawMode(true);
    if (output.write(OSC_11_QUERY) === false) return undefined;

    const deadline = startedAt + timeoutMs;
    let raw = "";
    while (clock.now() < deadline) {
      const chunk = stdin.read();
      if (chunk !== null && chunk !== undefined) {
        const text = chunkToString(chunk);
        if (text === undefined) return undefined;

        raw += text;
        if (raw.length > MAX_OSC_RESPONSE_LENGTH) return undefined;

        const complete = terminatedResponse(raw);
        if (complete !== undefined) {
          response = complete;
          break;
        }
      }
    }
  } catch {
    response = undefined;
  } finally {
    try {
      stdin.setRawMode(previousRawMode);
    } catch {
      response = undefined;
    }
  }

  return response;
}
