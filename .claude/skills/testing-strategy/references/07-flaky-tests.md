# Flaky tests

Scope: the kit's flaky-test policy in full, how to measure a suspected flake, and a diagnosis checklist for each of the five classes the SKILL.md report format names (time, order, shared state, network, unawaited async). The policy is a kit rule. The stack rules it leans on are linked, not restated: test doubles and boundaries in `01-levels-by-stack.md`, waiting and the clock in `02-playwright-web.md`, database isolation in `04-nestjs-e2e-and-db.md`, and fixtures in `06-fixtures-and-data.md`.

## The policy

Kit rules:

1. **Definition.** A test that fails and then passes with no change to the code under test, the test, or its inputs is flaky.
2. **Flaky is a bug.** Either the test is wrong (it depends on something it does not control) or the code is (a real race, an ordering assumption). Both are reported the same way until the cause is known.
3. **The agent reports, and never hides it.** Report with the run count (failed N of M), the exact command, the failing output, and the likely class with its evidence, in the SKILL.md "Flaky report format". hawkeye writes the fix when the cause is in a test; a cause in the code goes to thor with the failing test as the reproduction.
4. **No retry, skip, or quarantine by an agent.** Never add `retries`, `test.skip`, `skip:`, `@Skip`, a longer timeout, or a sleep to make a flake pass (AGENTS.md rule 9).
5. **Only Dave quarantines.** A quarantine has a linked issue and an expiry date, and the test keeps running in a non-blocking job so its rate stays visible. An expired quarantine is a failure.
6. **Framework retries stay at 0** unless a project ADR sets them (`02-playwright-web.md`, "Retries, traces, and the CI flags"). With retries on, a pass on retry is still reported as flaky.
7. **Fixed means measured.** A flake is closed only after the same repeat command that showed it passes every run, and the report gives both counts.

## Measure first

Run the one test many times before naming a class. A single rerun that passes proves nothing.

| Stack | Repeat one test | Notes |
| --- | --- | --- |
| Web, Playwright | `npx playwright test <file> -g "<name>" --repeat-each=50 --retries=0` | `--repeat-each` per `02-playwright-web.md`; add `--workers=1` to separate a parallelism cause from the rest |
| React or NestJS, Vitest or Jest | `for i in $(seq 1 50); do if ! npx vitest run <file> -t "<name>"; then echo "FAIL run $i"; fi; done` | Use the runner the repo already has (`04-nestjs-e2e-and-db.md`); for Jest, `npx jest <file> -t "<name>"` |
| Flutter | `for i in $(seq 1 50); do if ! flutter test <file> --plain-name "<name>"; then echo "FAIL run $i"; fi; done` | Run the whole file too: a test that passes alone and fails in its file is the order or shared-state class |

Then vary one thing at a time: alone versus in the full suite, one worker versus many, a loaded machine versus an idle one, a fixed clock versus the wall clock. The variable that changes the rate is the evidence for the class.

All runs are local. Nothing here runs against a shared or live system.

## Diagnosis by class

### Time

Signs: fails near midnight, a month end, a DST change, or on a slow CI runner; passes when the machine is idle.

- [ ] The code under test reads time from an injected clock, not the wall clock (`06-fixtures-and-data.md`, "Deterministic clocks and ids").
- [ ] The test names the time zone and uses instants on each side of any cutoff.
- [ ] No fixed sleep stands in for an event. Browser tests wait on a locator or a response, never a timeout (`02-playwright-web.md`).
- [ ] Timeouts in the code under test are injected or faked in the test, not waited out.

### Order

Signs: passes alone, fails in the suite, or the reverse; changes with test order or with which tests run.

- [ ] Run the file alone, then the suite, then the suite in a different order if the runner supports shuffling. The first pairing that fails names the polluter.
- [ ] No test depends on a row, a file, or a value another test created (Interacting Tests in `06-fixtures-and-data.md`).
- [ ] Setup and teardown run per test, not per file, for anything a test can change.

### Shared state

Signs: changes with worker count; fails when a new test is added nearby.

- [ ] No module-level, static, or top-level mutable value is reused across tests (the per-stack table in `06-fixtures-and-data.md`, "No shared mutable state").
- [ ] Each Flutter test builds its own `ProviderContainer`; each React test its own query client; each NestJS e2e test starts from a clean database (`04-nestjs-e2e-and-db.md`).
- [ ] Parallel workers do not share one database, port, or temp directory without a per-worker suffix.
- [ ] Browser tests get a fresh context per test (`02-playwright-web.md`).

### Network

Signs: fails with a connection or timeout error; changes with the network, a VPN, or a third-party outage.

- [ ] The test reaches nothing outside the machine. Mock at the boundary the standard names: MSW for React, a fake repository one layer down for Flutter, a local database for NestJS e2e (`01-levels-by-stack.md`).
- [ ] An unhandled request fails the test loudly instead of reaching the network (MSW's unhandled-request option set to error, or the project's equivalent).
- [ ] A local service the test needs (database, emulator) is ready before the first test, by a readiness check, not a sleep.

### Unawaited async

Signs: fails with "after the test finished" or "disposed" errors, or on an assertion that sees the old value; changes with machine speed.

- [ ] Every future or promise the test starts is awaited before it asserts, and the code under test returns the future it starts instead of firing and forgetting.
- [ ] Flutter: the test pumps until the state it asserts on, and checks `ref.mounted` paths where the code has them. `pumpAndSettle` waits for frames only (`03-flutter-integration.md`, "Timing").
- [ ] React: assertions on async UI use the testing library's async queries, not a synchronous query after an action.
- [ ] Timers and streams opened by the test are closed in teardown.

## When the cause is in the code

If the class points at the product code (a real race, an unawaited write, an order assumption between two requests), the flake is a bug report, not a test fix. Write the deterministic test that forces the bad interleaving (for NestJS, `04-nestjs-e2e-and-db.md` step 5 forces the window with two explicit transactions), confirm it fails every run, and hand it to thor. Then follow `08-bug-to-failing-test.md`.

## Sources

- John Micco, "Flaky Tests at Google and How We Mitigate Them", Google Testing Blog, 27 May 2016, verified 2026-11-08. Cited for the topic; no statistic or claim above is taken from it. https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html
- Kit references: `01-levels-by-stack.md`, `02-playwright-web.md`, `03-flutter-integration.md`, `04-nestjs-e2e-and-db.md`, `06-fixtures-and-data.md`, which carry their own sources for the framework behavior linked above.
