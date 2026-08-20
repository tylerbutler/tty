import { spawnSync as nodeSpawnSync } from "node:child_process";
import {
  osc11WorkerSource,
  queryOsc11,
  queryOsc11WithRuntime,
} from "../tty_ffi.mjs";

const RESPONSE = "\x1b]11;rgb:ffff/ffff/ffff";
const QUERY = "\x1b]11;?\x07";

function withProcess(mock, probe) {
  const saved = globalThis.process;
  try {
    globalThis.process = mock;
    return probe();
  } finally {
    globalThis.process = saved;
  }
}

function mockProcess({
  initialRaw = false,
  nodeVersion = "20.0.0",
  onSpawn,
  onSetRawMode,
} = {}) {
  const rawModes = [];
  const spawns = [];
  const stdin = {
    isTTY: true,
    isRaw: initialRaw,
    readableFlowing: null,
    setRawMode(mode) {
      rawModes.push(mode);
      stdin.isRaw = mode;
      if (onSetRawMode) onSetRawMode(mode);
    },
  };
  const stdout = { isTTY: true };
  const process = {
    execPath: "/mock/node",
    versions: { node: nodeVersion },
    stdin,
    stdout,
    stderr: { ...stdout },
  };
  const spawnSync = (...args) => {
    spawns.push(args);
    if (onSpawn) return onSpawn(...args);
    return { error: undefined, output: [null, null, null, ""], signal: null, status: 0 };
  };

  return {
    process,
    rawModes,
    spawns,
    spawnSync,
  };
}

export function rejectsUnsupportedTransportsWithoutMutation() {
  const missingRawMode = mockProcess();
  delete missingRawMode.process.stdin.setRawMode;

  const nonTtyOutput = mockProcess();
  nonTtyOutput.process.stdout.isTTY = false;

  const missingExecutable = mockProcess();
  delete missingExecutable.process.execPath;

  const malformed = mockProcess();
  Object.defineProperty(malformed.process.stdin, "isRaw", {
    get() {
      throw new Error("malformed raw state");
    },
  });

  const probes = [
    mockProcess({ nodeVersion: "19.9.0" }),
    missingRawMode,
    nonTtyOutput,
    missingExecutable,
  ];

  const invalidArguments = mockProcess();
  const invalidArgumentsRejected = [
    ["unknown", 100],
    ["stdout", 0],
    ["stdout", 101],
  ].every(
    ([stream, timeout]) =>
      queryOsc11WithRuntime(
        stream,
        timeout,
        invalidArguments.process,
        invalidArguments.spawnSync,
      ) === undefined,
  ) &&
    invalidArguments.rawModes.length === 0 &&
    invalidArguments.spawns.length === 0;

  return (
    withProcess({}, () => queryOsc11("stdout", 100) === undefined) &&
    withProcess(
      malformed.process,
      () => queryOsc11("stdout", 100) === undefined,
    ) &&
    malformed.rawModes.length === 0 &&
    malformed.spawns.length === 0 &&
    probes.every(
      (probe) =>
        queryOsc11WithRuntime(
          "stdout",
          100,
          probe.process,
          probe.spawnSync,
        ) === undefined &&
        probe.rawModes.length === 0 &&
        probe.spawns.length === 0,
    ) &&
    invalidArgumentsRejected
  );
}

export function readsTerminatedResponsesAndRestoresMode() {
  const bel = mockProcess({
    onSpawn() {
      return {
        error: undefined,
        output: [null, null, null, `${RESPONSE}\x07ignored`],
        signal: null,
        status: 0,
      };
    },
  });
  const belResult = queryOsc11WithRuntime(
    "stdout",
    100,
    bel.process,
    bel.spawnSync,
  );

  const st = mockProcess({
    initialRaw: true,
    onSpawn() {
      return {
        error: undefined,
        output: [null, null, null, `${RESPONSE}\x1b\\ignored`],
        signal: null,
        status: 0,
      };
    },
  });
  const stResult = queryOsc11WithRuntime(
    "stdout",
    100,
    st.process,
    st.spawnSync,
  );

  return (
    belResult === `${RESPONSE}\x07` &&
    stResult === `${RESPONSE}\x1b\\` &&
    bel.spawns.length === 1 &&
    st.spawns.length === 1 &&
    bel.rawModes.join(",") === "true,false" &&
    st.rawModes.join(",") === "true,true" &&
    bel.process.stdin.isRaw === false &&
    st.process.stdin.isRaw === true
  );
}

