import gleam/list
import startest/expect
import tty.{Dark, Light, Unknown}
import tty/resolve_background

// Helper: build an env-lookup function from a list of pairs.
fn env(pairs: List(#(String, String))) -> fn(String) -> Result(String, Nil) {
  fn(name) { list.key_find(pairs, name) }
}

fn resolve(env env: fn(String) -> Result(String, Nil)) -> tty.Background {
  case resolve_background.resolve_background(env: env) {
    0 -> Unknown
    1 -> Dark
    2 -> Light
    _ -> panic as "resolver returned a rank outside the documented 0..2 range"
  }
}

pub fn dark_background_zero_test() {
  resolve(env: env([#("COLORFGBG", "15;0")]))
  |> expect.to_equal(Dark)
}

pub fn dark_background_six_test() {
  resolve(env: env([#("COLORFGBG", "1;6")]))
  |> expect.to_equal(Dark)
}

pub fn dark_background_eight_test() {
  resolve(env: env([#("COLORFGBG", "7;8")]))
  |> expect.to_equal(Dark)
}

pub fn light_background_seven_test() {
  resolve(env: env([#("COLORFGBG", "0;7")]))
  |> expect.to_equal(Light)
}

pub fn light_background_nine_test() {
  resolve(env: env([#("COLORFGBG", "0;9")]))
  |> expect.to_equal(Light)
}

pub fn light_background_fifteen_test() {
  resolve(env: env([#("COLORFGBG", "0;15")]))
  |> expect.to_equal(Light)
}

pub fn unset_colorfgbg_is_unknown_test() {
  resolve(env: env([]))
  |> expect.to_equal(Unknown)
}

pub fn empty_colorfgbg_is_unknown_test() {
  resolve(env: env([#("COLORFGBG", "")]))
  |> expect.to_equal(Unknown)
}

pub fn missing_semicolon_is_unknown_test() {
  resolve(env: env([#("COLORFGBG", "7")]))
  |> expect.to_equal(Unknown)
}

pub fn fg_bg_extra_dark_test() {
  resolve(env: env([#("COLORFGBG", "0;0;0")]))
  |> expect.to_equal(Dark)
}

pub fn three_field_numeric_uses_last_field_test() {
  resolve(env: env([#("COLORFGBG", "15;7;0")]))
  |> expect.to_equal(Dark)
}

pub fn rxvt_three_field_dark_test() {
  resolve(env: env([#("COLORFGBG", "15;default;0")]))
  |> expect.to_equal(Dark)
}

pub fn rxvt_three_field_light_test() {
  resolve(env: env([#("COLORFGBG", "0;default;7")]))
  |> expect.to_equal(Light)
}

pub fn whitespace_dark_background_test() {
  resolve(env: env([#("COLORFGBG", "0; 0 ")]))
  |> expect.to_equal(Dark)
}

pub fn whitespace_light_background_test() {
  resolve(env: env([#("COLORFGBG", "0; 7 ")]))
  |> expect.to_equal(Light)
}

pub fn out_of_range_high_background_is_unknown_test() {
  resolve(env: env([#("COLORFGBG", "0;16")]))
  |> expect.to_equal(Unknown)
}

pub fn out_of_range_negative_background_is_unknown_test() {
  resolve(env: env([#("COLORFGBG", "0;-1")]))
  |> expect.to_equal(Unknown)
}

pub fn non_numeric_background_is_unknown_test() {
  resolve(env: env([#("COLORFGBG", "0;x")]))
  |> expect.to_equal(Unknown)
}
