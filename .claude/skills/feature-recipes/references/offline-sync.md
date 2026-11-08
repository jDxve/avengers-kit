# Offline sync

Scope: a Flutter app that reads and writes without a network and syncs with a NestJS backend later, and the narrower case of a React client that retries writes. Offline writes in a browser are not covered: the web storage sources were not read, so a project that needs them adds a contract of its own. The write queue rules are thor's [Mutation queues](../../../agents/thor.md#mutation-queues), mirrored in the contract template's Mutation queue section; the device storage and outbox trigger is [`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.6 "Offline and sync"; the web side is [`react-standards` 07](../../react-standards/references/07-async-correctness.md). This recipe adds the conflict policy, the server side of a long-lived queue, and what the user sees.

## When it is justified

The trigger is that "users must read or write without a network" (`flutter-standards` 16 11.6), stated in the project's contract (AGENTS.md rule 6). Without it, the app shows the offline state with retry and queues nothing (`flutter-standards` 16 11.4, "Offline and poor network defined"). The local database (`drift` or `isar` in 16 11.6) is an Open decision for Dave.

## Contract sections it fills

- Mutation queue: all five rules, per queued operation (the section is mandatory once anything is queued).
- Domain: which records are kept on the device, and the version or timestamp each carries for conflicts.
- Invariants: the conflict policy per record type.
- API: the idempotency key retention, and the conflict code the server returns.
- UI contract and Failure paths: the queued, sending, failed, dead-lettered, and synced states.
- Release: the local schema version and its migration.

## Invariants and enforcers

| Invariant | Enforced by |
| --- | --- |
| Each of thor's five rules is filled in the contract: idempotency key per user intent, ordering group, retry ceiling with backoff, visible dead-letter path, sign-out rule | thor [Mutation queues](../../../agents/thor.md#mutation-queues) (stop and report if any is missing); contract template "Mutation queue" |
| The idempotency key is created with the intent and stored with the queued write, so every retry sends the same key | [`flutter-standards` 10](../../flutter-standards/references/10-feature-anatomy-worked-example-auth.md) "data/services"; `api-contract` `05-idempotency-and-pagination.md` |
| The server keeps idempotency keys at least as long as the oldest write the client may still send | Kit rule: the contract states the client's maximum queue age and the server's key expiry, and the second is longer |
| Writes in one ordering group are sent one at a time, in order; groups do not block each other | Kit rule; the group is named per operation in the contract |
| Only transient failures are retried. A validation error, forbidden, or conflict goes straight to the dead-letter path | Kit rule; the failure classes in [`react-standards` 05](../../react-standards/references/05-rules.md) 4.6 |
| A conflict policy is written per record type: the server rejects a stale version with a conflict code, and the contract says what the client does with it | [`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) item 2 (version column, zero rows means conflict); kit rule that silent last-write-wins is allowed only when the contract says so |
| Sign-out never lets one user's queued writes send as another user, and clears the local database | thor's sign-out rule; `SEC-MOB-06`; [`flutter-standards` 08](../../flutter-standards/references/08-core-layer.md) "Threat model and limits" (session epoch) |
| The repository is the single source of truth and returns local data first | `flutter-standards` 16 11.6 |
| Every local schema version has a migration test | `flutter-standards` 16 11.6 |
| The server keeps accepting the request fields old installed apps still send | `api-contract` "Rules that never bend" (installed mobile clients) |

## Flutter

The queue and the local database sit behind the repository; notifiers see records with a sync status, never the queue (`flutter-standards` 16 11.6). The sender runs when the network returns and on app start, applies backoff with jitter, and stops at the ceiling. Queued rows are tagged with the user they belong to, and sending checks the current session against the tag (kit rule, alongside the epoch in `flutter-standards` 08). `ui/` widgets get each item's status as a value and retry or discard as callbacks (`ui-isolation`).

## React or Next.js

No offline queue by default. A write that fails because the network dropped keeps the form's values and offers retry with the same idempotency key (kit rule; `api-contract` `05-idempotency-and-pagination.md`). Optimistic updates need a rollback ([`react-standards` 07](../../react-standards/references/07-async-correctness.md) item 5), and double submission is guarded (item 4). Retry state stays in memory. A project that persists writes in the browser stops and writes its own contract covering storage eviction, one sender across tabs, and sign-out across tabs (`SEC-WEB-18`).

## NestJS

Each queued operation is an endpoint that requires `Idempotency-Key` and replays the stored result for a repeat (`api-contract` `05-idempotency-and-pagination.md`). Updates carry a version and return a stable conflict code when it is stale ([`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md); `api-contract` `04-errors-and-versioning.md`). A write that arrives days later is authorized against the current state, not the state when it was queued (kit rule; `SEC-API-01`). Sync lists use cursor pagination with a stable sort (`api-contract` `05-idempotency-and-pagination.md`).

## Security items

`SEC-API-01`, `SEC-API-03`, `SEC-API-12`, `SEC-MOB-01`, `SEC-MOB-06`.

## Failure paths and what the user sees

| State | What the user sees |
| --- | --- |
| Offline | An offline banner; local data stays readable and editable; nothing signs the user out (`flutter-standards` 16 11.4) |
| Queued | The item marked "waiting to sync" |
| Sending, or retrying after a transient failure | The same mark; no repeated toasts |
| Dead-lettered (rejected, forbidden, conflict, or past the retry ceiling) | The item marked "not saved" with the reason in project copy, and actions to retry, edit, or discard |
| Conflict with a resolution the contract allows | The choice the contract names (keep mine, keep theirs, or merge), never a silent overwrite unless the contract chose it |
| Signed out with writes queued | A warning before sign-out that unsynced changes will be lost (kit rule) |

## Tests

- Repository tests offline and online, and a migration test per local schema version (`flutter-standards` 16 11.6).
- Unit: a queued write retried three times sends the same idempotency key each time.
- Unit: writes in one group send in order; a stuck group does not block another.
- Unit: a 400, 403, or 409 moves the item to dead letter at once; a timeout is retried up to the ceiling.
- The `SEC-MOB-06` test: user A signs out with a write queued, user B signs in, and A's write never sends with B's token.
- e2e: the same key sent twice, the second time after a long delay within the key's retention, produces one effect.
- e2e: an update with a stale version returns the conflict code.
- Device script step 4 extended to writes (`flutter-standards` 16 11.6).

## Sources

- No public source beyond the kit. The local database's own documentation (`drift`, `isar`, or the project's choice) is named in the project's contract once Dave picks one; none was read here.
- Kit standards: thor "Mutation queues"; contract template "Mutation queue"; `flutter-standards` 08, 10, 16 (11.4, 11.6); `react-standards` 05 (4.5, 4.6), 07; `nestjs-standards` 07; `api-contract` `04-errors-and-versioning.md`, `05-idempotency-and-pagination.md`; `ui-isolation`; `security-engineering` `20-api.md`, `30-mobile.md`.
