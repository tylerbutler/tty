function hasEnv() {
  return typeof process !== "undefined" && process !== null && Boolean(process.env);
}

export function setEnv(name, value) {
  if (hasEnv()) process.env[name] = value;
  return undefined;
}

export function unsetEnv(name) {
  if (hasEnv()) delete process.env[name];
  return undefined;
}
