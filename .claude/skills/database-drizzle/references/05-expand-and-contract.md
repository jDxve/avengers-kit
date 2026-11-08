# Expand and contract

Scope: how a rename, a type change, a split, or a new required column reaches a live database while the old code is still running, with the backfill in between. The rule is owned by `devops-engineering` [SKILL.md](../../devops-engineering/SKILL.md) "Database" (expand, deploy, contract; forward-only; rollback is the previous image, which the expand step keeps compatible) and "Release", and [`nestjs-standards` 10](../../nestjs-standards/references/10-production-readiness.md) Delivery ("Migrations staged ahead of code"). This file adds the release-by-release steps. The lock and rewrite costs of each statement are in `04-migrations.md`.

## Why several releases

During a deploy, old and new code run against one schema: old instances drain while new ones start, and a rollback redeploys the old image onto the new schema (`devops-engineering` Database). So every schema state must work with two code versions, the one before and the one after. A rename done in one migration breaks whichever version does not know the new name.

Mobile clients make the window longer. An installed app keeps sending old request fields until the minimum supported version moves past it ([`api-contract` 04](../../api-contract/references/04-errors-and-versioning.md)). The database contract step for a field the API still accepts waits for that.

## The pattern for a rename

Example: rename `orders.note` to `orders.customer_note`.

| Release | Migration | Code | Safe to roll back to |
| --- | --- | --- | --- |
| 1. Expand | Add `customer_note`, nullable | Writes both columns; reads `note` | The release before 1, which ignores the new column |
| 2. Backfill | None, or a `--custom` migration for a small table | Same as 1; a batched job copies `note` into `customer_note` where it is NULL | 1 |
| 3. Switch reads | None | Reads `customer_note`; still writes both | 1 or 2, because `note` is still current |
| 4. Stop writing the old column | None | Reads and writes only `customer_note` | 3 |
| 5. Contract | Drop `note` | Same as 4 | 4. Not 3 or earlier: they write `note`, which is gone |

The drop ships in a release after the one that stopped writing the old column, because the migration runs while the previous release is still serving (`devops-engineering` Database). Releases 3 and 4 can be one release when no rollback to a version that reads `note` is planned. Write the choice in the contract's Release section.

In Drizzle terms: in release 1 both columns are in the table declaration, so drizzle-kit generates an `ADD COLUMN`. In release 5 `note` leaves the declaration and the generated SQL must be a `DROP COLUMN` of `note` and nothing else. If drizzle-kit offers a rename at that step, decline it (`04-migrations.md`, rename prompts).

## Other changes in the same shape

- **Type change** (integer cents to `bigint`, `text` to an enum): add a column of the new type, write both, backfill with the conversion, switch reads, drop the old column. Changing the type in place usually rewrites the table under `ACCESS EXCLUSIVE` (`04-migrations.md`).
- **New required column**: add nullable, deploy code that always writes it, backfill, then add the constraint with `NOT VALID` and validate (`04-migrations.md`, "A required column").
- **Split a table**: create the new table, write both, backfill, switch reads, stop writing the old columns, drop them.
- **Remove a column**: stop reading it, deploy, stop writing it, deploy, then drop it. Removing it from the Drizzle declaration and the API response comes first; the drop comes last.
- **Tighten a constraint** (a new unique or check): clean the data first, then add the constraint with `NOT VALID` where the type allows and validate it, so the clean-up and the constraint are separate failures.

## The backfill

- Runs in batches by primary key range, each batch its own short transaction, so no lock is held for the whole table (kit rule; locks and their cost are in `04-migrations.md`).
- Is idempotent: it only touches rows still missing the value (`WHERE customer_note IS NULL`), so it can stop and restart.
- Reports progress and a final count, and is followed by a check query that returns zero rows left.
- Is separate from the schema change (DB-MIG-05). Over many rows it is a job or a runbook step that Dave runs against a live database, never a step an agent runs (AGENTS.md rule 10).
- Is tested with seeded rows, including rows that already have the value: in the e2e suite on a database created for the run, or by Dave on the local disposable database (SKILL.md, "Rules that never bend").

## In the contract

The contract's Release section names, for each release: the migration, the code change, what is safe to roll back to, and whether the step is reversible. The backfill names its batch size, its check query, and who runs it. Use `devops-engineering` `assets/runbook-template.md` for any step Dave runs.

## Sources

- Scott W. Ambler and Pramod J. Sadalage, *Refactoring Databases: Evolutionary Database Design*, edition not verified: not read in this session. Named by the contract as the source for transition periods during which old and new schema coexist; no claim above is attributed to it, and the steps are kit rules built on `devops-engineering` Database.
- PostgreSQL documentation, "ALTER TABLE" (rewrites and locks behind the type-change note), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/sql-altertable.html
- Drizzle ORM documentation, "drizzle-kit generate" (rename prompts), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/drizzle-kit-generate
- Kit standards: `devops-engineering` SKILL.md (Database, Release) and `assets/runbook-template.md`; `nestjs-standards` 10; `api-contract` `04-errors-and-versioning.md`.
