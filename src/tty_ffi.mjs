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
const MAX_OSC_TIMEOUT_MS = 100;
const STREAM_FILE_DESCRIPTORS = { stdin: 0, stdout: 1, stderr: 2 };

const nodeChildProcess =
  hasProcess() && typeof process.versions?.node === "string"
    ? await import("node:child_process").catch(() => undefined)
    : undefined;

function isSupportedNode(runtime) {
  if (!runtime || typeof runtime.versions?.node !== "string") return false;
  const match = /^(\d+)\./.exec(runtime.versions.node);
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

export const osc11WorkerSource = `
import fs from "node:fs";

const outputFd = Number(process.argv[1]);
const timeoutMs = Number(process.argv[2]);
const query = ${JSON.stringify(OSC_11_QUERY)};
const maxResponseLength = ${MAX_OSC_RESPONSE_LENGTH};
let raw = "";
let finished = false;
let timer;

function terminatedResponse(response) {
  const bel = response.indexOf("\\x07");
  const st = response.indexOf("\\x1b\\\\");
  let end = -1;

  if (bel >= 0 && st >= 0) end = Math.min(bel + 1, st + 2);
  else if (bel >= 0) end = bel + 1;
  else if (st >= 0) end = st + 2;

  return end < 0 ? undefined : response.slice(0, end);
}

function finish(response) {
  if (finished) return;
  finished = true;
  clearTimeout(timer);

  if (response !== undefined) {
    fs.writeSync(3, Buffer.from(response, "latin1"));
  }
  process.exit(0);
}

process.stdin.setEncoding("latin1");
process.stdin.on("data", (chunk) => {
  raw += chunk;
  if (raw.length > maxResponseLength) return finish();

  const complete = terminatedResponse(raw);
  if (complete !== undefined) finish(complete);
});
process.stdin.on("end", () => finish());
process.stdin.on("error", () => finish());
process.stdin.resume();

timer = setTimeout(() => finish(), timeoutMs);

try {
  fs.writeSync(outputFd, Buffer.from(query, "latin1"));
} catch {
  finish();
}
`;

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

export function queryOsc11WithRuntime(
  streamName,
  timeoutMs,
  runtime,
  spawnSync,
) {
  if (
    !isSupportedNode(runtime) ||
    !["stdin", "stdout", "stderr"].includes(streamName) ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs <= 0 ||
    timeoutMs > MAX_OSC_TIMEOUT_MS ||
    typeof spawnSync !== "function"
  ) {
    return undefined;
  }

  const stdin = runtime.stdin;
  const output = runtime[streamName];
  if (
    !stdin ||
    !output ||
    stdin.isTTY !== true ||
    output.isTTY !== true ||
    typeof stdin.isRaw !== "boolean" ||
    typeof stdin.setRawMode !== "function" ||
    typeof runtime.execPath !== "string"
  ) {
    return undefined;
  }

  const previousRawMode = stdin.isRaw;
  let response;

  try {
    stdin.setRawMode(true);
    const child = spawnSync(
      runtime.execPath,
      [
        "--input-type=module",
        "--eval",
        osc11WorkerSource,
        String(STREAM_FILE_DESCRIPTORS[streamName]),
        String(timeoutMs),
      ],
      {
        encoding: "latin1",
        killSignal: "SIGKILL",
        maxBuffer: MAX_OSC_RESPONSE_LENGTH,
        stdio: ["inherit", "inherit", "inherit", "pipe"],
        timeout: timeoutMs,
        windowsHide: true,
      },
    );
    if (
      child?.status !== 0 ||
      child.signal !== null ||
      child.error !== undefined
    ) {
      return undefined;
    }

    const raw = chunkToString(child.output?.[3]);
    if (!raw || raw.length > MAX_OSC_RESPONSE_LENGTH) return undefined;
    response = terminatedResponse(raw);
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

// A short-lived child owns the asynchronous read while spawnSync bounds the
// synchronous public API. The parent always restores its original raw mode.
export function queryOsc11(streamName, timeoutMs) {
  try {
    return queryOsc11WithRuntime(
      streamName,
      timeoutMs,
      process,
      nodeChildProcess?.spawnSync,
    );
  } catch {
    return undefined;
  }
}
