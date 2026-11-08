# Tenant scoping

Scope: how tenant-owned data is kept to its tenant in a NestJS project on Drizzle and PostgreSQL. The kit default is four parts: a tenant column, one scoped query helper, composite keys, and the cross-tenant (IDOR) test. Row-level security is an option a project can choose in its contract, not a kit default (decided by Dave, `kit-skills` OD-10). The rule that every lookup is scoped to the caller's owner or tenant is owned by [`nestjs-standards` 09](../../nestjs-standards/references/09-security-baseline.md) ("IDOR checked") and checked by `security-engineering` `SEC-API-01` and `SEC-API-02` in [20-api.md](../../security-engineering/references/20-api.md). What a tenant is, and what ownership means for each resource, is a per-project decision ([`nestjs-standards` 16](../../nestjs-standards/references/16-decisions-this-document-deliberately-doe.md), "Authorization"). This file adds how the data layer holds that boundary.

The same parts apply when the boundary is an owner rather than a tenant (a user's own orders): read "owner" for "tenant" throughout.

## 1. The tenant column

- Every tenant-owned table has `tenantId`, `NOT NULL`, with a foreign key to the tenants table (kit rule; DB-MIG-09).
- A child table carries its own `tenantId` even when its parent has one. Then every query on the child can filter directly, and the composite key below can hold.
- The tenant id a query uses comes from the authenticated principal, resolved by the guard. Never from the path, the query string, the body, or a header the client sets (kit rule, from 09 and `security-engineering` `SEC-API-01`). A request that names a tenant (an admin switching tenants) is checked against the principal's memberships before it is used.

## 2. One scoped query helper

```ts
// src/database/scopes.ts
import { and, eq, type SQL } from 'drizzle-orm';
import type { PgColumn } from 'drizzle-orm/pg-core';

export type TenantContext = { readonly tenantId: string; readonly userId: string };

export function inTenant(tenantColumn: PgColumn, tenantId: string, ...conditions: (SQL | undefined)[]) {
  return and(eq(tenantColumn, tenantId), ...conditions);
}
```

```ts
// orders.service.ts
findOne(ctx: TenantContext, id: string, tx: Executor = this.db) {
  return tx.select().from(orders)
    .where(inTenant(orders.tenantId, ctx.tenantId, eq(orders.id, id)))
    .limit(1);
}
```

- Service methods on tenant-owned data take a `TenantContext` as their first argument, built by the controller from the principal. A method without one cannot scope, which makes the gap visible in its signature.
- Every select, update, and delete on a tenant-owned table goes through `inTenant`, including joins (each joined tenant-owned table is filtered too) and subqueries.
- Inserts set `tenantId` from the context, never from the request DTO. The request schema has no `tenantId` field, and `.strict()` rejects one (`security-engineering` `SEC-API-03`).
- The helper lives in one place the project chooses (`src/database/` or `src/common/utils/`, which `nestjs-standards` 04 reserves for pure functions); the soft delete helper sits next to it (`06-soft-delete.md`).

A query on a tenant-owned table without the helper is a review finding. Find candidates with `git grep -n "from(<table>)" -- src` and `git grep -n "update(<table>)\|delete(<table>)" -- src`, then read each hit's `where`. The grep only finds candidates; the test below is the proof.

## 3. Composite keys

The database can refuse a cross-tenant reference outright, so a bug in one query cannot link tenant B's row to tenant A's parent.

- **Unique constraints include the tenant column** (kit rule): `unique('invoices_tenant_number_uq').on(t.tenantId, t.number)`. A global unique on `number` would let tenant B learn that A already used a number, and block B from using it.
- **Child foreign keys include the tenant column.** The parent gets a unique constraint on `(tenantId, id)`, and the child references that pair:

```ts
export const orders = pgTable('orders', { /* id, tenantId, ... */ }, (t) => [
  unique('orders_tenant_id_uq').on(t.tenantId, t.id),
]);

export const orderLines = pgTable('order_lines', {
  id: uuid().defaultRandom().primaryKey(),
  tenantId: uuid().notNull().references(() => tenants.id),
  orderId: uuid().notNull(),
}, (t) => [
  foreignKey({ columns: [t.tenantId, t.orderId], foreignColumns: [orders.tenantId, orders.id] }),
  index('order_lines_tenant_order_idx').on(t.tenantId, t.orderId),
]);
```

The PostgreSQL constraints chapter shows this shape: tables keyed on `(tenant_id, ...)`, with a foreign key on `(tenant_id, author_id)` referencing the parent's composite key. A foreign key must reference a primary key or a unique constraint, which is why the parent needs `unique(tenantId, id)`. A line with tenant B and A's order id then fails the foreign key check.

- **List indexes lead with the tenant column**, `(tenant_id, created_at, id)`, so the scoped query can use them (`02-indexes-and-queries.md`).

## 4. The cross-tenant test

The proof that the boundary holds is a NestJS e2e test on a real database (`testing-strategy` [04-nestjs-e2e-and-db.md](../../testing-strategy/references/04-nestjs-e2e-and-db.md)), with the cases `SEC-API-01` and `SEC-API-02` name:

1. Seed tenants A and B, each with a user and a resource, using builders.
2. As B: get, update, and delete A's resource by id. Each returns 404, the same as an id that does not exist, and A's row is unchanged when read back.
3. As B: list, search, count, and export. None contains A's ids.
4. As B: create a child under A's parent id (`POST /orders/<A's id>/lines`). It returns 404, and no row was written.
5. At the database: insert a child with B's tenant id and A's parent id directly through Drizzle. It fails the composite foreign key.
6. As B: send `tenantId: <A>` in a create body. It returns 400 (`SEC-API-03`), and no row exists under A.

Prove the test can fail: remove `inTenant` from one query on a local branch and watch case 2 or 3 fail, then restore it (`testing-strategy`, "Every test has been seen to fail").

## Row-level security: an option, not the default

Decided by Dave (`kit-skills` OD-10): the default is the four parts above. A project may add PostgreSQL row-level security (RLS) as a second line when its contract states why. Reasons that can justify it: more than one service or tool reads the same tables with its own queries, or a compliance requirement asks for enforcement in the database. RLS never replaces the helper and the test; they stay.

What PostgreSQL does, from its "Row Security Policies" section:

- `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` makes every normal read and write of the table pass a policy. With no policy, nothing is visible or modifiable (default deny). `TRUNCATE` and `REFERENCES` are not subject to it.
- **Superusers and roles with `BYPASSRLS` always bypass it, and the table owner normally does too**, unless the table has `FORCE ROW LEVEL SECURITY`. An app that connects as the role that owns the tables, which is common when the same role runs migrations, is not protected until `FORCE` is set or the app connects as a separate role.
- Policies are permissive by default and combine with OR; restrictive policies combine with AND.
- A policy with a `USING` clause and no `WITH CHECK` uses the same expression for new rows, so rows for another tenant cannot be inserted or updated into view.
- Referential integrity checks (unique, primary key, foreign key) always bypass row security, which can leak the existence of rows through a covert channel. Design keys with that in mind.
- A policy that looks up other tables in a sub-`SELECT` can race with a concurrent change to those tables and show a row it should not. Policies that test only the row's own columns, such as `tenant_id`, are the simplest and best-performing case.

How the tenant reaches the policy, from the PostgreSQL docs: `set_config(name, value, is_local)` with `is_local` true applies the value only to the current transaction, and `current_setting(name)` reads it. PostgreSQL accepts any two-part custom setting name (`app.tenant_id`). So the app opens a transaction for each request's database work and sets the tenant first:

```ts
await db.transaction(async (tx) => {
  await tx.execute(sql`select set_config('app.tenant_id', ${ctx.tenantId}, true)`);
  // ... queries for this request, still filtered by inTenant ...
});
```

```sql
-- in a --custom migration (04-migrations.md)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
CREATE POLICY orders_tenant ON orders
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

Setting the value per transaction rather than per session keeps a pooled connection from carrying one request's tenant into the next request (kit rule, from the `is_local` behavior above).

Drizzle can declare RLS in the schema: `pgTable.withRLS(...)`, `pgPolicy(...)` with `as`, `to`, `for`, `using`, and `withCheck`, and `pgRole(...)`. Adding a policy enables RLS on the table. drizzle-kit does not manage roles unless `entities.roles` is enabled in `drizzle.config.ts`. The Drizzle page read for this skill does not show `FORCE ROW LEVEL SECURITY`, so check whether the project's Drizzle version can declare it; otherwise it goes in a `--custom` migration.

If a project chooses RLS, its contract adds:

- Which tables, which role the app connects as, and proof that role is neither the owner without `FORCE` nor `BYPASSRLS`.
- The cross-tenant test above, run twice: once as written, and once with `inTenant` removed from a query on a local branch, where RLS alone must still return 404 or an empty list.
- How migrations, the purge job, and support tooling, which may need to see all tenants, connect and why.

## Sources

- PostgreSQL documentation, "5.9. Row Security Policies", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- PostgreSQL documentation, "5.5. Constraints" (composite keys with `tenant_id`; foreign keys reference a primary key or unique constraint), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/ddl-constraints.html
- PostgreSQL documentation, "9.28. System Administration Functions" (`set_config`, `current_setting`), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/functions-admin.html
- PostgreSQL documentation, "19.16. Customized Options", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/runtime-config-custom.html
- Drizzle ORM documentation, "Row-Level Security (RLS)", Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/rls
- Drizzle ORM documentation, "Indexes & Constraints" (`unique().on`, `foreignKey`), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/indexes-constraints
- OWASP API Security Top 10, 2023 edition, API1:2023 Broken Object Level Authorization ("How To Prevent": check access to the record in every function that uses client input to reach it; write tests and do not deploy changes that fail them), read 2026-11-08. https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- Kit standards: `nestjs-standards` 04, 09, 16; `security-engineering` `20-api.md`; `testing-strategy` `04-nestjs-e2e-and-db.md`.
