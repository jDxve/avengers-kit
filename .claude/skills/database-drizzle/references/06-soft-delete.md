# Soft delete

Scope: when a row is marked deleted instead of removed, and what that costs in every query, every unique index, and the purge job. No kit standard covers soft delete; the rules here are kit rules from this skill's contract (`docs/contracts/kit-skills.md` section 4), with PostgreSQL behavior cited where it applies. Retention and deletion policy is a per-project decision ([`nestjs-standards` 16](../../nestjs-standards/references/16-decisions-this-document-deliberately-doe.md), "Data" and "Privacy").

## When it is justified

Soft delete only when a contract states the need. The needs that count:

- **Restore**: users can undo a delete for a stated period.
- **Audit**: a record must stay readable to auditors after users stop seeing it, and the audit trail alone does not hold enough ([`nestjs-standards` 10](../../nestjs-standards/references/10-production-readiness.md), "Audit trail on privileged mutations").
- **Legal hold**: the project is required to keep the data for a period.

"We might need it later" is not a need. Without a stated need, delete the row, and let the audit trail record that it happened. Soft delete also keeps personal data that a user asked to be removed, so the contract names how a deletion request is met (the purge below) when the table holds personal data.

## The column

```ts
deletedAt: timestamp({ withTimezone: true }), // NULL means live
```

A nullable timestamp, not a boolean: it records when, which the purge job needs. Who deleted it goes in the audit trail.

## Every query excludes deleted rows

Every read of the table excludes deleted rows unless the use case is restore, audit, or purge. One helper, next to the tenant helper and combined with it:

```ts
// src/database/scopes.ts
export const live = (deletedAt: PgColumn) => isNull(deletedAt);

db.select().from(documents)
  .where(and(inTenant(documents.tenantId, ctx.tenantId), live(documents.deletedAt), eq(documents.id, id)))
  .limit(1);
```

- Reads that must see deleted rows (restore, audit, purge) are named for it (`findDeletedForRestore`) and covered by their own authorization.
- Joins exclude deleted rows on both sides, or a deleted parent's children still show.
- A delete becomes an update that sets `deletedAt`, scoped by tenant and checked by row count like any conditional update (`03-transactions.md`).
- Foreign keys do not know about `deletedAt`. A live child pointing to a soft-deleted parent is allowed by the database, so the contract says what happens to children: soft-delete them in the same transaction, block the delete while live children exist, or leave them.

The test: seed one live and one deleted row for the same tenant, and assert that every list, search, count, export, and lookup by id returns only the live one (kit rule; the same shape as `security-engineering` `SEC-API-02`).

## Every unique index excludes deleted rows

A plain unique constraint counts deleted rows, so a user cannot create `invoice 1001` again after deleting it, or, worse, the app works around it by skipping the constraint. Use a unique partial index instead. From the PostgreSQL docs: a unique constraint cannot cover only some rows, but a unique partial index can, and it enforces uniqueness only among rows that satisfy its predicate.

```ts
}, (t) => [
  uniqueIndex('documents_tenant_number_live_uq')
    .on(t.tenantId, t.number)
    .where(sql`${t.deletedAt} IS NULL`),
]);
```

- The tenant column stays in the index (`07-tenant-scoping.md`).
- A partial index is not a constraint, so the duplicate-key mapper matches the index name (`01-schema-design.md`, naming).
- A foreign key cannot reference columns covered only by a partial unique index (the PostgreSQL constraints chapter requires a primary key, a unique constraint, or a non-partial unique index), so referenced keys keep a plain unique constraint.
- The PostgreSQL docs on partial indexes note the planner uses one only when the query's `WHERE` implies the predicate, matched at planning time. A query through `live()` writes `deleted_at IS NULL`, which matches.

## Restore

Restore clears `deletedAt`, scoped by tenant and checked by row count. It can collide with a live row created since the delete, which the partial unique index rejects. The contract names the error code the client branches on (`api-contract` `04-errors-and-versioning.md`).

## Purge

Rows past the retention period are deleted for real, by a scheduled job:

- The retention period comes from the contract or the project's data policy (`nestjs-standards` 16), never from code defaults.
- The job deletes in batches, each its own short transaction, and is idempotent (`05-expand-and-contract.md`, "The backfill", for the same batch rules).
- It runs once across instances ([`nestjs-standards` 08](../../nestjs-standards/references/08-multi-instance-gotchas.md)).
- It logs a count per run, never the rows ([`nestjs-standards` 05, 4.7](../../nestjs-standards/references/05-rules.md)).
- A legal hold excludes rows from the purge, and the hold is data, not a code change.

## Review questions

1. Which contract line states the need?
2. Does every read of the table go through `live()`, except restore, audit, and purge?
3. Does every unique index on the table carry `WHERE deleted_at IS NULL`?
4. What happens to children of a deleted row?
5. Who purges, when, and is the retention period written down?

## Sources

- PostgreSQL documentation, "11.8. Partial Indexes" (Example 11.3, partial unique index; planner matching), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/indexes-partial.html
- PostgreSQL documentation, "5.5. Constraints" (unique constraints, foreign keys reference a non-partial unique index), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/ddl-constraints.html
- Drizzle ORM documentation, "Indexes & Constraints" (`uniqueIndex(...).on(...).where(...)`), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/indexes-constraints
- Kit standards: `nestjs-standards` 05 (4.7), 08, 10, 16; `api-contract` `04-errors-and-versioning.md`; `security-engineering` `20-api.md`.
