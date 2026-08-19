import { readFileSync } from "node:fs";

const interfacePath = new URL(
  "../build/dev/docs/tty/package-interface.json",
  import.meta.url,
);
const packageInterface = JSON.parse(readFileSync(interfacePath, "utf8"));
const functions = packageInterface.modules.tty.functions;
const crossTargetFunctions = [
  "is_tty",
  "detect_color_level",
  "detect_background",
];

for (const name of crossTargetFunctions) {
  const implementations = functions[name]?.implementations;
  if (
    !implementations?.["can-run-on-erlang"] ||
    !implementations?.["can-run-on-javascript"]
  ) {
    throw new Error(`${name} must be documented as runnable on both targets`);
  }
}
