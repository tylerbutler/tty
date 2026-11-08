import gleam/order
import tty.{Ansi256, Basic, NoColor, TrueColor}

pub fn at_least_no_color_accepts_anything_test() {
  assert tty.color_level_at_least(NoColor, NoColor)
  assert tty.color_level_at_least(Basic, NoColor)
  assert tty.color_level_at_least(Ansi256, NoColor)
  assert tty.color_level_at_least(TrueColor, NoColor)
}

pub fn at_least_basic_rejects_no_color_test() {
  assert !tty.color_level_at_least(NoColor, Basic)
  assert tty.color_level_at_least(Basic, Basic)
  assert tty.color_level_at_least(Ansi256, Basic)
  assert tty.color_level_at_least(TrueColor, Basic)
}

pub fn at_least_ansi256_test() {
  assert !tty.color_level_at_least(NoColor, Ansi256)
  assert !tty.color_level_at_least(Basic, Ansi256)
  assert tty.color_level_at_least(Ansi256, Ansi256)
  assert tty.color_level_at_least(TrueColor, Ansi256)
}

pub fn at_least_truecolor_only_truecolor_test() {
  assert !tty.color_level_at_least(NoColor, TrueColor)
  assert !tty.color_level_at_least(Basic, TrueColor)
  assert !tty.color_level_at_least(Ansi256, TrueColor)
  assert tty.color_level_at_least(TrueColor, TrueColor)
}

pub fn compare_orders_ascending_test() {
  assert tty.color_level_compare(NoColor, Basic) == order.Lt
  assert tty.color_level_compare(Basic, Ansi256) == order.Lt
  assert tty.color_level_compare(Ansi256, TrueColor) == order.Lt
  assert tty.color_level_compare(NoColor, TrueColor) == order.Lt
}

pub fn compare_orders_descending_test() {
  assert tty.color_level_compare(TrueColor, Ansi256) == order.Gt
  assert tty.color_level_compare(Ansi256, Basic) == order.Gt
  assert tty.color_level_compare(Basic, NoColor) == order.Gt
  assert tty.color_level_compare(TrueColor, NoColor) == order.Gt
}

pub fn compare_equal_levels_test() {
  assert tty.color_level_compare(NoColor, NoColor) == order.Eq
  assert tty.color_level_compare(Basic, Basic) == order.Eq
  assert tty.color_level_compare(Ansi256, Ansi256) == order.Eq
  assert tty.color_level_compare(TrueColor, TrueColor) == order.Eq
}
