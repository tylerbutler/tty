import gleam/order
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

pub fn compare_orders_ascending_test() {
  tty.color_level_compare(NoColor, Basic) |> expect.to_equal(order.Lt)
  tty.color_level_compare(Basic, Ansi256) |> expect.to_equal(order.Lt)
  tty.color_level_compare(Ansi256, TrueColor) |> expect.to_equal(order.Lt)
  tty.color_level_compare(NoColor, TrueColor) |> expect.to_equal(order.Lt)
}

pub fn compare_orders_descending_test() {
  tty.color_level_compare(TrueColor, Ansi256) |> expect.to_equal(order.Gt)
  tty.color_level_compare(Ansi256, Basic) |> expect.to_equal(order.Gt)
  tty.color_level_compare(Basic, NoColor) |> expect.to_equal(order.Gt)
  tty.color_level_compare(TrueColor, NoColor) |> expect.to_equal(order.Gt)
}

pub fn compare_equal_levels_test() {
  tty.color_level_compare(NoColor, NoColor) |> expect.to_equal(order.Eq)
  tty.color_level_compare(Basic, Basic) |> expect.to_equal(order.Eq)
  tty.color_level_compare(Ansi256, Ansi256) |> expect.to_equal(order.Eq)
  tty.color_level_compare(TrueColor, TrueColor) |> expect.to_equal(order.Eq)
}
