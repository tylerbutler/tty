# Copilot instructions for `tty`

## Build, test, and lint commands

- Build: `just build` (or `gleam build`)
- Format: `just format` (or `gleam format src test`)
- Lint/format check: `just lint` (or `gleam format --check src test`)
- Docs: `just docs` (or `gleam docs build`)
- Full validation: `just ci` (runs format, lint, tests on both targets, build, and docs)

Tests run on both targets and should stay green on both:

- `gleam test --target erlang`
- `gleam test --target javascript`

Unitest discovers public zero-argument `*_test` functions and runs them
sequentially in seeded random order. Use native Gleam assertions.

Run a single test file:

- `gleam test --target erlang -- test/tty/resolve_color_level_test.gleam`
- `gleam test --target javascript -- test/tty/resolve_color_level_test.gleam`

(`test/tty/smoke_test.gleam` and `test/tty/color_level_helpers_test.gleam`
can be run the same way.)

Run one test or reproduce an order:

- `gleam test --target erlang -- --test tty/resolve_color_level_test.no_color_disables_everything_test`
- `gleam test --target javascript -- --seed 123`

## High-level architecture

- `src/tty.gleam` is the public API surface (`Stream`, `ColorLevel`, `is_tty`, `detect_color_level`, helper comparators/converters).
- `src/tty/resolve_color_level.gleam` contains the pure color-resolution decision logic. It takes `is_tty` + an env lookup function and returns a stable rank (`0..3`) that `src/tty.gleam` maps to `ColorLevel`.
- Platform-specific runtime probing is isolated in FFI:
  - Erlang: `src/tty_ffi.erl`
  - JavaScript: `src/tty_ffi.mjs`
- Test strategy is split by concern:
  - Rule/precedence behavior: `test/tty/resolve_color_level_test.gleam` (pure, dependency-injected env)
  - Public helper ordering/mapping: `test/tty/color_level_helpers_test.gleam`
  - Runtime/FFI smoke checks: `test/tty/smoke_test.gleam`
  - Probe helpers for env lookup order assertions: `test/tty/env_probe.gleam` + target-specific FFI files

## Key repository conventions

- Treat `src/tty.gleam` as the stable 1.x contract. `ColorLevel` is intentionally closed (`NoColor`, `Basic`, `Ansi256`, `TrueColor`) and rank mapping (`0..3`) is part of the public contract.
- Keep color resolution precedence aligned with the documented rules in `README.md` and with tests in `test/tty/resolve_color_level_test.gleam`. In particular, default unknown TTY behavior (no hints) is `NoColor`.
- Preserve target parity: behavior changes in runtime probing or env handling should be reflected in both `src/tty_ffi.erl` and `src/tty_ffi.mjs`, then validated on both targets.
- JavaScript runtime fallback is intentionally defensive: missing `process`/`process.env` must degrade safely (no throws, effectively “not a TTY” / env unset behavior).
- For release work, add changelog fragments under `.changes/unreleased/` and follow `DEV.md` workflow (release automation updates `gleam.toml` version via release PR).
