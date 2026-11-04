# React fixtures

- Merge `boundaries/` into your `fixtures/boundaries/`. `allowed/` must pass and `forbidden/` must report `ui-is-presentational`.
- Copy `lint/src/features/orders/ui/forbidden.tsx` to `fixtures/lint/` keeping the same relative path under a `src/`, because the ESLint block matches on `src/features/*/ui`.
- Assert exactly 6 `no-restricted` errors in `scripts/verify-lint-rules.sh`, so a pattern that grows or shrinks fails either way.
