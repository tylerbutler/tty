# Development

## Prerequisites

- Gleam 1.11 or newer for package compatibility; CI uses Gleam 1.16.0
- Erlang/OTP 26 or newer for the Erlang target
- Node.js 20 or newer for the JavaScript target

## Common commands

- `just build` — compile the package
- `just test` — run the Erlang and JavaScript test suites
- `just format` — format the source and test files
- `just lint` — check formatting
- `just docs` — build the Hex documentation
- `just ci` — run the full validation workflow

## Release workflow

1. Add a changelog fragment under `.changes/unreleased/` using the project’s Changie setup.
2. Keep `gleam.toml` at the last released version until the release PR merges; the release PR is what bumps the package to `1.0.0`.
3. Run `just ci` before opening a pull request.
4. Merge the release PR to `main` and let the release workflow publish the package.

## Public API expectations

- Keep the documented functions in `src/tty.gleam` stable across minor releases.
- Prefer additive changes over breaking changes for 1.x.
- If a behavior change is necessary, document it in the changelog and update the README examples when needed.
