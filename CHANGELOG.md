# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0 - 2026-05-25

Initial public release.

### Added

- `is_tty(stream)` — detect whether `Stdin`, `Stdout`, or `Stderr` is
  connected to a terminal. Works on Erlang (OTP 26+) and JavaScript
  (Node 20+ or Node-compatible runtimes).
- `detect_color_level(stream)` — returns one of `NoColor`, `Basic`,
  `Ansi256`, or `TrueColor`, honoring `NO_COLOR`, `FORCE_COLOR`, `CI`,
  `TERM`, and `COLORTERM`.
- `resolve_color_level(is_tty:, env:)` — pure resolution function with
  an injectable environment lookup, for table-testing color logic
  without touching real environment variables.
- `color_level_at_least(actual, required)` and
  `color_level_to_int(level)` — ordering helpers so consumers can gate
  features without matching every variant.
- `FORCE_COLOR` recognizes `true`/`false` (case-insensitive) in
  addition to `0`/`1`/`2`/`3`, matching `chalk/supports-color`.
- TypeScript declarations are emitted for the JavaScript target.
- JavaScript FFI guards against environments where `process` is
  undefined (browsers, Deno without node-compat, Workers), degrading
  to "not a TTY" / "env unset" instead of throwing.

