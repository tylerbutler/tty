import { queryOsc11 } from "../tty_ffi.mjs";

const RESPONSE = "\x1b]11;rgb:ffff/ffff/ffff";

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
  onSetRawMode,
  onSpawn,
  response = `${RESPONSE}\x07`,
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

  return {
    process: {
      versions: { node: nodeVersion },
      execPath: "/mock/node",
      getBuiltinModule(name) {
        if (name !== "child_process") return undefined;
        return {
          spawnSync(executable, arguments_, options) {
            spawns.push({ executable, arguments_, options });
            if (onSpawn) return onSpawn();
            return {
              error: undefined,
              output: [null, null, null, response],
              signal: null,
              status: 0,
            };
          },
        };
      },
      stdin,
      stdout,
      stderr: { ...stdout },
    },
    rawModes,
    spawns,
  };
}

export function rejectsUnsupportedTransportsWithoutMutation() {
  const missingRawMode = mockProcess();
  delete missingRawMode.process.stdin.setRawMode;

  const nonTtyOutput = mockProcess();
  nonTtyOutput.process.stdout.isTTY = false;

  const missingSpawn = mockProcess();
  missingSpawn.process.getBuiltinModule = () => undefined;

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
    missingSpawn,
    malformed,
  ];

  const invalidArguments = mockProcess();
  const invalidArgumentsRejected =
    withProcess(invalidArguments.process, () => {
      return (
        queryOsc11("unknown", 100) === undefined &&
        queryOsc11("stdout", 0) === undefined &&
        queryOsc11("stdout", 101) === undefined
      );
    }) &&
    invalidArguments.rawModes.length === 0 &&
    invalidArguments.spawns.length === 0;

  return (
    withProcess({}, () => queryOsc11("stdout", 100) === undefined) &&
    probes.every(
      (probe) =>
        withProcess(
          probe.process,
          () => queryOsc11("stdout", 100) === undefined,
        ) &&
        probe.rawModes.length === 0 &&
        probe.spawns.length === 0,
    ) &&
    invalidArgumentsRejected
  );
}

export function readsTerminatedResponsesAndRestoresMode() {
  const bel = mockProcess({
    response: `${RESPONSE}\x07ignored`,
  });
  const belResult = withProcess(bel.process, () =>
    queryOsc11("stdout", 100),
  );

  const st = mockProcess({
    initialRaw: true,
    response: `${RESPONSE}\x1b\\ignored`,
  });
  const stResult = withProcess(st.process, () =>
    queryOsc11("stdout", 100),
  );

  return (
    belResult === `${RESPONSE}\x07` &&
    stResult === `${RESPONSE}\x1b\\` &&
    bel.spawns[0].executable === "/mock/node" &&
    bel.spawns[0].arguments_.slice(-2).join(",") === "stdout,100" &&
    bel.spawns[0].options.stdio.join(",") === "inherit,inherit,inherit,pipe" &&
    bel.rawModes.join(",") === "false" &&
    st.rawModes.join(",") === "true" &&
    bel.process.stdin.isRaw === false &&
    st.process.stdin.isRaw === true
  );
}

export function restoresModeOnEveryFailure() {
  const timeout = mockProcess({
    onSpawn() {
      return {
        error: new Error("timed out"),
        output: [null, null, null, null],
        signal: "SIGTERM",
        status: null,
      };
    },
  });
  const timeoutResult = withProcess(timeout.process, () =>
    queryOsc11("stdout", 5),
  );

  const spawnFailure = mockProcess({
    onSpawn() {
      throw new Error("spawn failed");
    },
  });
  const spawnResult = withProcess(spawnFailure.process, () =>
    queryOsc11("stdout", 100),
  );

  const emptyResponse = mockProcess({
    response: "",
  });
  const emptyResult = withProcess(emptyResponse.process, () =>
    queryOsc11("stdout", 100),
  );

  const oversizedResponse = mockProcess({
    response: "x".repeat(4097),
  });
  const oversizedResult = withProcess(oversizedResponse.process, () =>
    queryOsc11("stdout", 100),
  );

  const malformedResult = mockProcess({
    onSpawn() {
      return {};
    },
  });
  const malformedResponse = withProcess(malformedResult.process, () =>
    queryOsc11("stdout", 100),
  );

  const restoreFailure = mockProcess({
    onSetRawMode() {
      throw new Error("mode restore failed");
    },
  });
  const restoreResult = withProcess(restoreFailure.process, () =>
    queryOsc11("stdout", 100),
  );

  return [
    timeout,
    spawnFailure,
    emptyResponse,
    oversizedResponse,
    malformedResult,
    restoreFailure,
  ].every(
    (probe) =>
      probe.process.stdin.isRaw === false &&
      probe.rawModes.join(",") === "false",
  ) &&
    timeoutResult === undefined &&
    spawnResult === undefined &&
    emptyResult === undefined &&
    oversizedResult === undefined &&
    malformedResponse === undefined &&
    restoreResult === undefined;
}

export function receivesScheduledResponseInChildProcess() {
  const childProcess = process.getBuiltinModule?.("child_process");
  if (typeof childProcess?.spawnSync !== "function") return false;

  const ffiUrl = new URL("../tty_ffi.mjs", import.meta.url).href;
  const script = `
    import { EventEmitter } from "node:events";
    import { runOscQueryChild } from ${JSON.stringify(ffiUrl)};

    const rawModes = [];
    const writes = [];
    let resumed = false;
    let paused = false;

    class Input extends EventEmitter {
      isRaw = false;
      setRawMode(mode) {
        rawModes.push(mode);
        this.isRaw = mode;
      }
      resume() { resumed = true; }
      pause() { paused = true; }
    }

    const stdin = new Input();
    const runtime = {
      stdin,
      stdout: {
        write(value) {
          writes.push(value);
          setTimeout(
            () => stdin.emit("data", Buffer.from(${JSON.stringify(`${RESPONSE}\x07`)})),
            5,
          );
        },
      },
      getBuiltinModule(name) {
        if (name !== "fs") return undefined;
        return {
          writeSync(fd, response) {
            console.log(JSON.stringify({
              fd,
              paused,
              rawModes,
              response,
              resumed,
              writes,
            }));
          },
        };
      },
    };

    runOscQueryChild(runtime, "stdout", 50);
  `;
  const result = childProcess.spawnSync(
    process.execPath,
    ["--input-type=module", "--eval", script],
    { encoding: "utf8", timeout: 1000 },
  );
  if (result.status !== 0 || result.signal !== null) return false;

  try {
    const probe = JSON.parse(result.stdout.trim());
    return (
      probe.fd === 3 &&
      probe.paused === true &&
      probe.rawModes.join(",") === "true,false" &&
      probe.response === `${RESPONSE}\x07` &&
      probe.resumed === true &&
      probe.writes.join("") === "\x1b]11;?\x07"
    );
  } catch {
    return false;
  }
}
