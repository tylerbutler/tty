# tty

TTY and ANSI color-support detection for Gleam. Works on both Erlang and JavaScript targets.

[![Hex](https://img.shields.io/hexpm/v/tty)](https://hex.pm/packages/tty)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue)](https://hexdocs.pm/tty)

## Install

```sh
gleam add tty
```

## Usage

```gleam
import gleam/io
import tty.{Ansi256, Basic, NoColor, Stdout, TrueColor}

pub fn main() {
  case tty.is_tty(Stdout) {
    True -> io.println("interactive!")
    False -> io.println("piped or redirected")
  }

  case tty.detect_color_level(Stdout) {
    NoColor -> io.println("plain text")
    Basic -> io.println("16 colors")
    Ansi256 -> io.println("256 colors")
    TrueColor -> io.println("24-bit color")
  }
}
```

These examples use `Stdout`, but CLIs that write data on stdout and
diagnostics on stderr usually want to check `Stderr` instead — e.g.
`tty.is_tty(Stderr)` to decide whether to color a progress bar or log
output while stdout is being piped elsewhere.

## Color resolution rules

`detect_color_level(stream)` evaluates in order (first match wins):

1. `NO_COLOR` set to any non-empty value → `NoColor`
2. `FORCE_COLOR` set (overrides the TTY check) →
   `0`/`false`=`NoColor`, `2`=`Ansi256`, `3`=`TrueColor`,
   `""`/`1`/`true`/unknown=`Basic` (case-insensitive)
3. Stream is not a TTY → `NoColor`
4. `TERM=dumb` → `NoColor`
5. `COLORTERM` is `truecolor` or `24bit` (case-insensitive) → `TrueColor`
6. `TERM` contains `256` → `Ansi256`
7. `CI` set → `Basic`
8. Default (unknown TTY with no color hints) → `NoColor`

The default in rule 8 errs on the side of safety: emitting ANSI escapes to
a terminal that may not handle them is worse than rendering plain text.
Set `FORCE_COLOR=1` (or any other supported value) to opt in explicitly.

Honors the [`NO_COLOR`](https://no-color.org) standard and uses a precedence model inspired by [`chalk/supports-color`](https://github.com/chalk/supports-color).

Notes:

- `TERM=dumb` is matched exactly (`dumb`).
- `TERM` containing `256` yields `Ansi256`.
- `CI` is treated as enabled if the variable is set to any value.

## Background detection

`detect_background(stream)` reports whether the terminal has a `Light` or `Dark`
background, or `Unknown` when it cannot tell. It reads the `COLORFGBG`
environment variable (set by terminals such as rxvt and konsole) and inspects
the background palette index (the second `;`-separated field):

- `0`–`6` or `8` → `Dark`
- `7` or `9`–`15` → `Light`
- unset, malformed, or out of range → `Unknown`

Detection is conservative: it only reports `Light`/`Dark` on a clear signal and
never guesses from `TERM`. Most terminals do not set `COLORFGBG`, so `Unknown`
is common — consumers should apply their own default (a common choice is to
treat `Unknown` as `Dark`) or accept an explicit override.

```gleam
import tty.{Dark, Light, Stdout, Unknown, detect_background}

case detect_background(Stdout) {
  Light -> render_for_light_background()
  Dark -> render_for_dark_background()
  Unknown -> render_default_theme()
}
```

## Public API guidance

For 1.x, this module intentionally exposes a small stable surface:

- `is_tty`
- `detect_color_level`
- `color_level_at_least`
- `color_level_compare`
- `detect_background`
- `Stream`
- `ColorLevel`
- `Background`

`ColorLevel` is intentionally closed for 1.x (`NoColor`, `Basic`, `Ansi256`,
`TrueColor`) to keep matching behavior predictable. Compare levels with
`color_level_at_least` or `color_level_compare` rather than relying on any
numeric rank; the integer mapping is an internal implementation detail.

`Background` is likewise closed for 1.x (`Light`, `Dark`, `Unknown`).

You can also gate behavior on the detected level without matching every
variant:

```gleam
import tty.{Ansi256, Stdout, color_level_at_least, detect_color_level}

let level = detect_color_level(Stdout)
case color_level_at_least(actual: level, at_least: Ansi256) {
  True -> render_256_color()
  False -> render_basic()
}
```

For finer-grained ordering, `color_level_compare` returns a `gleam/order`
`Order`, so it composes with `list.sort`, `order.reverse`, and friends:

```gleam
import gleam/order
import tty.{Ansi256, Basic, color_level_compare}

color_level_compare(Basic, Ansi256)
// -> order.Lt
```

## Runtime compatibility and fallback behavior

Supported runtimes:

- **Erlang target:** OTP ≥ 26
- **JavaScript target:** Node ≥ 20 (or compatible runtime with `process.*`)

In JavaScript runtimes without `process`/`process.env` (for example, browser
or Worker contexts), this library degrades safely:

- `is_tty(_)` returns `False`
- env vars are treated as unset
- `detect_color_level(_)` resolves to `NoColor`
- `detect_background(_)` resolves to `Unknown`

## Requirements

- Gleam ≥ 1.11
- Erlang/OTP and Node versions tested in CI:
  - OTP (Erlang target): 26, 27, 28
  - Node (JavaScript target): 20, 22, 24

## Troubleshooting

- **Getting `NoColor` unexpectedly:** check `NO_COLOR`, whether the stream is
  a TTY, and whether `TERM` is set to `dumb`.
- **Need color in CI/non-TTY contexts:** set `FORCE_COLOR=1`, `2`, or `3`.
- **Expected CI color but got none:** ensure `CI` is actually set in your
  environment.

For contributor setup, testing, and release workflow details, see [DEV.md](DEV.md).

## License

Dual licensed under either of

- MIT License ([LICENSE-MIT](LICENSE-MIT))
- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))

at your option.
