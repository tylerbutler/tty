# 1. Omit the `is_dark_background` helper

Date: 2026-06-05

## Status

Accepted

## Context

Issue #8 added env-based terminal background detection via
`detect_background(stream) -> Background`, where `Background` is
`Light | Dark | Unknown`. The issue also floated an optional convenience helper:

```gleam
pub fn is_dark_background(stream: Stream) -> Bool
```

which would collapse `Background` to a `Bool`, treating `Unknown` as `Dark`
(the conventional default, and the one the downstream consumer spruce uses).

The question is whether to ship this helper as part of the stable 1.x surface.

## Decision

Do not add `is_dark_background` for now. `detect_background` returns the full
`Background` type and consumers decide how to treat `Unknown`.

## Rationale

- **Charter.** `tty`'s job is capability *detection*, not policy. Returning a
  raw `Background` keeps the library policy-free, consistent with
  `detect_color_level`, which returns a `ColorLevel` and lets callers gate on it.
- **Baked-in policy.** `is_dark_background` would hard-code `Unknown == Dark`
  into the 1.x API. A consumer who prefers `Unknown == Light` gains nothing and
  falls back to matching `Background` anyway.
- **Reversibility.** Adding the helper later is purely additive and
  non-breaking; removing it after release is not. Deferring is the cheap,
  low-regret option.
- **Low cost today.** Consumers that want the conventional default write one
  `case` (e.g. `Unknown -> Dark`). spruce already supplies its own default plus
  an explicit `with_background` override, so it does not need the helper.

## Consequences

- Consumers must explicitly handle `Unknown` (this is a feature: the default is
  visible at the call site, not hidden in `tty`).
- If a clear, widely shared convention emerges, `is_dark_background` (or a more
  flexible variant such as one taking the desired `Unknown` fallback) can be
  added later without breaking existing code.
