import gleam/bool
import gleam/int
import gleam/list
import gleam/string

const response_prefix = "\u{1b}]11;rgb:"

const bel = "\u{7}"

const st = "\u{1b}\\"

/// Internal OSC 11 background-query resolution logic.
///
/// Returns a stable rank (`0..2`) where:
/// - `0` => Unknown
/// - `1` => Dark
/// - `2` => Light
pub fn resolve_query_background(
  is_tty is_tty: Bool,
  query query: fn() -> Result(String, Nil),
) -> Int {
  use <- bool.guard(when: !is_tty, return: 0)

  case query() {
    Ok(response) -> parse_response(response)
    Error(Nil) -> 0
  }
}

fn parse_response(response: String) -> Int {
  use body <- result_rank(response_body(response))

  case string.split(body, on: "/") {
    [red, green, blue] -> classify_channels(red: red, green: green, blue: blue)
    _ -> 0
  }
}

fn response_body(response: String) -> Result(String, Nil) {
  use <- bool.guard(
    when: !string.starts_with(response, response_prefix),
    return: Error(Nil),
  )

  let body_and_terminator =
    string.drop_start(response, string.length(response_prefix))

  case string.ends_with(body_and_terminator, bel) {
    True -> Ok(string.drop_end(body_and_terminator, 1))
    False ->
      case string.ends_with(body_and_terminator, st) {
        True -> Ok(string.drop_end(body_and_terminator, 2))
        False -> Error(Nil)
      }
  }
}

fn result_rank(result: Result(String, Nil), next: fn(String) -> Int) -> Int {
  case result {
    Ok(value) -> next(value)
    Error(Nil) -> 0
  }
}

fn classify_channels(
  red red: String,
  green green: String,
  blue blue: String,
) -> Int {
  let width = string.length(red)
  let valid_width = width == 2 || width == 4
  let uniform_width =
    string.length(green) == width && string.length(blue) == width

  case
    valid_width && uniform_width && is_hex(red) && is_hex(green) && is_hex(blue)
  {
    False -> 0
    True ->
      case
        int.base_parse(red, 16),
        int.base_parse(green, 16),
        int.base_parse(blue, 16)
      {
        Ok(red), Ok(green), Ok(blue) ->
          classify_luminance(
            red: normalize_channel(red, width),
            green: normalize_channel(green, width),
            blue: normalize_channel(blue, width),
          )
        _, _, _ -> 0
      }
  }
}

fn is_hex(channel: String) -> Bool {
  channel
  |> string.to_graphemes
  |> list.all(is_hex_digit)
}

fn is_hex_digit(digit: String) -> Bool {
  case digit {
    "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9"
    | "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F" -> True
    _ -> False
  }
}

fn normalize_channel(channel: Int, width: Int) -> Int {
  case width {
    2 -> channel * 257
    _ -> channel
  }
}

fn classify_luminance(red red: Int, green green: Int, blue blue: Int) -> Int {
  // Rec. 601 perceived luminance weights, with channels normalized to 16-bit.
  // A luminance of at least 50% (`0x8000`) is considered a light background.
  let weighted_luminance = red * 299 + green * 587 + blue * 114
  let light_threshold = 32_768 * 1000

  case weighted_luminance >= light_threshold {
    True -> 2
    False -> 1
  }
}
