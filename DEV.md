# Development

## Prerequisites

- Gleam 1.11 or newer for package compatibility; CI uses Gleam 1.16.0
- Erlang/OTP 26 or newer for the Erlang target
- Node.js 20 or newer for the JavaScript target

CI and Hex publishing use Ubuntu 24.04 because the pinned BEAM setup action
does not support Ubuntu 26.04.

## Common commands

- `just build` — compile the package
- `just test` — run the Erlang and JavaScript test suites
- `just format` — format the source and test files
- `just lint` — check formatting
- `just docs` — build the Hex documentation
- `just ci` — run the full validation workflow

## Dependency updates

Run `gleam deps outdated` to check for updates and `gleam deps update` to
update the lockfile. Then run `just ci`.

## Tests

Unitest discovers public zero-argument functions whose names end in `_test`.
Use native Gleam `assert` statements for checks. Keep `@target` annotations on
target-specific tests.

Tests run sequentially in random order. Unitest reports the seed so you can
reproduce that order. Pass runner options after `--`:

```sh
# Run a test file on either target
gleam test --target erlang -- test/tty/resolve_color_level_test.gleam
gleam test --target javascript -- test/tty/resolve_color_level_test.gleam

# Run one test
gleam test --target erlang -- --test tty/resolve_color_level_test.no_color_disables_everything_test

# Reproduce an order using the reported seed
gleam test --target javascript -- --seed 123
```

## Release workflow

1. Add a changelog fragment under `.changes/unreleased/` using the project’s Changie setup.
2. Keep `gleam.toml` at the last released version until the release PR merges; the release PR is what bumps the package to `1.0.0`.
3. Run `just ci` before opening a pull request.
4. Ensure repository secrets are configured for automation:
   - `HEX_API_KEY`
   - `RELEASE_APP_ID`
   - `RELEASE_APP_PRIVATE_KEY`
5. Merge the release PR to `main`.
6. When the release PR closes, the auto-tag workflow creates a tag and GitHub release.
7. The `Publish` workflow runs on tag push and publishes the package to Hex.

## Public API expectations

- Keep the documented public API in `src/tty.gleam` stable across minor releases.
- `ColorLevel` is a closed 1.x API contract (`NoColor`, `Basic`, `Ansi256`, `TrueColor`).
- Prefer additive changes over breaking changes for 1.x.
- If a behavior change is necessary, document it in the changelog and update the README examples when needed.
