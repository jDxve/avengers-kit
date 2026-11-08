# NestJS e2e and the test database

Scope: NestJS end-to-end tests over HTTP against a real PostgreSQL database, how that database is created and migrated for each run, how tests are kept independent, and how a concurrency guard is tested. The rules are [`nestjs-standards` 05, 4.11 Testing](../../nestjs-standards/references/05-rules.md) (e2e against a real, containerized or disposable database; every concurrency guard tested with two operations on the same row) and [`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) (which mechanism fits which invariant). Schema, transactions, and migration design belong to the `database-drizzle` skill; this file covers only what a test needs.

## The e2e harness

From the NestJS testing docs:

- Build the module with `Test.createTestingModule({ imports: [AppModule] }).compile()`, then `moduleRef.createNestApplication()` and `await app.init()`. `compile()` alone creates no HTTP adapter, so anything that needs `httpAdapter` needs `createNestApplication()`.
- Send requests with Supertest: `request(app.getHttpServer()).post('/orders/o1/cancel')`. The request is handled as a real HTTP request would be.
- Close the app in `afterAll` with `await app.close()`, as every docs example does.
- Keep e2e files in `test/` with the `.e2e-spec` suffix (docs hint; 4.11 DEFAULT also puts e2e in `test/`).
- Newly generated Nest projects use Vitest by default, and the testing APIs do not depend on the runner. Use the runner the repo already has.

What to override: the docs show `overrideProvider(...)` to replace a provider with a test double. In this kit, e2e overrides only what leaves the system (an email sender, a payment provider, a push service). The database is never overridden; 4.11 requires the real one.

## A disposable database per run

1. **Create it fresh.** A containerized PostgreSQL started by the CI job or the test setup, or a new database on a local server, named for the run. It is never a shared, staging, or production database (AGENTS.md rule 10; 4.4 forbids `drizzle-kit push` against anything but a local disposable database).
2. **Refuse the wrong target.** Global setup reads the connection URL and stops before connecting unless the host and database name match the test pattern the project sets (for example a database name ending in `_test` on `localhost`). A typo in an environment variable must not truncate a real database (kit rule).
3. **Apply the committed migrations** with `drizzle-kit migrate`, not `push`. Per the Drizzle docs, `migrate` reads the `.sql` files in the migrations folder, reads the applied list from the database, applies the ones not yet applied, and logs them in `__drizzle_migrations` (schema `drizzle` by default). A test config can be passed with `--config=drizzle-test.config.ts`.
4. **Why migrate on every run:** an empty database migrated from zero proves the committed migrations build the schema the code expects, which is the same path the deploy step takes (4.4).
5. **Seed with builders**, not a shared dump (`06-fixtures-and-data.md`).
6. **Throw it away.** Teardown stops the container or drops the database, also when a test fails, so the next run starts from step 1.

## Who may run the suite

Dave's decision of 2026-11-08 (kit rule):

- An agent may run the project's e2e command (for example `npm run test:e2e`), which applies the migrations, only when the suite creates its database for that run and throws it away afterwards: steps 1, 2, and 6 above are all in the suite's own setup and teardown, or in the CI job.
- If the suite points at a database that outlives the run, such as a long-lived local development database, or the agent would have to create the database itself, the agent does not run it. It writes the command and the expected result, and Dave runs it.
- The migrations are applied by the suite, never by a command the agent types. Agents never run `drizzle-kit push`, `migrate`, `pull`, `studio`, `psql`, or a seed, even against a local database (`database-drizzle` SKILL.md, "Rules that never bend").

## Keeping tests independent

Three ways, each with a cost. Pick per suite and write the choice in the suite's setup comment.

| Strategy | How | Fits | Does not fit |
| --- | --- | --- | --- |
| Transaction rollback | Open a transaction before the test, pass it as the executor, roll back after | Service-level integration tests where the service accepts `tx: Executor = this.db` (4.4) | HTTP e2e, where the app uses its own pool; concurrency tests |
| Truncate | `TRUNCATE` the touched tables after each test or file. `CASCADE` also truncates tables with foreign keys to them; `RESTART IDENTITY` resets their sequences | HTTP e2e; concurrency tests | Parallel workers sharing one database: `TRUNCATE` takes an `ACCESS EXCLUSIVE` lock that blocks every other operation on the table |
| Database per worker | Each runner worker gets its own migrated database | Parallel e2e | Suites where migration time per worker dominates the run |

Why rollback does not fit HTTP e2e or concurrency tests, from the PostgreSQL docs on isolation:

- Read Committed is PostgreSQL's default isolation level. A query sees only data committed before it began and never sees uncommitted changes from a concurrent transaction. Rows a test inserted inside an open transaction are invisible to the application's own pool connections and to a second test connection, so the test would be checking a different world from the one the app sees.
- Sequence changes (and so `serial` and identity values) are visible to all transactions at once and are not rolled back. After a rollback, the next id is not the one a test expects. Never assert on a literal generated id; assert on the id the response returned.

## Concurrency tests

07 says a guard with no test is a hope: fire two concurrent calls at the same row and assert that exactly one succeeds. To make that test honest:

1. **Seed committed data** (truncate strategy, not rollback), so both operations see the same row.
2. **Use two separate connections or two HTTP requests in flight together**, for example `await Promise.allSettled([cancel(), cancel()])`. Two calls awaited one after the other test nothing.
3. **Assert the outcome, not just one status:** exactly one success, the other a conflict with its error `code` ([05, 4.3](../../nestjs-standards/references/05-rules.md) error shape), and the final row state read back from the database.
4. **Prove the race happened.** Remove the guard (the `WHERE status = 'pending'` predicate, the `version` check, or the affected-row count check from 07) and run the test. It must fail. If it still passes, the two operations did not overlap, and the test proves nothing.
5. **Force the window when it does not overlap.** Open two explicit transactions from the test, run both reads, then both writes, so the interleaving is the one the guard exists for. This is deterministic, which also keeps the test from becoming flaky.
6. **Under Repeatable Read or Serializable**, PostgreSQL may abort one transaction with a serialization failure, and the docs say applications must be prepared to retry. Test that the code retries or maps the failure to the contract's error, whichever the contract says.

The CI gate for these tests is [`nestjs-standards` 11, "Concurrency guards"](../../nestjs-standards/references/11-enforcing-this-automatically.md): a migration that adds a status or balance column with no constraint, index, or concurrency test is a review comment, not a merge.

## Sources

- NestJS documentation, "Testing" (unit testing, end-to-end testing, overriding providers and enhancers), docs source file `content/fundamentals/unit-testing.md` at commit dc23b40 of 2026-10-27, read 2026-11-04. https://docs.nestjs.com/fundamentals/testing and https://github.com/nestjs/docs.nestjs.com/blob/master/content/fundamentals/unit-testing.md
- PostgreSQL documentation, "13.2. Transaction Isolation", PostgreSQL 18 (current), read 2026-11-04. https://www.postgresql.org/docs/current/transaction-iso.html
- PostgreSQL documentation, "TRUNCATE", PostgreSQL 18 (current), read 2026-11-04. https://www.postgresql.org/docs/current/sql-truncate.html
- Drizzle ORM documentation, "drizzle-kit migrate", Drizzle v1.0 docs, read 2026-11-04. https://orm.drizzle.team/docs/drizzle-kit-migrate
