# Development

## Prerequisites

- Gleam 1.11 or newer for package compatibility; CI uses Gleam 1.16.0
- Erlang/OTP 26 or newer for the Erlang target
- Node.js 20 or newer for the JavaScript target
- Trellis 1.3.0 for changelog and release commands

Install the repository's tools with `mise install`. Trellis uses the
`github:tylerbutler/trellis` backend, pinned to 1.3.0 in `.mise.toml` and
`.tool-versions`. CI installs the same published binary.

CI uses Ubuntu 24.04 because its pinned BEAM setup action does not support
Ubuntu 26.04. The reusable release workflow uses a newer BEAM action that
supports Ubuntu 26.04.

## Common commands

- `just build` — compile the package
- `just test` — run the Erlang and JavaScript test suites
- `just format` — format the source and test files
- `just lint` — check formatting
- `just docs` — build the Hex documentation
- `just change Fixed "Describe the change"` — add a changelog fragment
- `just changelog-preview` (or `just changelog`) — preview version bumps without changing files
- `just release-check` — check release configuration and fragments
- `just ci` — run the full validation workflow

## Dependency updates

Run `gleam deps outdated` to check for updates and `gleam deps update` to
update the lockfile. Then run `just ci`.

## Tests

Unitest discovers public zero-argument functions whose names end in `_test`.
Use native Gleam `assert` statements for checks. Keep `@target` annotations on
target-specific tests.

Tests run sequentially in random order. Unitest reports the seed so you can
reproduce that order. Pass runner options after `--`:

```sh
# Run a test file on either target
gleam test --target erlang -- test/tty/resolve_color_level_test.gleam
gleam test --target javascript -- test/tty/resolve_color_level_test.gleam

# Run one test
gleam test --target erlang -- --test tty/resolve_color_level_test.no_color_disables_everything_test

# Reproduce an order using the reported seed
gleam test --target javascript -- --seed 123
```

## Release workflow

### Changelog entries and version planning

Add fragments for user-facing changes; development-only changes do not need
an entry. `just change` (alias `just cl`) requires a kind and a body:

```sh
just change Fixed "Reject malformed terminal responses"
just change Added "Add a terminal capability helper"
# Equivalent native command; TTY is the only releasable package.
trellis changelog new --package tty --kind Fixed --body "Reject malformed terminal responses"
trellis version plan --json
```

Trellis writes TOML fragments under `.changes/unreleased/`. It archives release
sections under `.changes/tty/` and generates `CHANGELOG.md` during release
preparation. Historical release text remains in the adopted archive.

The largest fragment bump determines the next version. `Added` means minor,
`MajorRelease` means major, and `Fixed`, `Performance`, `Changed`, `Reverted`,
`Dependencies`, and `Security` mean patch. These preserve the former kind
rules, including the patch bump for `Changed`.

PR checks compare changed package content against the PR base and head,
rather than infer missing entries from conventional commit types.
Missing-entry comments are advisory; invalid fragments fail the check.
Run `just ci` before opening a pull request.

### Stable releases

Keep `gleam.toml` at the last released version until the release PR merges.
On main pushes, the `Release` workflow prepares or refreshes a native
`release/pending` PR. Trellis owns the version bump, changelog, fragment
archives, and `.changes/release.toml` semantic intent. Do not edit the intent
file; use the workflow's release inputs to change a request.

Review and merge the release PR. The workflow publishes the approved merge
commit to Hex, then records the release with an immutable `v{version}` tag
and a GitHub release. Tag pushes do not trigger another publisher.
Preparation waits until both publication and tagging succeed.

### Release candidates and promotion

Select **main** when dispatching `Release` in GitHub Actions. Use `pre: rc`
and a `set` target such as `tty=1.2.0` to request `1.2.0-rc.0`. The `set`
and `bump` inputs accept one override per line.

Review, merge, and publish each candidate before dispatching the next request.
Use `pre: rc` again for the next candidate, or `pre: none` for stable promotion.
Trellis archives candidate fragments and rolls them up for the stable release.
Unchanged content does not generate repeated candidate releases.

The coordinator pauses automatic preparation while a candidate or manual
request owns the release. Native resumption preserves the pending request's
targets and mode. No automatic path promotes a candidate to stable.
Successful stable promotion restores automatic preparation.

### Credentials and recovery

Configure `HEX_API_KEY`, `RELEASE_APP_ID`, and `RELEASE_APP_PRIVATE_KEY`.
The Hex key must permit publication of `tty`. Install the release App on this
repository with Contents, Pull requests, and Commit statuses write access.
The workflow token needs Contents and Commit statuses write access and
Pull requests read access.

The coordinator serializes release runs and records `trellis/release` on the
approved merge commit. It records success only after Hex publication and
tagging complete. Recover by rerunning the failed **merge-event** workflow,
not by dispatching a new version or publishing current main. Trellis skips
already-published Hex versions and reconciles existing tags and releases.

Manual requests reserve their base commit with a pending
`trellis/release_request` status, including if preparation fails before a PR
exists. Fix and rerun that request. To abandon it, close its pending PR and
clear the reservation on the recorded base commit after checking its state.
Do not mark an unknown or partial publication successful.

### Migration handoff

Before this migration reaches main, close the old Changie release PR
[#20](https://github.com/tylerbutler/tty/pull/20) and confirm that no old release
run remains active. Do not merge that PR after migration.
This onboarding change does not close the PR or change repository settings.

Both pending entries retain their text and semantic bumps, so Trellis plans
the same stable release, `1.1.1` to `1.2.0`. It will prepare a new
`release/pending` PR from those fragments after migration.
Legacy releases used `release/next`, so they do not require a historical
`trellis/release` status seed for the new coordinator.

## Public API expectations

- Keep the documented public API in `src/tty.gleam` stable across minor releases.
- `ColorLevel` is a closed 1.x API contract (`NoColor`, `Basic`, `Ansi256`, `TrueColor`).
- Prefer additive changes over breaking changes for 1.x.
- If a behavior change is necessary, document it in the changelog and update the README examples when needed.
