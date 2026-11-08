# Indexes and queries

Scope: which index serves which query, how to read a query plan, and the query shapes that go wrong (N+1, unbounded lists). The rules are owned by [`nestjs-standards` 05, 4.4](../../nestjs-standards/references/05-rules.md): every list has `.limit()`, index foreign keys used in joins or filters, validate indexes against real plans, and watch for an `await` inside a `.map()`. Pagination semantics are [12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) and the `api-contract` skill. This file adds the PostgreSQL detail and the review steps. Profiling beyond the database is the `observability-and-debugging` skill.

## Which index for which query

| Query shape | Index | Why |
| --- | --- | --- |
| Join or filter on a foreign key | Index on the referencing column | PostgreSQL does not create it for you (PostgreSQL constraints chapter); without it a parent delete and every join scan the child table |
| List filtered by tenant or owner, sorted | Multicolumn B-tree, equality columns first, then the sort column: `(tenant_id, created_at, id)` | A multicolumn B-tree is most efficient with constraints on its leading columns |
| Unique among live rows only | Unique partial index | See `06-soft-delete.md` |
| A query that only ever reads a small, fixed subset (`status = 'pending'`) | Partial index with that predicate | Smaller index, cheaper writes; usable only when the query's `WHERE` implies the predicate |
| Case-insensitive lookup | Expression index, for example `lower(email)` | The Drizzle `.using('btree', sql\`lower(${t.email})\`)` form |

From the PostgreSQL docs on multicolumn indexes: equality constraints on the leading columns, plus an inequality on the first column without an equality, limit the part of the index scanned. Constraints on columns to the right are checked in the index but do not necessarily narrow the scan. PostgreSQL 18 can also apply a skip scan in some cases; do not design for it, measure it.

From the PostgreSQL docs on partial indexes: the planner uses a partial index only when it can prove the query's `WHERE` implies the index predicate, at planning time, so a parameterized condition (`x < $1`) does not match a predicate such as `x < 2`. Write the predicate the same way the query writes it. The same page warns against many non-overlapping partial indexes as a substitute for partitioning.

Indexes cost write throughput and storage (4.4 DEFAULT). Add one for a query you can name, and show the plan before and after.

## Declaring an index in Drizzle

```ts
export const orders = pgTable('orders', {
  id: uuid().defaultRandom().primaryKey(),
  tenantId: uuid().notNull().references(() => tenants.id),
  customerId: uuid().notNull().references(() => customers.id),
  status: orderStatus().notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, (t) => [
  index('orders_tenant_created_idx').on(t.tenantId, t.createdAt, t.id),
  index('orders_customer_idx').on(t.customerId),
  index('orders_pending_idx').on(t.tenantId).where(sql`${t.status} = 'pending'`),
]);
```

The Drizzle index builder also has `.concurrently()`. Whether to build concurrently is a migration decision, so it is covered in `04-migrations.md` (DB-MIG-04).

## Reading a plan

`EXPLAIN ANALYZE` runs against the local disposable database or a copy Dave provides, never against a shared or live database. The kit's settings deny `psql` to agents, so an agent writes the statement and what to look for, and Dave runs it and returns the plan (AGENTS.md rule 10). From the PostgreSQL "Using EXPLAIN" chapter:

- `EXPLAIN ANALYZE` executes the statement. For an `INSERT`, `UPDATE`, `DELETE`, or `MERGE`, wrap it in `BEGIN; ... ROLLBACK;` so nothing changes.
- `ANALYZE` turns on `BUFFERS` by default, which reports pages hit, read, dirtied, and written per node.
- `actual time` is in milliseconds; `cost` is in arbitrary planner units, so the two do not compare.
- For a node that runs more than once, `loops` counts the runs, and `actual time` and `rows` are per-run averages. Multiply by `loops` for the total.
- The first thing to check is whether estimated rows are close to actual rows. A large gap means the planner chose the plan from a wrong picture of the data.

What to look for, in order:

1. A `Seq Scan` on a large table under a filter or join that should be selective. Usually a missing index or a predicate the index cannot serve.
2. Estimated rows far from actual rows, on any node.
3. A `Nested Loop` whose inner side has a large `loops` value and a non-trivial per-loop time.
4. A `Sort` above a scan for a list endpoint. An index in the sort order can remove it.

Record the plan in the PR or the finding: the query, the plan before, the change, the plan after.

## Query shapes

- **Unbounded list.** Every list query has `.limit()` (4.4), and the maximum page size comes from the query schema (`api-contract` `05-idempotency-and-pagination.md`).
- **N+1.** An `await` inside `.map()` or a `for` loop that queries the database (4.4). Replace it with one query using `inArray(table.id, ids)` or a join, then map the rows in memory. A test that seeds N parents and asserts the number of queries does not grow with N proves the fix (kit rule; count with the driver's query logger in the test).
- **Select only what the response needs.** `db.select({ id: t.id, status: t.status })` instead of the whole row keeps internal columns out of memory and out of the response (`security-engineering` `SEC-API-07`).
- **Stable sort.** A list sorted on a non-unique column also sorts on the id, or pages repeat and skip rows ([`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md)).
- **Tenant first.** Every query on a tenant-owned table goes through the tenant helper (`07-tenant-scoping.md`), which is also what makes the `(tenant_id, ...)` index usable.

## Reporting a slow query

A finding names the endpoint, the query, the plan with row counts, the proposed index or rewrite, and the expected effect on the endpoint's budget. Whoever measured it hands the schema or index change to the owner of the schema, with that finding.

## Sources

- PostgreSQL documentation, "14.1. Using EXPLAIN", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/using-explain.html
- PostgreSQL documentation, "11.3. Multicolumn Indexes", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/indexes-multicolumn.html
- PostgreSQL documentation, "11.8. Partial Indexes", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/indexes-partial.html
- PostgreSQL documentation, "5.5. Constraints" (foreign keys do not index the referencing columns), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/ddl-constraints.html
- Drizzle ORM documentation, "Indexes & Constraints" (index builder, `.where`, `.using`, `.concurrently`), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/indexes-constraints
- Kit standards: `nestjs-standards` 05 (4.4), 12; `api-contract` `05-idempotency-and-pagination.md`; `security-engineering` `20-api.md`.
