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
  chunks = [],
  initialRaw = false,
  nodeVersion = "20.0.0",
  onClock,
  onRead,
  onSetRawMode,
  onWrite,
} = {}) {
  let now = 0n;
  const rawModes = [];
  const writes = [];
  const stdin = {
    isTTY: true,
    isRaw: initialRaw,
    readableFlowing: false,
    read() {
      if (onRead) return onRead();
      return chunks.length === 0 ? null : chunks.shift();
    },
    setRawMode(mode) {
      rawModes.push(mode);
      stdin.isRaw = mode;
      if (onSetRawMode) onSetRawMode(mode);
    },
  };
  const stdout = {
    isTTY: true,
    write(value) {
      writes.push(value);
      if (onWrite) return onWrite(value);
      return true;
    },
  };

  return {
    process: {
      versions: { node: nodeVersion },
      hrtime: {
        bigint() {
          if (onClock) return onClock();
          now += 1_000_000n;
          return now;
        },
      },
      stdin,
      stdout,
      stderr: { ...stdout },
    },
    rawModes,
    writes,
  };
}

export function rejectsUnsupportedTransportsWithoutMutation() {
  const missingRead = mockProcess();
  delete missingRead.process.stdin.read;

  const unpaused = mockProcess();
  unpaused.process.stdin.readableFlowing = null;

  const missingClock = mockProcess();
  delete missingClock.process.hrtime;

  const nonTtyOutput = mockProcess();
  nonTtyOutput.process.stdout.isTTY = false;

  const malformed = mockProcess();
  Object.defineProperty(malformed.process.stdin, "isRaw", {
    get() {
      throw new Error("malformed raw state");
    },
  });

  const probes = [
    mockProcess({ nodeVersion: "19.9.0" }),
    missingRead,
    unpaused,
    missingClock,
    nonTtyOutput,
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
    invalidArguments.writes.length === 0;

  return (
    withProcess({}, () => queryOsc11("stdout", 100) === undefined) &&
    probes.every(
      (probe) =>
        withProcess(
          probe.process,
          () => queryOsc11("stdout", 100) === undefined,
        ) &&
        probe.rawModes.length === 0 &&
        probe.writes.length === 0,
    ) &&
    invalidArgumentsRejected
  );
}

export function readsTerminatedResponsesAndRestoresMode() {
  const bel = mockProcess({
    chunks: [RESPONSE.slice(0, 12), `${RESPONSE.slice(12)}\x07ignored`],
  });
  const belResult = withProcess(bel.process, () =>
    queryOsc11("stdout", 100),
  );

  const st = mockProcess({
    chunks: [RESPONSE, "\x1b", "\\ignored"],
    initialRaw: true,
  });
  const stResult = withProcess(st.process, () =>
    queryOsc11("stdout", 100),
  );

  return (
    belResult === `${RESPONSE}\x07` &&
    stResult === `${RESPONSE}\x1b\\` &&
    bel.writes.join("") === "\x1b]11;?\x07" &&
    st.writes.join("") === "\x1b]11;?\x07" &&
    bel.rawModes.join(",") === "true,false" &&
    st.rawModes.join(",") === "true,true" &&
    bel.process.stdin.isRaw === false &&
    st.process.stdin.isRaw === true
  );
}

export function restoresModeOnEveryFailure() {
  const timeout = mockProcess();
  const timeoutResult = withProcess(timeout.process, () =>
    queryOsc11("stdout", 5),
  );

  const writeFailure = mockProcess({
    onWrite() {
      throw new Error("write failed");
    },
  });
  const writeResult = withProcess(writeFailure.process, () =>
    queryOsc11("stdout", 100),
  );

  const readFailure = mockProcess({
    onRead() {
      throw new Error("read failed");
    },
  });
  const readResult = withProcess(readFailure.process, () =>
    queryOsc11("stdout", 100),
  );

  const rejectedWrite = mockProcess({
    onWrite() {
      return false;
    },
  });
  const rejectedWriteResult = withProcess(rejectedWrite.process, () =>
    queryOsc11("stdout", 100),
  );

  let clockReads = 0;
  const malformedClock = mockProcess({
    onClock() {
      clockReads += 1;
      return clockReads === 1 ? 0n : "invalid";
    },
  });
  const malformedClockResult = withProcess(malformedClock.process, () =>
    queryOsc11("stdout", 100),
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
  const modeResult = withProcess(modeFailure.process, () =>
    queryOsc11("stdout", 100),
  );

  const restoreFailure = mockProcess({
    onSetRawMode(mode) {
      if (mode === false) throw new Error("mode restore failed");
    },
  });
  const restoreResult = withProcess(restoreFailure.process, () =>
    queryOsc11("stdout", 100),
  );

  return [
    timeout,
    writeFailure,
    readFailure,
    rejectedWrite,
    malformedClock,
    modeFailure,
    restoreFailure,
  ].every(
    (probe) =>
      probe.process.stdin.isRaw === false &&
      probe.rawModes.join(",") === "true,false",
  ) &&
    timeoutResult === undefined &&
    writeResult === undefined &&
    readResult === undefined &&
    rejectedWriteResult === undefined &&
    malformedClockResult === undefined &&
    modeResult === undefined &&
    restoreResult === undefined;
}
