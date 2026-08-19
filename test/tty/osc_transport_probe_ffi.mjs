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
  onRead,
  onSetRawMode,
  onWrite,
} = {}) {
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
      versions: { node: "20.0.0" },
      stdin,
      stdout,
      stderr: { ...stdout },
    },
    rawModes,
    writes,
  };
}

export function rejectsUnsupportedTransportsWithoutMutation() {
  const cases = [
    {},
    { versions: { node: "19.9.0" } },
    {
      versions: { node: "20.0.0" },
      stdin: { isTTY: false },
      stdout: { isTTY: true, write() {} },
    },
  ];

  const unsupported = mockProcess();
  delete unsupported.process.stdin.read;
  cases.push(unsupported.process);

  return cases.every(
    (candidate) =>
      withProcess(
        candidate,
        () => queryOsc11("stdout", 100) === undefined,
      ) &&
      unsupported.rawModes.length === 0 &&
      unsupported.writes.length === 0,
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
    queryOsc11("stdout", 0),
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

  return [timeout, writeFailure, readFailure, modeFailure].every(
    (probe) =>
      probe.process.stdin.isRaw === false &&
      probe.rawModes.join(",") === "true,false",
  ) &&
    timeoutResult === undefined &&
    writeResult === undefined &&
    readResult === undefined &&
    modeResult === undefined;
}
