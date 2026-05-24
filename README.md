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

1. `NO_COLOR` set non-empty → `NoColor`
2. `FORCE_COLOR` set → `0`=`NoColor`, `1`/empty/unknown=`Basic`, `2`=`Ansi256`, `3`=`TrueColor`
3. Stream is not a TTY → `NoColor`
4. `TERM=dumb` → `NoColor`
5. `COLORTERM` is `truecolor` or `24bit` (case-insensitive) → `TrueColor`
6. `TERM` contains `256` → `Ansi256`
7. `CI` set → `Basic`
8. Default for TTYs → `Basic`

Honors the [`NO_COLOR`](https://no-color.org) standard and uses a precedence model inspired by [`chalk/supports-color`](https://github.com/chalk/supports-color).

## Testing your color logic

`resolve_color_level` is exposed as a pure function so you can table-test
your own rendering code without manipulating real environment variables
or terminals. Its `env` callback uses `Ok(value)` for a set variable,
including `Ok("")` for a set-but-empty variable, and `Error(Nil)` for an
unset variable:

```gleam
import tty.{Basic, resolve_color_level}

let env = fn(name) {
  case name {
    "TERM" -> Ok("xterm")
    _ -> Error(Nil)
  }
}

resolve_color_level(is_tty: True, env: env)
// -> Basic
```

## Requirements

- Gleam ≥ 1.11
- **Erlang target:** OTP ≥ 26 (uses per-stream `io:getopts/1`)
- **JavaScript target:** Node ≥ 20, or a Node-style runtime that provides
  `process.stdin`, `process.stdout`, `process.stderr`, and `process.env`

## License

Dual licensed under either of

- MIT License ([LICENSE-MIT](LICENSE-MIT))
- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))

at your option.
