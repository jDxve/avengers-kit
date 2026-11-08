# Transactions, isolation, and locks

Scope: how a NestJS service on Drizzle groups writes, passes the executor, picks an isolation level, takes a row lock, and checks a conditional update. The rules are owned by [`nestjs-standards` 05, 4.4](../../nestjs-standards/references/05-rules.md) (atomic writes share a transaction, the caller opens it and passes the executor, no transaction around the outside world) and [07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) (which mechanism protects which invariant, and the affected-row check). This file adds the Drizzle API and the PostgreSQL behavior behind those rules. The tests that prove a guard are in `testing-strategy` `04-nestjs-e2e-and-db.md`.

## Drizzle's transaction API

From the Drizzle transactions page:

- `db.transaction(async (tx) => { ... })` runs the callback in one transaction. A throw, or `tx.rollback()`, which throws, rolls it back.
- The callback's return value is the transaction's return value.
- `tx.transaction(...)` inside a transaction creates a savepoint (nested transaction).
- PostgreSQL options are passed as a second argument: `isolationLevel` (`'read uncommitted'`, `'read committed'`, `'repeatable read'`, `'serializable'`), `accessMode`, and `deferrable`.

## Passing the executor

4.4 shows the signature: `async create(data: CreateUser, tx: Executor = this.db)`. A service never opens its own transaction if another service can call it inside one. In practice:

```ts
// orders.service.ts
async cancel(ctx: TenantContext, orderId: string): Promise<Order> {
  return this.db.transaction(async (tx) => {
    const order = await this.markCancelled(ctx, orderId, tx);
    await this.stock.release(ctx, order.lines, tx); // StockService takes tx too
    await this.outbox.add({ type: 'order.cancelled', orderId }, tx); // dispatched after commit
    return order;
  });
}
```

- The outermost use case opens the transaction; everything below takes `tx`.
- The outbox row is written in the same transaction; a worker sends the email or calls the provider after commit (4.4, "A database transaction cannot roll back the outside world").
- No HTTP call, queue publish, or `await` on anything outside the database runs inside the callback. A row lock held across a network call is held for as long as the network takes (07 item 3).
- The `Executor` type is the project's own alias for "the database or a transaction". Define it once next to the Drizzle client in `src/database/`.

## Isolation levels in PostgreSQL

From the PostgreSQL "Transaction Isolation" section:

- **Read Committed** is the default. Each statement sees data committed before that statement began, so two statements in one transaction can see different data.
- **Repeatable Read** and **Serializable** can fail a transaction with a serialization failure, and applications using them must be prepared to retry the whole transaction from the beginning. Serialization failures always use SQLSTATE `40001`.
- **Serializable** behaves like Repeatable Read plus monitoring for anomalies. Data read in a Serializable transaction is not valid until that transaction commits, except in a deferrable read-only transaction.

07 opens with the consequence: at Read Committed, two requests can both pass the same check and both commit. Raising the isolation level is one fix; the 07 table lists the others, and they are usually cheaper.

If a project uses Repeatable Read or Serializable for a use case, the contract says so, the retry wraps the whole transaction with a ceiling ([`nestjs-standards` 10](../../nestjs-standards/references/10-production-readiness.md), "Retries have backoff and a ceiling"), and only `40001` is retried.

## Row locks

From the PostgreSQL "Explicit Locking" chapter:

- `SELECT ... FOR UPDATE` locks the returned rows until the transaction ends. Other transactions that try to update, delete, or lock those rows wait. A waiting `FOR UPDATE` then returns the updated row, or no row if it was deleted.
- In a Repeatable Read or Serializable transaction, `FOR UPDATE` raises an error if the row changed since the transaction started.
- `FOR NO KEY UPDATE`, `FOR SHARE`, and `FOR KEY SHARE` are weaker modes. Use the weakest one that protects the invariant.
- PostgreSQL detects deadlocks and aborts one of the transactions; which one is not predictable. The chapter's advice: acquire locks on multiple objects in a consistent order (for example by ascending id), take the most restrictive mode first, and otherwise retry transactions that abort on a deadlock.
- `lock_timeout` aborts a statement that waits longer than the given time for any lock, and it is off (zero) by default. Set it per transaction or session where a long wait is worse than a failure, not in `postgresql.conf`, which the docs advise against.

The Drizzle pages read in this session do not document a row-locking method on the select builder. Check the Drizzle version in the repo for one; otherwise run the locking read as SQL through the documented `tx.execute(sql\`SELECT ... FOR UPDATE\`)`, with values interpolated through the `sql` template so they stay parameters. Either way it runs inside `db.transaction`, because the lock ends with the transaction.

## Conditional updates and the affected-row count

07 makes the affected-row check non-negotiable: an update that matched zero rows and is treated as success is the bug. In Drizzle, use `.returning()` and check the result:

```ts
const [row] = await tx
  .update(orders)
  .set({ status: 'cancelled', updatedAt: new Date() })
  .where(and(inTenant(orders.tenantId, ctx.tenantId), eq(orders.id, orderId), eq(orders.status, 'pending')))
  .returning({ id: orders.id, status: orders.status });
if (!row) throw new OrderNotPendingError(orderId); // zero rows: gone, other tenant, or already moved
```

`inTenant` is the tenant helper from `07-tenant-scoping.md`. Zero rows can mean "not found", "another tenant's row", or "lost the race". The API answers the first two with the same 404 (`security-engineering` `SEC-API-01`). Telling the race apart needs a second read inside the same transaction, and the contract decides whether the caller learns the difference.

## Review questions

1. Which writes in this use case must succeed or fail together? Are they in one transaction, opened by the outermost caller?
2. Does anything inside the callback leave the database?
3. Which 07 mechanism protects each invariant, and where is its two-request test?
4. Is every conditional update's row count checked?
5. If the isolation level is raised, where is the bounded retry on `40001`?

## Sources

- Drizzle ORM documentation, "Transactions", Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/transactions
- PostgreSQL documentation, "13.2. Transaction Isolation", PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/transaction-iso.html
- PostgreSQL documentation, "13.3. Explicit Locking" (row-level lock modes, deadlocks), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/explicit-locking.html
- PostgreSQL documentation, "19.11. Client Connection Defaults" (`lock_timeout`), PostgreSQL 18 (current), read 2026-11-08. https://www.postgresql.org/docs/current/runtime-config-client.html
- Drizzle ORM documentation, "Select" and "Magic sql operator" (`db.execute(sql...)`), and the docs' full-text export searched for a row-locking method (none found), Drizzle v1.0 docs, read 2026-11-08. https://orm.drizzle.team/docs/select and https://orm.drizzle.team/docs/sql and https://orm.drizzle.team/llms-full.txt
- Drizzle ORM documentation, "Update" (`.returning()`), Drizzle v1.0 docs, read 2026-11-08 through the full-text export. https://orm.drizzle.team/docs/update
- Kit standards: `nestjs-standards` 05 (4.4), 07, 10; `testing-strategy` `04-nestjs-e2e-and-db.md`; `security-engineering` `20-api.md`.
