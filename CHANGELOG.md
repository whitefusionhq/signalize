# Changelog

## [Unreleased]

## [1.3.0] - 2023-10-04

- Provide `Signalize::Struct`, a struct-like object to hold multiple signals (including computed)
  (optional via `require "signalize/struct"`)

## [1.2.0] - 2023-10-03

- Add `untracked` method (implements #5)
- Add `mutation_detected` check for `computed`

Gem now roughly analogous to `@preact/signals-core` v1.5

## [1.1.0] - 2023-03-25

- Provide better signal/computed inspect strings (fixes #1)
- Use Concurrent::Map for thread-safe globals (fixes #3)

## [1.0.1] - 2023-03-08

- Prevent early returns in effect blocks
- Use gem's error class (fixes #2)

## [1.0.0] - 2023-03-07

- Initial release
