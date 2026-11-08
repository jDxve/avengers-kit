# Background jobs and queues

Scope: work a NestJS backend does outside the request that caused it (emails, exports, provider calls, scheduled tasks), with BullMQ when a queue is justified, and the app-side equivalent in Flutter. The rules live in [`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.9 "Async work" and 4.4 (outbox), and [08](../../nestjs-standards/references/08-multi-instance-gotchas.md) (scheduled jobs across instances). This recipe adds how BullMQ meets them and what the contract must say.

## When it is justified

`nestjs-standards` [03](../../nestjs-standards/references/03-stack.md) adds a queue (BullMQ) only when "You have work that is slow, retryable, or must survive a restart". BullMQ stores jobs in Redis (BullMQ "Job Ids": the id is used to construct the key that stores the job in Redis), so a queue also brings Redis. Both arrive only with that stated need in the project's contract (AGENTS.md rule 6). The transactional outbox in 4.4 is already required for work that crosses a system boundary; a project with low volume may dispatch its outbox with a worker reading the database and need no Redis at all. Which one is an Open decision for Dave (kit rule).

## Contract sections it fills

- Domain: each job type, the ids its payload carries, and the domain key that makes its effect happen once.
- State: the job's status as the user sees it, if the user waits on it (an export, an import).
- Invariants: the rows below, per job type.
- Failure paths: what the user sees when a job is pending, retrying, and dead-lettered.
- Release: Redis connection settings by secret name; whether workers run in the API process or their own.
- Open decisions: queue or database outbox worker; retry ceiling and backoff per job type; retention of failed jobs.

## Invariants and enforcers

| Invariant | Enforced by |
| --- | --- |
| Handlers are idempotent: a job may run more than once | `nestjs-standards` 4.9 ("They will be retried"). BullMQ: a stalled job is moved back to waiting and processed again by another worker, and failed jobs are retried when `attempts` is set. The effect is guarded by a unique constraint or a conditional update on the domain key ([`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) items 1, 2, 4) |
| Retries have a ceiling and backoff | `nestjs-standards` 4.9. BullMQ: retries need `attempts` above 1; without a backoff function a failed job is retried at once; built-in `exponential` backoff waits `2 ^ (attempts - 1) * delay`, with optional `jitter` |
| A job that exhausts its retries lands in a dead-letter path that someone sees | `nestjs-standards` 4.9. BullMQ moves it to the failed set; `removeOnFail: true` would delete it, so failed jobs are kept, bounded by count or age (kit rule). An alert fires on dead letters (`observability-and-debugging` `05-profiling.md` "Alerts"; `01-structured-logging.md` logs a dead-lettered job at `error`) |
| Payloads carry ids, not data. The handler reloads current state, and re-checks tenant scope, before acting | Kit rule, `docs/contracts/kit-skills.md` section 9; `database-drizzle` `07-tenant-scoping.md`; no secret or personal data stored in Redis (`SEC-LOG-01`, kit rule to apply it to payloads) |
| A job is enqueued only after the transaction that wants it commits | `nestjs-standards` 4.4 (outbox, then dispatch) |
| A custom `jobId` is a convenience, not the guarantee | BullMQ "Job Ids": a job added with an existing id is ignored, but once the earlier job has been removed the same id can be added again. The domain key in the database is the guarantee (kit rule) |
| Each payload carries the `requestId` of the request that created it, and every log line of the job carries it | `observability-and-debugging` `02-request-ids-and-tracing.md` |
| A scheduled job runs once across instances | [`nestjs-standards` 08](../../nestjs-standards/references/08-multi-instance-gotchas.md); [07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) item 5 for the distributed lock, which is not a substitute for idempotency |
| A failed notification never fails the parent request | `nestjs-standards` 4.9 |
| A handler returns control to the event loop often | BullMQ "Stalled Jobs": a busy CPU stops the worker renewing its lock, and the job is marked stalled. CPU-heavy work is split or moved out of the event loop (kit rule) |

## Flutter

Work that continues after the app exits uses the trigger and minimum rules in [`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.6 "Background work": behind a domain-level scheduler contract, tasks idempotent and resumable. Writes queued on the device are `offline-sync.md`, not this recipe.

## React or Next.js

The browser runs no background jobs here. A user waiting on a long job (an export) starts it with an idempotent request and then polls a status endpoint through the query layer ([`react-standards` 05](../../react-standards/references/05-rules.md) 4.4), or receives a hint as `realtime.md` describes (kit rule).

## NestJS

Queue and worker setup belong in their own module, with the queue name and job options in one place (kit rule). BullMQ requires processors to throw `Error` objects. Retry options are set per job type, or in the queue's `defaultJobOptions`. Outbound calls inside a job follow [`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md): timeouts, and no blind retry of an irreversible call that timed out (`SEC-API-21`). A user-triggered job that is expensive has a per-account limit (`SEC-API-12`).

## Security items

`SEC-API-12`, `SEC-API-21`, `SEC-LOG-01`, `SEC-LOG-09`, `SEC-LOG-11`.

## Failure paths and what the user sees

| Failure | What the user sees |
| --- | --- |
| Job waiting or running | A status ("preparing your export") the user can leave and come back to |
| Retrying after a transient failure | Nothing new; the status stays in progress |
| Dead-lettered | A failed status with the project's copy and a retry action, which starts a new job for the same domain key; the operator gets an alert |
| Redis unavailable at enqueue | The request still succeeds, because the intent is in the outbox; the dispatcher enqueues when Redis returns |
| Worker crashed mid-job | Nothing; the job stalls, is picked up again, and the idempotent handler does not repeat its effect |

## Tests

- Unit or e2e: run the same job twice; the effect happens once (`testing-strategy` `04-nestjs-e2e-and-db.md`, concurrency tests).
- Unit: each job type's options set `attempts` above 1 and a backoff; a test asserts them, so a refactor cannot drop them.
- Unit: a job that always throws ends in the failed set, and the alert hook is called.
- Unit: a payload schema accepts ids only; adding a data field fails the test.
- e2e: a transaction that rolls back leaves no job and no outbox row.
- e2e: the job's log lines carry the creating request's `requestId`.

## Sources

- BullMQ documentation, "Retrying failing jobs", "Job Ids", "Stalled Jobs", "Auto-removal of jobs", docs source on the GitHub master branch (latest npm release 6.7.2), read 2026-11-08. https://docs.bullmq.io/guide/retrying-failing-jobs and https://docs.bullmq.io/guide/jobs/job-ids and https://docs.bullmq.io/guide/workers/stalled-jobs and https://docs.bullmq.io/guide/queues/auto-removal-of-jobs
- Kit standards: `nestjs-standards` 03, 05 (4.4, 4.9), 07, 08, 12; `flutter-standards` 16 (11.6); `react-standards` 05 (4.4); `database-drizzle` `07-tenant-scoping.md`; `observability-and-debugging` `01-structured-logging.md`, `02-request-ids-and-tracing.md`, `05-profiling.md`; `testing-strategy` `04-nestjs-e2e-and-db.md`; `security-engineering` `20-api.md`, `50-secrets-logs-errors.md`.
