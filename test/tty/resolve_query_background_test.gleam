import tty.{Dark, Light, Unknown}
import tty/resolve_query_background

const bel = "\u{7}"

const st = "\u{1b}\\"

fn response(channels: String, terminator: String) -> String {
  "\u{1b}]11;rgb:" <> channels <> terminator
}

fn query(response: String) -> fn() -> Result(String, Nil) {
  fn() { Ok(response) }
}

fn resolve(
  is_tty is_tty: Bool,
  query query: fn() -> Result(String, Nil),
) -> tty.Background {
  case
    resolve_query_background.resolve_query_background(
      is_tty: is_tty,
      query: query,
    )
  {
    0 -> Unknown
    1 -> Dark
    2 -> Light
    _ -> panic as "resolver returned a rank outside the documented 0..2 range"
  }
}

fn resolve_response(response: String) -> tty.Background {
  resolve(is_tty: True, query: query(response))
}

pub fn non_tty_is_unknown_without_querying_test() {
  assert resolve(is_tty: False, query: fn() {
      panic as "non-TTY resolution must not invoke the query"
    })
    == Unknown
}

pub fn query_error_is_unknown_test() {
  assert resolve(is_tty: True, query: fn() { Error(Nil) }) == Unknown
}

pub fn eight_bit_bel_dark_test() {
  assert resolve_response(response("00/00/00", bel)) == Dark
}

pub fn eight_bit_bel_light_test() {
  assert resolve_response(response("ff/ff/ff", bel)) == Light
}

pub fn eight_bit_st_response_test() {
  assert resolve_response(response("ff/ff/ff", st)) == Light
}

pub fn sixteen_bit_bel_dark_test() {
  assert resolve_response(response("0000/0000/0000", bel)) == Dark
}

pub fn sixteen_bit_st_light_test() {
  assert resolve_response(response("ffff/ffff/ffff", st)) == Light
}

pub fn uppercase_and_lowercase_hex_are_accepted_test() {
  assert resolve_response(response("aB/Cd/eF", bel)) == Light
  assert resolve_response(response("ABcd/ef01/2345", st)) == Light
}

pub fn eight_bit_channels_are_normalized_at_threshold_test() {
  assert resolve_response(response("7f/7f/7f", bel)) == Dark
  assert resolve_response(response("80/80/80", bel)) == Light
}

pub fn sixteen_bit_channels_use_same_threshold_test() {
  assert resolve_response(response("7fff/7fff/7fff", bel)) == Dark
  assert resolve_response(response("8000/8000/8000", bel)) == Light
}

pub fn perceived_luminance_weights_channels_test() {
  assert resolve_response(response("ff/00/00", bel)) == Dark
  assert resolve_response(response("00/ff/00", bel)) == Light
  assert resolve_response(response("00/00/ff", bel)) == Dark
}

pub fn missing_terminator_is_unknown_test() {
  assert resolve_response("\u{1b}]11;rgb:ff/ff/ff") == Unknown
}

pub fn truncated_st_is_unknown_test() {
  assert resolve_response("\u{1b}]11;rgb:ff/ff/ff\u{1b}") == Unknown
}

pub fn unrelated_response_is_unknown_test() {
  assert resolve_response("\u{1b}]10;rgb:ff/ff/ff\u{7}") == Unknown
  assert resolve_response("rgb:ff/ff/ff\u{7}") == Unknown
}

pub fn extra_data_before_or_after_response_is_unknown_test() {
  assert resolve_response("x\u{1b}]11;rgb:ff/ff/ff\u{7}") == Unknown
  assert resolve_response("\u{1b}]11;rgb:ff/ff/ff\u{7}x") == Unknown
}

pub fn missing_or_extra_channel_is_unknown_test() {
  assert resolve_response(response("ff/ff", bel)) == Unknown
  assert resolve_response(response("ff/ff/ff/ff", bel)) == Unknown
  assert resolve_response(response("ff//ff", bel)) == Unknown
}

pub fn mixed_width_channels_are_unknown_test() {
  assert resolve_response(response("ff/ffff/ffff", bel)) == Unknown
  assert resolve_response(response("ffff/ff/ffff", bel)) == Unknown
  assert resolve_response(response("ffff/ffff/ff", bel)) == Unknown
}

pub fn unsupported_channel_width_is_unknown_test() {
  assert resolve_response(response("f/f/f", bel)) == Unknown
  assert resolve_response(response("fff/fff/fff", bel)) == Unknown
  assert resolve_response(response("fffff/fffff/fffff", bel)) == Unknown
}

pub fn non_hex_channel_is_unknown_test() {
  assert resolve_response(response("gg/ff/ff", bel)) == Unknown
  assert resolve_response(response("ff/x0/ff", bel)) == Unknown
  assert resolve_response(response("ff/ff/0z", bel)) == Unknown
}

pub fn whitespace_is_unknown_test() {
  assert resolve_response(response(" ff/ff/ff", bel)) == Unknown
  assert resolve_response(response("ff/ff/ff ", bel)) == Unknown
}

pub fn wrong_prefix_case_is_unknown_test() {
  assert resolve_response("\u{1b}]11;RGB:ff/ff/ff\u{7}") == Unknown
}

pub fn c1_st_terminator_is_unknown_test() {
  assert resolve_response("\u{1b}]11;rgb:ff/ff/ff\u{9c}") == Unknown
}
