---
name: testing-strategy
description: Which test to write and where, across Flutter, React and Next.js, and NestJS. Unit versus integration versus end-to-end, Playwright for web, Flutter integration_test, NestJS e2e on a real database, API contract tests, fixtures and test data, the flaky-test policy, and turning a bug report or log into a failing test. Use when planning the tests for a contract, writing or reviewing tests, triaging a flaky test, or reproducing a bug.
paths:
  - "**/test/**"
  - "**/e2e/**"
  - "**/integration_test/**"
  - "**/*.spec.ts"
  - "**/*_test.dart"
  - "**/*.test.tsx"
---

# Testing strategy

Which test proves which claim, at which level, in which stack's files. The rules live in each stack standard's testing section; this skill links them and adds the cross-stack view, the flaky-test policy, and the route from a bug to a failing test. The repo's established test layout beats this skill, and you say so when they differ. Except the fixed stack choices (Drizzle and Zod), which repo convention never overrides.

## What am I proving

| Proving | Level | Read |
| --- | --- | --- |
| A pure rule: money, dates, permissions, a state machine | Unit | `01-levels-by-stack.md` |
| A repository or service, with the boundary below it mocked | Unit with a double one layer down | `01-levels-by-stack.md` |
| A `ui/` widget renders from props and fires callbacks | Widget or component test, no provider | `ui-isolation` Testing |
| Every state a screen shows: loading, error, empty, loaded | Widget or component test | `01-levels-by-stack.md` |
| A flow through the real router and guard | Flow test | `01-levels-by-stack.md`, `03-flutter-integration.md` |
| An endpoint against a real database | NestJS e2e | `04-nestjs-e2e-and-db.md` |
| A concurrency guard holds | Two real operations on one row | `04-nestjs-e2e-and-db.md` |
| Client and server agree on the API | Contract test | `05-contract-tests.md` |
| A critical journey in a real browser or device | Playwright or `integration_test` | `02-playwright-web.md`, `03-flutter-integration.md` |

Pick the lowest level that can show the failure. Go up a level only for what the lower one cannot see, such as wiring.

## Rules that never bend

- Every test has been seen to fail before it counts (hawkeye, Method step 3; `flutter-standards` 12, 7.3 for machine-applied sabotage).
- Mock at the boundary the standard names: one layer below in Flutter (`flutter-standards` 12), the network with MSW in React (`react-standards` 05, 4.9), a real database for NestJS e2e (`nestjs-standards` 05, 4.11).
- Never a skip, a retry, or a longer timeout to get green (AGENTS.md rule 9). A real failure is reported as a bug with the failing test name.
- No real personal data in fixtures, from production, a log, or a person you know (kit rule, `06-fixtures-and-data.md`).
- Secret-shaped fixtures are assembled at runtime from pieces, so the repo never holds a string a secret scanner flags (as in `kit-learning-loop` Tests).

## Flaky-test policy

A test that fails and then passes with no code change is flaky, and flaky is a bug.

- Report it with the run count (fails N of M), the failing output, and the likely class: time, order, shared state, network, or unawaited async.
- Never add a retry, a skip, or a quarantine. Only Dave quarantines, with a linked issue and an expiry date, and the test keeps running in a non-blocking job.
- Framework retries (Playwright `retries`) stay at 0 unless a project ADR sets them. A pass on retry is still reported as flaky.

Diagnosis per class: `07-flaky-tests.md`.

Flaky report format:

```text
FLAKY <test file>:<test name>
Runs: failed <N> of <M>, command: <exact command>
Class (likely): <time | order | shared state | network | unawaited async>, because <evidence>
Failing output: <first failing assertion and stack, trimmed>
Next: <the diagnosis step from 07-flaky-tests.md that confirms or rules out the class>
```

## Bug to failing test

Follow `08-bug-to-failing-test.md`: from the report to the lowest-level test that fails the same way, then up one level if the bug is in wiring. Reading a log or trace into inputs belongs to the `observability-and-debugging` skill; this skill owns the test.

## Read only what the task needs

| Task | Read in `references/` |
| --- | --- |
| Plan the Tests section of a contract, pick a level, place a file | `01-levels-by-stack.md` |
| Web end-to-end, locators, auth state, traces, a11y scans | `02-playwright-web.md` |
| Flutter flow on a device or emulator, flavors in CI | `03-flutter-integration.md` |
| NestJS e2e, test database, isolation, concurrency tests | `04-nestjs-e2e-and-db.md` |
| OpenAPI, web types, and Flutter DTOs agree | `05-contract-tests.md` |
| Fixtures, builders, clocks, ids, test data | `06-fixtures-and-data.md` |
| A test that passes and fails on the same code | `07-flaky-tests.md` |
| A bug report or log that needs a failing test | `08-bug-to-failing-test.md` |
| Hunt edge cases nobody specified, or turn an exploratory finding into a test | `09-exploratory-testing.md` |
