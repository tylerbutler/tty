# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - 2026-06-05


### Added

- Terminal background detection via `detect_background/1`, which reports whether
a stream's terminal has a `Light` or `Dark` background, or `Unknown` when it
cannot be determined. Detection reads the `COLORFGBG` environment variable
(set by terminals such as rxvt and konsole) and is conservative: it only
reports `Light`/`Dark` on a clear signal, so `Unknown` is common and callers
should supply their own default.

Adds the `Background` type (`Light`, `Dark`, `Unknown`), intentionally closed
for 1.x like `ColorLevel`. Works on both the Erlang and JavaScript targets and
degrades to `Unknown` when `process`/`process.env` is unavailable on
JavaScript.

## v1.0.0 - 2026-05-28


### MajorRelease

- Initial stable release.

Provides `is_tty/1` for TTY detection on stdout/stderr and
`detect_color_level/1` for resolving terminal color support, on both the
Erlang and JavaScript targets.

Public API: `Stream`, `ColorLevel` (`NoColor`, `Basic`, `Ansi256`,
`TrueColor`), `is_tty/1`, `detect_color_level/1`,
`color_level_at_least/2` (labels: `actual:`, `at_least:`), and
`color_level_compare/2`, which returns a `gleam/order` `Order`. Levels are
compared via these helpers; the numeric rank is an internal implementation
detail and is not part of the public API.

Color resolution follows the documented precedence rules in `README.md`;
the JavaScript runtime degrades safely when `process`/`process.env` are
unavailable.

Requires `gleam_stdlib >= 0.40.0 and < 2.0.0`.


## v0.1.0 - 2026-05-25


