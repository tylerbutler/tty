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

## Public API guidance

For 1.0, treat these as the primary stable APIs:

- `is_tty`
- `detect_color_level`
- `color_level_at_least`
- `color_level_to_int`

`resolve_color_level` is available for advanced deterministic testing and
custom integrations. Most applications should prefer `detect_color_level`.

You can also gate behavior on the detected level without matching every
variant:

```gleam
import tty.{Ansi256, Stdout, color_level_at_least, detect_color_level}

case color_level_at_least(detect_color_level(Stdout), Ansi256) {
  True -> render_256_color()
  False -> render_basic()
}
```

## Requirements

- Gleam ≥ 1.11
- **Erlang target:** OTP ≥ 26 (uses per-stream `io:getopts/1`)
- **JavaScript target:** Node ≥ 20, or a Node-style runtime that provides
  `process.stdin`, `process.stdout`, `process.stderr`, and `process.env`

For contributor setup, testing, and release workflow details, see [DEV.md](DEV.md).

## License

Dual licensed under either of

- MIT License ([LICENSE-MIT](LICENSE-MIT))
- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))

at your option.
