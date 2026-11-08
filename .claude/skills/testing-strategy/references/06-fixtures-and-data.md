# Fixtures and test data

Scope: how a test gets the data it needs, across all three stacks. Builders over shared fixtures, no shared mutable state, deterministic clocks and ids, and the rules for personal and secret-shaped data. The doubles each stack uses (`mocktail` and `ProviderContainer` in Flutter, MSW in React, a real database in NestJS e2e) are set by the standards: [`flutter-standards` 12](../../flutter-standards/references/12-testing.md) intro, [`react-standards` 05, 4.9](../../react-standards/references/05-rules.md), [`nestjs-standards` 05, 4.11](../../nestjs-standards/references/05-rules.md).

## Fresh fixture, built by the test

Meszaros, *xUnit Test Patterns*:

- **Fresh Fixture**: each test builds its own fixture for its own private use and does not reuse one left by another test or run. Each test starts and ends with a clean slate, which prevents Erratic Tests.
- **Shared Fixture**: one fixture reused across tests. It runs faster, but it can cause collisions between tests, so one test depends on another's outcome (Erratic Test), and it grows more complex than any one test needs.
- **Creation Method**: hide the mechanics of building a ready-to-use object behind an intention-revealing name, and pass as parameters only what the assertions check or what affects the outcome. Defaults fill everything else.

A builder is a Creation Method with named overrides. One per domain type, in the test helpers folder the stack uses:

```ts
// NestJS or React test helper
export function anOrder(overrides: Partial<Order> = {}): Order {
  return { id: 'order-1', ownerId: 'user-1', status: 'pending', totalMinor: 1250, ...overrides };
}

it('rejects cancelling a shipped order', () => {
  const order = anOrder({ status: 'shipped' }); // the one value this test is about
  expect(() => cancel(order, 'user-1')).toThrow(OrderNotPendingError);
});
```

```dart
// Flutter test helper
Order anOrder({String id = 'order-1', OrderStatus status = OrderStatus.pending}) =>
    Order(id: id, ownerId: 'user-1', status: status, totalMinor: 1250);
```

- The test names only the values it is about. A reader sees `status: 'shipped'` and knows why the test exists.
- Builders return new objects every call. A builder that returns a shared instance is a Shared Fixture in disguise.
- For NestJS e2e, the same builders feed an `insertOrder(db, anOrder({...}))` helper, so the database is seeded per test, not from a shared dump (`04-nestjs-e2e-and-db.md`).

## No shared mutable state

Meszaros lists Interacting Tests as a cause of Erratic Tests: tests that depend on each other, usually through a Shared Fixture or static variables. Symptoms: a test that works alone fails when another test is added or removed, or a test passes in the suite but not alone (Lonely Test).

Check for, per stack:

| Stack | Usual shared state |
| --- | --- |
| Flutter | A top-level or `static` field; a `ProviderContainer` reused across tests instead of built per test; a fake repository instance declared once at file level |
| React | A module-level array the MSW handlers push into; `localStorage` left by a previous test; a query client shared across tests |
| NestJS | Rows left in the database (no truncate, see 04); a singleton provider with in-memory state; a module-level cache |

Each test builds its own instance in its setup. When a file-level value is truly immutable (a `const` map of reference data), it can stay.

## Deterministic clocks and ids

- **Time** comes from an injected source the test controls, never from the wall clock inside the code under test. NestJS: a clock provider overridden in the testing module. Browser: `page.clock` (`02-playwright-web.md`). Flutter: a clock passed in or provided through a Riverpod provider the test overrides with `ProviderContainer`.
- **Zones** are named in the test. `nestjs-standards` 05, 4.4 stores time as an unambiguous instant and applies business-local rules with the zone named in code; a test of a cutoff at 5pm local states the zone and an instant on each side of the cutoff.
- **Ids** in unit tests are fixed strings from the builder. In database tests, the database generates them; assert on the id the response returned, never on a literal, because PostgreSQL sequences are not rolled back (`04-nestjs-e2e-and-db.md`).
- **Random values** (idempotency keys, `uuid`) come from an injected generator in unit tests, so a test can assert the same key is reused on retry, which is what [`flutter-standards` 12, 7.1](../../flutter-standards/references/12-testing.md) Notifier row calls "idempotency intent".

## No real personal data

Kit rule: no fixture holds personal data from production, a log, a support ticket, or a real person. That includes names, emails, phone numbers, addresses, and ids copied from a real system.

- Emails and hosts use the reserved names from RFC 2606: `example.com`, `example.net`, `example.org` for second-level domains, and the `.test` and `.invalid` top-level domains. For example `buyer@example.com`, `api.shop.test`.
- Names are obviously fake (`Test Buyer`, `User B`).
- A bug reproduced from a production log keeps the shape of the data and replaces every personal value before it enters a test (`08-bug-to-failing-test.md`).

## Secret-shaped fixtures

Kit rule, as in `kit-learning-loop` Tests: a fixture that must look like a secret (an API key, a token, a private key header) is assembled at runtime from pieces, so the repository never contains a string a secret scanner flags, and a real-looking secret never needs an exception in the scanner config.

```ts
// assembled at runtime; the file never holds the whole token
const fakeToken = ['tok', 'test', 'x'.repeat(24)].join('_');
```

Never paste a real token, even an expired one, into a test.

## Sources

- Gerard Meszaros, *xUnit Test Patterns: Refactoring Test Code*, 1st edition, Addison-Wesley, 2007 (ISBN 9780131495050; edition per the InformIT product page). Read: the author's companion pages for Fresh Fixture, Shared Fixture, Creation Method, and Erratic Test, which say the book's text has since changed; not the printed book. http://xunitpatterns.com/Fresh%20Fixture.html, http://xunitpatterns.com/Shared%20Fixture.html, http://xunitpatterns.com/Creation%20Method.html, http://xunitpatterns.com/Erratic%20Test.html, https://www.informit.com/store/xunit-test-patterns-refactoring-test-code-9780131495050
- D. Eastlake and A. Panitz, RFC 2606, "Reserved Top Level DNS Names", June 1999 (BCP 32), read 2026-11-04. https://www.rfc-editor.org/rfc/rfc2606.txt