export function supportsFreshTtyAndDelayedResponses() {
  const fresh = mockProcess({
    onSpawn(_executable, args, options) {
      if (
        fresh.process.stdin.isRaw !== true ||
        args.at(-2) !== "1" ||
        args.at(-1) !== "100" ||
        options.timeout !== 100
      ) {
        throw new Error("invalid worker invocation");
      }
      return {
        error: undefined,
        output: [null, null, null, `${RESPONSE}\x07`],
        signal: null,
        status: 0,
      };
    },
  });
  const freshResult = queryOsc11WithRuntime(
    "stdout",
    100,
    fresh.process,
    fresh.spawnSync,
  );

  const harness = `
import { spawn } from "node:child_process";

const workerSource = Buffer.from(process.argv[1], "base64").toString("utf8");
const query = Buffer.from(process.argv[2], "base64").toString("latin1");
const response = Buffer.from(process.argv[3], "base64");
const child = spawn(
  process.execPath,
  ["--input-type=module", "--eval", workerSource, "1", "100"],
  { stdio: ["pipe", "pipe", "inherit", "pipe"] },
);
let queryOutput = "";
let workerResponse = "";
let responseScheduled = false;
const guard = setTimeout(() => process.exit(2), 1000);

child.stdout.setEncoding("latin1");
child.stdio[3].setEncoding("latin1");
child.stdout.on("data", (chunk) => {
  queryOutput += chunk;
  if (!responseScheduled && queryOutput.includes(query)) {
    responseScheduled = true;
    setTimeout(() => child.stdin.write(response), 10);
  }
});
child.stdio[3].on("data", (chunk) => {
  workerResponse += chunk;
});
child.on("close", (code) => {
  clearTimeout(guard);
  const valid =
    code === 0 &&
    responseScheduled &&
    queryOutput === query &&
    workerResponse === response.toString("latin1");
  process.exit(valid ? 0 : 1);
});
`;
  const delayed = nodeSpawnSync(
    process.execPath,
    [
      "--input-type=module",
      "--eval",
      harness,
      Buffer.from(osc11WorkerSource).toString("base64"),
      Buffer.from(QUERY, "latin1").toString("base64"),
      Buffer.from(`${RESPONSE}\x07`, "latin1").toString("base64"),
    ],
    { timeout: 2000 },
  );

  return (
    fresh.process.stdin.readableFlowing === null &&
    freshResult === `${RESPONSE}\x07` &&
    fresh.rawModes.join(",") === "true,false" &&
    delayed.status === 0 &&
    delayed.error === undefined
  );
}

export function restoresModeOnEveryFailure() {
  const timeout = mockProcess();
  const timeoutResult = queryOsc11WithRuntime(
    "stdout",
    5,
    timeout.process,
    timeout.spawnSync,
  );

  const spawnFailure = mockProcess({
    onSpawn() {
      throw new Error("spawn failed");
    },
  });
  const spawnResult = queryOsc11WithRuntime(
    "stdout",
    100,
    spawnFailure.process,
    spawnFailure.spawnSync,
  );

  const childFailure = mockProcess({
    onSpawn() {
      return {
        error: new Error("child failed"),
        output: [null, null, null, ""],
        signal: null,
        status: null,
      };
    },
  });
  const childResult = queryOsc11WithRuntime(
    "stdout",
    100,
    childFailure.process,
    childFailure.spawnSync,
  );

  let firstModeChange = true;
  const modeFailure = mockProcess({
    onSetRawMode() {
      if (firstModeChange) {
        firstModeChange = false;
        throw new Error("mode change failed");
      }
    },
  });
  const modeResult = queryOsc11WithRuntime(
    "stdout",
    100,
    modeFailure.process,
    modeFailure.spawnSync,
  );

  const restoreFailure = mockProcess({
    onSetRawMode(mode) {
      if (mode === false) throw new Error("mode restore failed");
    },
  });
  const restoreResult = queryOsc11WithRuntime(
    "stdout",
    100,
    restoreFailure.process,
    restoreFailure.spawnSync,
  );

  return [
    timeout,
    spawnFailure,
    childFailure,
    modeFailure,
    restoreFailure,
  ].every(
    (probe) =>
      probe.process.stdin.isRaw === false &&
      probe.rawModes.join(",") === "true,false",
  ) &&
    timeoutResult === undefined &&
    spawnResult === undefined &&
    childResult === undefined &&
    modeResult === undefined &&
    restoreResult === undefined;
}
