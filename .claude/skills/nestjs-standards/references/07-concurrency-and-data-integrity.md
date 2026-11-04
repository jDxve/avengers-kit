## 6. Concurrency and data integrity

**This is the section most backends get wrong.** Transactions give you atomicity. They do
not, at the default isolation level, stop two simultaneous requests from both passing the
same validity check and both committing.

The failure shape is always the same: read, decide in application code, write. Between the
read and the write, someone else did the same thing.

**Pick the mechanism that matches the invariant, not the one that matches the table.** The
requirement is that every invariant touching money, inventory, balances, approvals, or a
status workflow is protected by *something* on this list. Which one depends on what must be
true:

| The invariant | The tool |
|---|---|
| This must not exist twice | Unique constraint (1) |
| Only one actor may move this record out of its current state | Optimistic locking (2) |
| Read, compute, then write, with no one else touching the row | Pessimistic locking (3) |
| This must not happen twice even if the request arrives twice | Idempotency key (4) |
| Exactly one process may do this across instances | Distributed lock (5) |

A status workflow usually wants 2, but not always. A single transition guarded by
`WHERE status = 'pending'` with the affected-row count checked gives the same guarantee
without a version column, and is the better choice when there is exactly one transition and
no other mutable fields. Reach for the version column when the record has several mutable
fields or several possible transitions.

**1. Unique constraints, at the database.**
The only guarantee that holds under every race. Application-level "check if exists first" is
not a guarantee. Enforce one active payroll run per period, one pending leave request per
employee per date range, one account per email, in the schema. Catch the violation and map
it to a clean domain error.

**2. Optimistic locking.**
For records several actors may edit concurrently. Add a `version` column, include it in the
`WHERE` of every update, and increment it. Zero rows affected means someone else got there
first, so reject with a conflict error.

```sql
UPDATE leave_requests
   SET status = 'approved', version = version + 1
 WHERE id = $1 AND version = $2 AND status = 'pending';
```

For a single guarded transition with nothing else mutable, the state predicate alone is
enough. **Either way, the non-negotiable part is checking the affected-row count.** An
update that reports zero rows and is treated as success is the bug this whole section is
about.

```sql
UPDATE leave_requests SET status = 'approved'
 WHERE id = $1 AND status = 'pending';   -- rowCount 0 means someone already approved it
```

**3. Pessimistic locking (`SELECT ... FOR UPDATE`).**
When you must read, compute, and write with no one else touching the row: balance
decrements, stock reservations, sequence allocation. Hold it for the shortest possible span,
always inside a transaction, and never across a network call.

**4. Idempotency keys.**
For anything a user can trigger twice: a double-clicked submit, a client retry, a webhook
redelivery. The caller sends a key, you store it with the result, and a repeat returns the
original result instead of doing the work again. REQUIRED on payments and on any
irreversible operation.

**5. Distributed locks (Redis).**
Only for cross-process coordination the database cannot express, such as ensuring a
scheduled job runs once across instances. Not a substitute for 1 through 4. Locks expire,
and a lock that expires mid-work is worse than no lock if the work is not idempotent.

**Test it.** A concurrency guard with no test is a hope. Fire two concurrent calls at the
same row and assert that exactly one succeeds.

---

