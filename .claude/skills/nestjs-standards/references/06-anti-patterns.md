## 5. Anti-patterns

| Anti-pattern | Why it hurts | Instead |
|---|---|---|
| Business logic in controllers | Untestable, duplicated across routes | Move to a service |
| Pass-through facade | Three files per endpoint, no benefit | Inject the real services |
| God service doing auth, export, and billing | Unreadable, merge conflicts, untestable | Split by responsibility |
| `forwardRef` | Papers over a cycle | Fix the boundary, or invert with an event |
| Domain logic in `common/` | Becomes a dumping ground | It belongs to a domain module |
| Reaching into another module's internals | Breaks encapsulation silently | Go through its exports |
| Infrastructure inside a version folder | `v2` imports from `v1` | `common/` sits outside versioning |
| `if (user.role === 'admin')` in a controller | Bypasses the guard system | `RolesGuard` + `@Roles()` |
| Returning raw Drizzle rows | Leaks columns, breaks the contract | Map to a response DTO |
| Unbounded list endpoints | Dies at scale | Mandatory pagination |
| Read, check in JS, then write | Lost update under concurrency | See section 6 |
| Ignoring the affected-row count on a guarded update | Silent no-op reported as success | Check `rowCount`, throw on 0 |
| Two live successors in one refresh-token family | Reuse detection can no longer tell a retry from a theft | One live token per family, enforced by a partial unique index (4.8) |
| Time window instead of state to classify token reuse | A guess lets both the retry and the attacker through | Branch on whether the successor was consumed (4.8) |
| Wrapping an unexpected error in a domain error | Tells the client to retry a bug, and hides it from triage | Let it reach the filter as a 500 (4.6) |
| Domain-specific errors in `common/errors/` | Shared folder accumulates domain knowledge | Keep them in the owning module |
| External call inside a transaction | The rollback is a lie | Outbox, then dispatch |
| Retrying an irreversible call after a timeout | The first one may have succeeded | Reconcile by idempotency key first |
| Verifying a webhook signature against the parsed body | Re-serialization breaks the hash | Verify against the raw body |
| Trusting a file's extension or client MIME type | Both are attacker-controlled | Validate the content |
| Floats for money | Rounding drift nobody can trace | Integer minor units or exact decimal |
| Global guard depending on another guard's output | Global guards run first, context is empty | Decode what you need, or move to controller level |
| Cron in every cluster instance | Duplicate work and records | Distributed lock, or pin to one instance |
| `any` | Erases the point of TypeScript | `unknown` plus narrowing |
| `console.log` | Unstructured, invisible in production | The logger |
| Silent `catch {}` | Hides failures | Log and rethrow |
| Secrets in the repo | Unrecoverable once pushed | Env vars, validated at boot |

---

