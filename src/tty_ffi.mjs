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
const CHILD_STARTUP_TIMEOUT_MS = 250;

function isSupportedNode() {
  if (!hasProcess() || typeof process.versions?.node !== "string") return false;
  const match = /^(\d+)\./.exec(process.versions.node);
  return (
    match !== null &&
    Number(match[1]) >= 20 &&
    typeof process.getBuiltinModule === "function"
  );
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

export function runOscQueryChild(runtime, streamName, timeoutMs) {
  const stdin = runtime.stdin;
  const output = runtime[streamName];
  const fs = runtime.getBuiltinModule?.("fs");
  if (
    !stdin ||
    !output ||
    typeof stdin.isRaw !== "boolean" ||
    typeof stdin.setRawMode !== "function" ||
    typeof stdin.on !== "function" ||
    typeof stdin.off !== "function" ||
    typeof stdin.resume !== "function" ||
    typeof stdin.pause !== "function" ||
    typeof output.write !== "function" ||
    typeof fs?.writeSync !== "function"
  ) {
    return;
  }

  const previousRawMode = stdin.isRaw;
  let raw = "";
  let timer;
  let settled = false;

  const finish = (response) => {
    if (settled) return;
    settled = true;
    if (timer !== undefined) clearTimeout(timer);
    try {
      stdin.off("data", onData);
      stdin.pause();
    } catch {
      response = undefined;
    }

    try {
      stdin.setRawMode(previousRawMode);
    } catch {
      response = undefined;
    }

    if (response !== undefined) {
      try {
        fs.writeSync(3, response);
      } catch {
        // The parent treats a missing response as an unsupported query.
      }
    }
  };

  const onData = (chunk) => {
    const text = chunkToString(chunk);
    if (text === undefined) {
      finish(undefined);
      return;
    }

    raw += text;
    if (raw.length > MAX_OSC_RESPONSE_LENGTH) {
      finish(undefined);
      return;
    }

    const complete = terminatedResponse(raw);
    if (complete !== undefined) finish(complete);
  };

  try {
    stdin.setRawMode(true);
    stdin.on("data", onData);
    stdin.resume();
    timer = setTimeout(() => finish(undefined), timeoutMs);
    output.write(OSC_11_QUERY);
  } catch {
    finish(undefined);
  }
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

function queryOsc11WithProcess(streamName, timeoutMs) {
  if (
    !isSupportedNode() ||
    !["stdin", "stdout", "stderr"].includes(streamName) ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs <= 0 ||
    timeoutMs > MAX_OSC_TIMEOUT_MS
  ) {
    return undefined;
  }

  const stdin = process.stdin;
  const output = process[streamName];
  const childProcess = process.getBuiltinModule("child_process");
  if (
    !stdin ||
    !output ||
    stdin.isTTY !== true ||
    output.isTTY !== true ||
    typeof stdin.isRaw !== "boolean" ||
    typeof stdin.setRawMode !== "function" ||
    typeof process.execPath !== "string" ||
    typeof childProcess?.spawnSync !== "function"
  ) {
    return undefined;
  }

  const previousRawMode = stdin.isRaw;
  const childSource = `
    import { runOscQueryChild } from ${JSON.stringify(import.meta.url)};
    runOscQueryChild(process, process.argv[1], Number(process.argv[2]));
  `;
  let result;

  try {
    result = childProcess.spawnSync(
      process.execPath,
      [
        "--input-type=module",
        "--eval",
        childSource,
        streamName,
        String(timeoutMs),
      ],
      {
        encoding: "utf8",
        maxBuffer: MAX_OSC_RESPONSE_LENGTH,
        stdio: ["inherit", "inherit", "inherit", "pipe"],
        timeout: timeoutMs + CHILD_STARTUP_TIMEOUT_MS,
      },
    );
  } catch {
    result = undefined;
  } finally {
    try {
      stdin.setRawMode(previousRawMode);
    } catch {
      result = undefined;
    }
  }

  if (
    result?.status !== 0 ||
    result.signal !== null ||
    result.error !== undefined
  ) {
    return undefined;
  }

  const response = result.output?.[3];
  if (
    typeof response !== "string" ||
    response.length > MAX_OSC_RESPONSE_LENGTH
  ) {
    return undefined;
  }
  return terminatedResponse(response);
}

// The helper process owns the asynchronous read while this process waits
// synchronously, allowing post-write terminal replies to reach Node's event loop.
export function queryOsc11(streamName, timeoutMs) {
  try {
    return queryOsc11WithProcess(streamName, timeoutMs);
  } catch {
    return undefined;
  }
}
