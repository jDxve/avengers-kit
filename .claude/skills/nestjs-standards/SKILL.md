---
name: nestjs-standards
description: Dave's NestJS backend standard. Use when writing, reviewing, or planning NestJS code, including modules, controllers, services, DTOs, migrations, auth, concurrency, queues, and webhooks.
paths:
  - "src/modules/**"
  - "**/*.module.ts"
  - "**/*.controller.ts"
  - "**/*.service.ts"
---

# NestJS standards

The repo's established convention beats this standard. When they differ, follow the repo and say so. Except the fixed stack choices (Drizzle and Zod), which repo convention never overrides; a repo that differs is flagged for migration. Rules marked REQUIRED are firm. DEFAULT rules can be departed from with a stated reason.

## Rules that never bend

- Controllers route, guard, and bind. Business logic lives in services. Never return a raw database row.
- Auth is deny-by-default. Every non-public route declares authorization, and every lookup is scoped to ownership.
- The module graph is acyclic, and `forwardRef` between domains is forbidden.
- Every invariant on money, inventory, balances, approvals, or status has a concurrency mechanism, and its test runs two operations against one row. Check the affected-row count.
- Money is never binary floating point. Time is stored as an unambiguous instant.
- No external call inside a transaction. Use an outbox, then dispatch.
- Errors follow one contract with stable codes. Unexpected failures stay a generic 500, never relabelled as a domain error.
- Add no Redis, queue, CQRS, or service extraction without a stated requirement.

## Read only what the task needs

| Task | Read in `references/` |
| --- | --- |
| New feature | `13-adding-a-feature.md` |
| Where a file goes | `04-structure.md` |
| Controllers, services, DTOs, database, boundaries, errors, logging, tests | `05-rules.md` |
| Refresh tokens, sessions, revocation | `05-rules.md`, section 4.8 |
| Races and integrity | `07-concurrency-and-data-integrity.md` |
| Security checklist | `09-security-baseline.md` |
| Webhooks, outbound calls, uploads | `12-api-behavior-and-external-dependencies.md` |
| Release readiness | `10-production-readiness.md`, `08-multi-instance-gotchas.md` |
| Review an existing backend | `14-reviewing-an-existing-backend.md`, `06-anti-patterns.md` |
| CI and automated checks | `11-enforcing-this-automatically.md` |
| Per-project decisions | `16-decisions-this-document-deliberately-doe.md` |

The OpenAPI output is the source of truth for client contracts. A change to it needs a contract update.
