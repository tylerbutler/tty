let seenNames = [];

export function reset() {
  seenNames = [];
  return undefined;
}

export function record(name) {
  seenNames = [name, ...seenNames];
  return undefined;
}

export function seen(name) {
  return seenNames.includes(name);
}
