import gleam/list
import startest/expect
import tty.{Ansi256, Basic, NoColor, TrueColor}

pub fn at_least_no_color_accepts_anything_test() {
  tty.color_level_at_least(NoColor, NoColor) |> expect.to_be_true
  tty.color_level_at_least(Basic, NoColor) |> expect.to_be_true
  tty.color_level_at_least(Ansi256, NoColor) |> expect.to_be_true
  tty.color_level_at_least(TrueColor, NoColor) |> expect.to_be_true
}

pub fn at_least_basic_rejects_no_color_test() {
  tty.color_level_at_least(NoColor, Basic) |> expect.to_be_false
  tty.color_level_at_least(Basic, Basic) |> expect.to_be_true
  tty.color_level_at_least(Ansi256, Basic) |> expect.to_be_true
  tty.color_level_at_least(TrueColor, Basic) |> expect.to_be_true
}

pub fn at_least_ansi256_test() {
  tty.color_level_at_least(NoColor, Ansi256) |> expect.to_be_false
  tty.color_level_at_least(Basic, Ansi256) |> expect.to_be_false
  tty.color_level_at_least(Ansi256, Ansi256) |> expect.to_be_true
  tty.color_level_at_least(TrueColor, Ansi256) |> expect.to_be_true
}

pub fn at_least_truecolor_only_truecolor_test() {
  tty.color_level_at_least(NoColor, TrueColor) |> expect.to_be_false
  tty.color_level_at_least(Basic, TrueColor) |> expect.to_be_false
  tty.color_level_at_least(Ansi256, TrueColor) |> expect.to_be_false
  tty.color_level_at_least(TrueColor, TrueColor) |> expect.to_be_true
}

pub fn to_int_orders_levels_test() {
  tty.color_level_to_int(NoColor) |> expect.to_equal(0)
  tty.color_level_to_int(Basic) |> expect.to_equal(1)
  tty.color_level_to_int(Ansi256) |> expect.to_equal(2)
  tty.color_level_to_int(TrueColor) |> expect.to_equal(3)
}

pub fn from_int_round_trips_valid_ranks_test() {
  tty.color_level_from_int(0) |> expect.to_equal(Ok(NoColor))
  tty.color_level_from_int(1) |> expect.to_equal(Ok(Basic))
  tty.color_level_from_int(2) |> expect.to_equal(Ok(Ansi256))
  tty.color_level_from_int(3) |> expect.to_equal(Ok(TrueColor))
}

pub fn from_int_rejects_out_of_range_test() {
  tty.color_level_from_int(-1) |> expect.to_equal(Error(Nil))
  tty.color_level_from_int(4) |> expect.to_equal(Error(Nil))
  tty.color_level_from_int(99) |> expect.to_equal(Error(Nil))
}

pub fn to_int_then_from_int_is_identity_test() {
  let levels = [NoColor, Basic, Ansi256, TrueColor]
  list.each(levels, fn(level) {
    tty.color_level_from_int(tty.color_level_to_int(level))
    |> expect.to_equal(Ok(level))
  })
}
