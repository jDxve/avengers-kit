# Migrations

Scope: how a migration is generated, read, reviewed, and handed over for the controlled deploy step, and what to do with SQL that drizzle-kit does not generate. The rules are owned by [`nestjs-standards` 05, 4.4](../../nestjs-standards/references/05-rules.md) (generate, review, commit, apply by a controlled step; `push` only against a local disposable database) and `devops-engineering` [SKILL.md](../../devops-engineering/SKILL.md) "Database" (the `migrate` image target, forward-only, expand, deploy, contract, reversibility stated). ADR-012 fixes Drizzle and drizzle-kit. The review checklist is `DB-MIG-01` to `DB-MIG-09` in this skill's SKILL.md; this file is the background for it.

## Who runs what

| Step | Who | Against |
| --- | --- | --- |
| Change the schema, `npx drizzle-kit generate`, read the SQL | Agent or Dave | No database: generate reads the schema and the previous snapshots, and the kit's settings allow it |
| `drizzle-kit check` | Agent or Dave | No database: it checks the migration history in the folder |
| `drizzle-kit migrate` or `push`, `psql`, a seed, or any other command against a local disposable database | Dave, never an agent (Dave's decision of 2026-11-08). The kit's settings deny `drizzle-kit push`, `migrate`, `pull`, `studio`, and `psql` to every agent, so the agent writes the command and the expected result | Local disposable database only. `push` only for prototyping, never to produce a committed change |
| The NestJS e2e suite, which applies the committed migrations to its own database | An agent only when the suite creates that database for the run and throws it away afterwards; otherwise Dave (Dave's decision of 2026-11-08) | A database created for the run (`testing-strategy` `04-nestjs-e2e-and-db.md`, "Who may run the suite") |
| `drizzle-kit migrate` from the `migrate` image | Dave, through the controlled deploy step | Shared, staging, production |
| A backfill or a step that must run outside the migrator | Dave, from a runbook (`devops-engineering` `assets/runbook-template.md`) | Shared, staging, production |

The Drizzle docs describe `push` as fit for rapid prototyping and report teams using it as their production flow. The kit rule is stricter: 4.4 and `devops-engineering` allow it only against a local disposable database.

## Generate

From the Drizzle docs for `drizzle-kit generate`:

1. It reads the schema files and builds a JSON snapshot.
2. It compares that snapshot with the most recent one in the migrations folder.
3. It prompts for renames where a change could be a rename or a drop and add.
4. It writes `migration.sql` and `snapshot.json` into a new folder named with a timestamp under the `out` folder (default `./drizzle`).

Consequences:

- Commit the schema change, `migration.sql`, and `snapshot.json` together. The next `generate` diffs against that snapshot.
- Answer every rename prompt on purpose. Choosing "create" for a renamed column generates a drop and an add, which loses the column's data. A rename of something the deployed code reads goes through `05-expand-and-contract.md` instead.
- `--name=<name>` names the migration. Name it for the change (`orders_add_cancelled_at`).
- `npx drizzle-kit check` checks the consistency of the migration history, which matters when two branches both changed the schema. Run it before a merge (DB-MIG-01).

## Read the SQL

Every generated statement is read before it is committed. For each, note the lock and whether it rewrites or scans the table. From the PostgreSQL `ALTER TABLE` page, PostgreSQL 18:

| Statement | Lock and cost |
| --- | --- |
| `ALTER TABLE` in general | `ACCESS EXCLUSIVE` unless the subform says otherwise; with several subcommands, the strictest one applies. `ACCESS EXCLUSIVE` is the only mode that blocks a plain `SELECT` (Explicit Locking chapter) |
| `ADD COLUMN` with no default, or a non-volatile default | No table rewrite; the default is stored in metadata |
| `ADD COLUMN` with a volatile default (such as `clock_timestamp()`), a stored generated column, or an identity column | Rewrites the table and its indexes |
| `ALTER COLUMN ... TYPE` | Normally rewrites the table and its indexes, with exceptions for binary-coercible changes |
| `SET NOT NULL` | Scans the whole table, unless a valid `CHECK` constraint already proves no NULLs |
| `ADD CONSTRAINT` (check, foreign key) | Scans the table to validate existing rows. `ADD FOREIGN KEY` takes `SHARE ROW EXCLUSIVE` on both tables |
| `ADD CONSTRAINT ... NOT VALID`, then `VALIDATE CONSTRAINT` | The add skips the scan and applies to new rows at once; the validate scans with only `SHARE UPDATE EXCLUSIVE`, which does not block writes. Allowed for foreign key, check, and (PostgreSQL 18) not-null constraints |
| `CREATE INDEX` | Blocks writes, not reads, until done |
| `CREATE INDEX CONCURRENTLY` | Does not block writes; slower; cannot run inside a transaction block (from the `CREATE INDEX` page) |

Set `lock_timeout` at the top of a migration that takes `ACCESS EXCLUSIVE` on a busy table, so it fails instead of waiting without limit for a lock (PostgreSQL `lock_timeout`, off by default). The value is Dave's decision, and the runbook says what to do when it fires (kit rule).

## Patterns for a table with rows

**A required column (DB-MIG-03).** In three migrations, or two releases when code must write the value first:

1. Add the column nullable, or with a constant default.
2. Backfill existing rows in batches (`05-expand-and-contract.md`).
3. `ADD CONSTRAINT <name> CHECK (<col> IS NOT NULL) NOT VALID`, then `VALIDATE CONSTRAINT <name>`, then `SET NOT NULL`, which skips its scan because the valid check proves it, then drop the check. These are custom SQL (below), and the schema change to `.notNull()` is generated in the same step so the snapshot matches.

**An index (DB-MIG-04).** `CREATE INDEX CONCURRENTLY` in a migration with no other statement. The Drizzle index builder has `.concurrently()`. The Drizzle pages read for this skill do not say whether `drizzle-kit migrate` runs a migration inside a transaction. Dave finds out on the local disposable database: if PostgreSQL rejects the statement because it is inside a transaction block, the index becomes a runbook step Dave runs, and the schema declaration is generated so the snapshot agrees. From the `CREATE INDEX` page: if a concurrent build fails, it leaves an `INVALID` index that is ignored by queries but still costs every write. Drop it and build again. A failed concurrent unique index keeps enforcing uniqueness.

**A foreign key on a large table.** `ADD CONSTRAINT ... NOT VALID`, then `VALIDATE CONSTRAINT` in a later migration, and an index on the referencing columns (`01-schema-design.md`).

**A data change (DB-MIG-05).** Never in the same migration as DDL on the same table. A small, fixed data change can be a `--custom` migration. A backfill over many rows is a batched job or a runbook step, because it holds locks and time the deploy step should not.

## Custom SQL migrations

From the Drizzle docs: `drizzle-kit generate --custom --name=<name>` writes an empty migration for SQL that drizzle-kit does not generate, or for seeding, and `drizzle-kit migrate` runs it with the others. Use it for:

- `NOT VALID` constraints and `VALIDATE CONSTRAINT`.
- Row-level security when a project chose it, if the schema declarations do not cover it (`07-tenant-scoping.md`).
- Small, fixed reference data.

Keep each custom migration to one purpose, and write in a comment at its top why drizzle-kit could not generate it (kit rule).

An agent may write the body of a new custom migration it created with `--custom`. It never edits a migration that is already committed, generated or custom; a correction is a new migration. Dave runs it like any other (Dave's decision of 2026-11-08).

## Reversibility and release

- Drizzle migrations are forward-only; rolling back the app does not undo them (`devops-engineering` Database). The PR states whether each migration is reversible, and a destructive one names the backup Dave takes first (DB-MIG-07).
- A migration ships ahead of the code that needs it, as part of expand, deploy, contract (`05-expand-and-contract.md`; [`nestjs-standards` 10](../../nestjs-standards/references/10-production-readiness.md) Delivery).
- The deploy step runs `drizzle-kit migrate` once per deploy from the `migrate` image target, never from each app instance (`devops-engineering` Artifacts and Database).

## Prove it locally

Before review: on a fresh local test database, the committed migrations applied from zero, then the e2e suite (DB-MIG-08; setup and the wrong-target guard in `testing-strategy` [`04-nestjs-e2e-and-db.md`](../../testing-strategy/references/04-nestjs-e2e-and-db.md)). An agent runs the e2e suite itself only when the suite creates that database for the run and throws it away afterwards; otherwise it writes the commands and the expected result, and Dave runs them. An agent never applies the migrations by a command of its own. Say in the report that this proves the migrations build the schema, not how long they lock a table with production data, which only a run against a copy of that data can show, and that is Dave's to run.

## Sources

- Drizzle ORM documentation, "drizzle-kit generate", "drizzle-kit migrate", "drizzle-kit push", "drizzle-kit check", "Custom migrations", and "Migrations" fundamentals, Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/drizzle-kit-generate, https://orm.drizzle.team/docs/drizzle-kit-migrate, https://orm.drizzle.team/docs/drizzle-kit-push, https://orm.drizzle.team/docs/drizzle-kit-check, https://orm.drizzle.team/docs/kit-custom-migrations, https://orm.drizzle.team/docs/migrations
- Drizzle ORM documentation, "Indexes & Constraints" (`.concurrently()`), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/indexes-constraints
- PostgreSQL documentation, "ALTER TABLE" (lock levels, `NOT VALID`, `VALIDATE CONSTRAINT`, rewrites), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/sql-altertable.html
- PostgreSQL documentation, "CREATE INDEX" (building indexes concurrently), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/sql-createindex.html
- PostgreSQL documentation, "13.3. Explicit Locking", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/explicit-locking.html
- PostgreSQL documentation, "19.11. Client Connection Defaults" (`lock_timeout`), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/runtime-config-client.html
- Kit standards: `nestjs-standards` 05 (4.4), 10; `devops-engineering` SKILL.md and `assets/runbook-template.md`; `testing-strategy` `04-nestjs-e2e-and-db.md`; ADR-012.
