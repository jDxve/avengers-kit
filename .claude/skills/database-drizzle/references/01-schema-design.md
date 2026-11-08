# Schema design

Scope: how a table is declared in a NestJS project on Drizzle and PostgreSQL. Where tables live, keys, constraints, enums, money and time columns, and timestamps. The rules are owned by [`nestjs-standards` 05, 4.4](../../nestjs-standards/references/05-rules.md) (constraints, money, time) and [04](../../nestjs-standards/references/04-structure.md) (folders); which constraint protects which invariant is [07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md). This file adds the Drizzle and PostgreSQL detail. Tenant columns are in `07-tenant-scoping.md`; soft delete in `06-soft-delete.md`.

## Where tables live

- One `schema/` folder per domain module, `src/modules/<domain>/schema/`, and `drizzle.config.ts` points its `schema` option at a glob over those folders. Generated migrations go to the root `drizzle/` folder and are committed (`nestjs-standards` 04).
- The Drizzle docs accept a single file, a glob such as `./src/**/schema.ts`, or an array of paths for `schema`. Use the glob the repo already has.
- A table belongs to the module that owns its data. Another module reads it through that module's exported service, not by importing the table ([`nestjs-standards` 05, 4.5](../../nestjs-standards/references/05-rules.md)).

## Keys

- Primary keys: the Drizzle docs show `integer().primaryKey().generatedAlwaysAsIdentity()` for an identity column, and `uuid().defaultRandom().primaryKey()` for a UUID. Pick one per project and record it.
- An id that appears in a URL is guessable when it is sequential. OWASP API Security Top 10 2023, API1, lists "prefer random and unpredictable values as GUIDs for records' IDs" among its preventions. That is a second line only: the first is the owner or tenant filter (`security-engineering` `SEC-API-01`).
- Composite primary keys use the standalone `primaryKey({ columns: [t.a, t.b] })` operator in the table's extra config.

## Constraints

The constraint is the guarantee (4.4). Declare it in the Drizzle table so `drizzle-kit generate` writes it into the migration.

| Invariant | Drizzle | PostgreSQL behavior to know |
| --- | --- | --- |
| Must not exist twice | `.unique()` on a column, or `unique().on(t.a, t.b)` | A unique constraint creates a unique B-tree index. Two NULLs are not equal by default, so rows with a NULL in a constrained column can repeat. `NULLS NOT DISTINCT` (PostgreSQL 15 or later per the Drizzle docs; `.nullsNotDistinct()`) changes that |
| Unique among some rows only | `uniqueIndex('name').on(...).where(sql\`...\`)` | A unique constraint cannot cover only some rows; a unique partial index can (`06-soft-delete.md`) |
| Value in range, or columns consistent with each other | `check('name', sql\`...\`)` | A table check can compare columns of the same row |
| Required | `.notNull()` | Adding it later to a table with rows needs steps (`04-migrations.md`, DB-MIG-03) |
| Reference exists | `.references(() => parent.id)` or `foreignKey({ columns, foreignColumns })` | PostgreSQL does not index the referencing columns for you; a delete or key update on the parent scans the child table. Index them (4.4 DEFAULT) |

On delete behavior, from the PostgreSQL constraints chapter: the default is `NO ACTION`, which rejects the delete while referencing rows exist. `CASCADE` fits a child that cannot exist without its parent (order items under an order). `RESTRICT` or `NO ACTION` fits two independent things (a product and the order lines that name it). `SET NULL` fits an optional link. Write the choice in the contract's data section, because a cascade is a delete the user did not see.

A referencing row with a NULL in any of its foreign key columns escapes the check; with `MATCH FULL`, only a row with all of them NULL escapes. If the link is required, the column is `NOT NULL` as well.

Name constraints when the API maps their violation to a domain error (07 item 1: "catch the violation and map it to a clean domain error"). The mapper matches the constraint name, so give it one on purpose (`unique('orders_tenant_number_unique').on(...)`) rather than depend on a generated one, and cover the mapping with a test.

## Enums

`pgEnum('order_status', ['pending', 'paid', 'shipped'])` creates a PostgreSQL enum type. A text column with a `check` constraint is the alternative. Choose per project and record why. Removing or renaming a value of a type that live rows use is an expand and contract change (`05-expand-and-contract.md`), and adding a value is a change every client must tolerate ([`api-contract` 04](../../api-contract/references/04-errors-and-versioning.md)).

## Money

4.4: integer minor units or an exact decimal type, end to end. In Drizzle:

- Integer minor units: `integer()` or `bigint({ mode: 'bigint' })`. The Drizzle docs say `bigint({ mode: 'number' })` is for values above 2^31 and below 2^53; above that, a JavaScript number loses precision.
- Exact decimal: `numeric({ precision, scale })`. Its `mode: 'number'` maps the value to a JavaScript number, which is binary floating point, so a money column never uses that mode (kit rule, from 4.4).
- Store the currency next to the amount when more than one currency is possible.

## Time

4.4: an unambiguous instant, normally UTC in a timezone-aware column. In Drizzle that is `timestamp({ withTimezone: true })`.

From the Drizzle docs, quoting the PostgreSQL docs: a `timestamp with time zone` is stored in UTC, and an input with no zone is read in the server's `TimeZone` setting. A `timestamp without time zone` silently ignores any zone in the input. So a column without the zone records a wall-clock reading, not an instant.

- `mode: 'date'` maps to a JavaScript `Date`; `mode: 'string'` passes the database string through unchanged. Pick one per project.
- `createdAt` and `updatedAt` on every table that a user or a job changes: `timestamp({ withTimezone: true }).defaultNow().notNull()`. Who changed a row and why is the audit trail's job, not these columns ([`nestjs-standards` 10](../../nestjs-standards/references/10-production-readiness.md), "Audit trail").
- A local calendar rule (a 5 pm cutoff, a pay period) is applied in code with the zone named, and the zone is stored when it is part of the record (4.4).

## Review questions for a new table

1. Which module owns it, and is it in that module's `schema/` folder?
2. Which invariants does the contract name, and which constraint holds each one?
3. Is every foreign key indexed, and is each on delete action written down?
4. Is it tenant-owned (`07-tenant-scoping.md`)? Does it need soft delete, and does a contract say so (`06-soft-delete.md`)?
5. Are money and time columns in the representation 4.4 requires?
6. Which response mapper keeps internal columns out of the API (`security-engineering` `SEC-API-07`)?

## Sources

- Drizzle ORM documentation, "Drizzle schema" (sql-schema-declaration), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/sql-schema-declaration
- Drizzle ORM documentation, "Indexes & Constraints", Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/indexes-constraints
- Drizzle ORM documentation, "PostgreSQL column types" (bigint, numeric, timestamp modes; enum), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/column-types/pg
- Drizzle ORM documentation, "drizzle-kit generate" (schema path globs), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/drizzle-kit-generate
- PostgreSQL documentation, "5.5. Constraints", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/ddl-constraints.html
- OWASP API Security Top 10, 2023 edition, API1:2023 Broken Object Level Authorization, "How To Prevent", read 2026-11-08. https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- Kit standards: `nestjs-standards` 04, 05 (4.4, 4.5), 07, 10; `api-contract` 04; `security-engineering` `20-api.md`.
