# Levels by stack

Scope: how to choose the level of a test, where each stack's test files go, and how one contract's invariants spread across Flutter, React or Next.js, and NestJS. The per-layer rules are in each stack standard; this file indexes them and adds the cross-stack plan. It does not restate a standard's matrix.

## Choosing a level

From Fowler (Vocke), "The Practical Test Pyramid":

- Write tests with different granularity, and the more high-level a test is, the fewer of them you should have. Lots of small, fast unit tests, some coarser tests, very few end-to-end tests.
- Push tests as far down the pyramid as you can.
- If a higher-level test finds an error and no lower-level test fails, write the lower-level test.
- Avoid duplication across levels. A higher-level test covers only what the lower levels could not, such as whether an endpoint answers HTTP at all.
- Do not get attached to layer names. A UI can be unit tested in a modern framework, so "UI test" does not mean "top of the pyramid".

Kit reading of that: the level is chosen by what the test must prove, not by what kind of code it touches. The decision table in SKILL.md is the short form.

## Where each stack's rules and files are

| Stack | Rules for each layer | Where files go |
| --- | --- | --- |
| Flutter | [`flutter-standards` 12, 7.1 The test matrix](../../flutter-standards/references/12-testing.md), with 7.4 to 7.9 for each layer and 7.10 for what to test | The "Where" column of 7.1. Flow tests in `test/flows/`, the same flow on a device in `integration_test/` (7.9, and `03-flutter-integration.md`) |
| React and Next.js | [`react-standards` 05, 4.9 Testing](../../react-standards/references/05-rules.md); async races in [07](../../react-standards/references/07-async-correctness.md); the gate in [12, 11.9](../../react-standards/references/12-enforcing-this-automatically.md) | 4.9 DEFAULT: tests next to the code, end-to-end specs in `e2e/`, accessibility in `*.a11y.test.tsx` |
| NestJS | [`nestjs-standards` 05, 4.11 Testing](../../nestjs-standards/references/05-rules.md); concurrency in [07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) | 4.11 DEFAULT: `*.spec.ts` next to the code, e2e in `test/`. The NestJS docs suggest the `.e2e-spec` suffix for files in `test/` |

The skill's `paths` cover these locations, so it loads when any of those files is open.

## One contract, three stacks

A contract invariant is proven once, at the lowest level that can show it, in the stack that owns it. Clients then prove they handle the outcome, not the rule.

Worked example, invariant "an order can be cancelled only while it is pending, and only by its owner":

| Claim | Stack | Level | Why this level |
| --- | --- | --- | --- |
| The status rule (pending to cancelled, nothing else) | NestJS | Unit | Branching business rule, 4.11 REQUIRED list |
| The update is guarded and the affected-row count is checked | NestJS | e2e, real database | Only a real database runs the `WHERE status = 'pending'` predicate ([07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md), item 2) |
| Two cancels at once: exactly one succeeds | NestJS | Concurrency test | 07 "Test it", see `04-nestjs-e2e-and-db.md` |
| User B gets 404 for user A's order | NestJS | e2e | The owner scope lives in the query, so a unit test with a mocked client cannot see it |
| The error body is `{ code, message, requestId }` | NestJS | e2e | The shape is part of the contract ([05, 4.3](../../nestjs-standards/references/05-rules.md)) |
| Web shows the conflict message for that `code` | React | Component test with MSW | Network boundary mock, 4.9 |
| Web double submit sends one request | React | Component test | Async race, react 07 |
| Mobile notifier ignores a double tap and maps the error | Flutter | Notifier test | 7.1 Notifier row |
| Mobile screen shows loading, error, empty, loaded | Flutter | Widget test | 7.1 Widget row |
| The DTOs on both clients decode the server's examples | Both clients | Contract test | `05-contract-tests.md` |
| A user can cancel from the order screen | One of web or mobile, only if this is the app's critical flow | Playwright or `integration_test` | Fowler: very few end-to-end tests; 4.9 and 7.9 name which flows earn one |

What the example leaves out on purpose: no client re-tests the status rule, and no end-to-end test re-checks the 404. Both are covered lower down.

## Planning the Tests section of a contract

1. List every invariant and every failure path in the contract.
2. For each, write one row: the claim, the stack, the level, the file location from the table above.
3. For each invariant test, name the sabotage that must make it fail (`flutter-standards` 12, 7.3 is the model for all three stacks).
4. Add the contract tests (`05-contract-tests.md`) when the contract changes an endpoint or DTO.
5. Add an end-to-end row only for a journey 4.9 or 7.9 names as critical. If the list grows past two or three, look for missing lower-level tests (7.9).
6. Mark each row with who writes it. Tests are written in test files only, never by patching production code to make them pass.

## Signs a test is at the wrong level

| Sign | Likely fix |
| --- | --- |
| An end-to-end test asserts a validation message for each of ten inputs | Move the cases to a unit test of the schema, keep one end-to-end path |
| A unit test mocks five collaborators to check one branch | Separate the rule from the I/O and test the rule alone ([`nestjs-standards` 05, 4.4](../../nestjs-standards/references/05-rules.md) DEFAULT) |
| A React test stubs the query hook | Mock the network with MSW instead (4.9) |
| A NestJS e2e test overrides the database provider | Use the real database (4.11); override only what leaves the system, such as an email sender |
| A higher-level test fails and no lower-level test does | Write the lower-level test (Fowler) |

## Sources

- Ham Vocke, "The Practical Test Pyramid", martinfowler.com, published 26 February 2018 (final installment), read 2026-11-04. https://martinfowler.com/articles/practical-test-pyramid.html
- NestJS documentation, "Testing" (end-to-end testing hint on the `test` directory and `.e2e-spec` suffix), docs source at commit dc23b40 of 2026-10-27, read 2026-11-04. https://docs.nestjs.com/fundamentals/testing and https://github.com/nestjs/docs.nestjs.com/blob/master/content/fundamentals/unit-testing.md
