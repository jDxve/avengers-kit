# Errors and versioning

How error codes are listed, documented, and turned into client copy, what counts as a breaking change, and how a deprecation window is written into a contract. The error shape `{ code, message, requestId }` and the backward-compatibility rule are owned by [`nestjs-standards` 4.3](../../nestjs-standards/references/05-rules.md); where codes live and how the filter maps errors is owned by 4.6 in the same file. This file adds the cross-stack view: what the contract records and what each client does with it.

## Error codes: a closed list per module

- A module's codes are the errors in `modules/<domain>/<domain>.errors.ts`, prefixed by domain so they are unique across the API (nestjs 4.6). That file is the closed list: a code that is not there does not exist.
- A code exists only for a condition the client can act on. Unexpected failures stay a generic 500 with only the request id, never a new code (nestjs 4.6).
- The contract's API section lists, per operation, the codes a client branches on (see the output format in this skill's SKILL.md). The codes are the promise; `message` text is free to change (nestjs 4.3).
- Validation failures from nestjs-zod are mapped by the filter to one stable code (`01-nestjs-publishing.md`).

## HTTP status codes

The status is the class of failure, and `code` is the specific one. Status meanings come from RFC 9110:

| Status | RFC 9110 | Kit use |
| --- | --- | --- |
| 400 Bad Request | 15.5.1: the server will not process the request because of a perceived client error | Schema validation failed, including an unknown key under `.strict()` (nestjs 4.3) |
| 401 Unauthorized | 15.5.2 | No valid session. Auth lifecycle in nestjs [4.8](../../nestjs-standards/references/05-rules.md) |
| 403 Forbidden | 15.5.4 | Signed in, not allowed (`ForbiddenError`, nestjs 4.6) |
| 404 Not Found | 15.5.5 | `NotFoundError`, including a resource owned by someone else (the ownership rule is in the `security-engineering` skill) |
| 409 Conflict | 15.5.10: conflict with the current state of the target resource; the user might resolve it and resubmit | `ConflictError`: a guarded state transition lost, or a duplicate ([nestjs section 6 (`07-concurrency-and-data-integrity.md`)](../../nestjs-standards/references/07-concurrency-and-data-integrity.md)) |
| 422 Unprocessable Content | 15.5.21: content is well formed but its instructions cannot be processed | An idempotency key reused with a different body (`05-idempotency-and-pagination.md`) |
| 500 Internal Server Error | 15.6.1 | Unexpected failure, generic body with `requestId` only (nestjs 4.6) |

The Flutter mapper in [`flutter-standards` section 3 (`08-core-layer.md`)](../../flutter-standards/references/08-core-layer.md) ("Dio error mapper") classifies 400, 409, and 422 as `rejected`, 403 as `forbidden`, 429 as `retryable`, and 5xx as `server`, so a status change on an existing code is a change in what a Flutter user is told. Treat it as changing the error (breaking, below).

## From a code to client copy

| Stack | Where the copy lives | Unknown code |
| --- | --- | --- |
| React and Next.js | The app's own message table keyed by `code`; the error UI shows the `requestId` ([react 4.4, 4.6](../../react-standards/references/05-rules.md)) | Generic copy for the failure class plus the `requestId`. Never the raw `message` of an exception (react 4.6) |
| Flutter | `errorToMessage` switches on `ErrorType` (flutter section 3, "AppException"). Per-code copy needs a `code` on `AppException`, which flutter section 3 does not have yet (see `03-flutter-clients.md`) | The `ErrorType` copy, with the sanitized server `message` only for `rejected` (flutter section 3) |

A client that meets a code it does not know falls back to its generic copy for the status. That is why adding a code to an operation is a contract change: until the clients map it, users see the generic text.

## RFC 9457, not adopted

RFC 9457 (Problem Details for HTTP APIs, which obsoletes RFC 7807) defines a JSON error object with `type`, `status`, `title`, `detail`, and `instance`, served as `application/problem+json`, and lets problem types add extension members that clients must ignore if they do not recognize them. The kit does not use it: the shape is fixed by nestjs 4.3 as `{ code, message, requestId }`, and every client in the kit standards reads that shape. The IETF Idempotency-Key draft shows its error examples as problem details; the kit returns those errors in its own shape (`05-idempotency-and-pagination.md`). Adopting RFC 9457 would be a change to nestjs 4.3 and to every client mapper, which Dave decides.

## What counts as breaking

From nestjs 4.3: within a version, adding optional fields is safe; removing a field, renaming one, tightening validation, or changing an error code is breaking.

| Change | Breaking? | Why |
| --- | --- | --- |
| Add an optional response field | No | Additive (nestjs 4.3). The Flutter decode test passes (`03-flutter-clients.md`) |
| Add an optional request field | No | Old clients do not send it |
| Remove or rename a response field | Yes | nestjs 4.3. Web: compile error after regenerating; Flutter: decode test fails |
| Remove or rename a request field | Yes | Old clients still send it, and `.strict()` returns 400 for the unknown key. Installed mobile clients keep sending it until the minimum supported version stops (nestjs 4.3) |
| Add a required request field, or tighten a limit, format, or enum | Yes | Tightening validation (nestjs 4.3) |
| Change, remove, or repurpose an error code | Yes | nestjs 4.3 |
| Change the status code returned with an existing error code | Yes | Clients map status to a failure class (flutter section 3) |
| Rename a reusable schema `id` | Not on the wire; yes for the generated web types | `01-nestjs-publishing.md`, "Reusable schemas and names" |

The review of the `openapi.json` diff applies this table. The staleness check only proves the file is current (`01-nestjs-publishing.md`).

## Deprecation window in a contract

A breaking change ships either as a new version or behind a deprecation window. The window is written in the contract that makes the change:

```markdown
### Deprecations

| Item | Replaced by | Deprecated in | Removed no earlier than | Minimum app version that no longer uses it | `deprecated: true` in OpenAPI |
| --- | --- | --- | --- | --- | --- |
| `GET /orders` field `total` | `totalMinor` | v1, 2026-11-10 | 2027-02-10 | 4.2.0 | yes |
```

- "Removed no earlier than" is a date, and the item is removed only when that date has passed and the minimum supported app version no longer sends or reads it (nestjs 4.3 on installed mobile clients).
- OpenAPI 3.0.4 has a `deprecated` boolean on the Operation, Parameter, Header, and Schema Objects, each meaning the item SHOULD be transitioned out of usage. Confirm the exported `openapi.json` diff shows it on the deprecated item. openapi-typescript reads it: its `--exclude-deprecated` flag drops deprecated fields from the types, which a project may use only after the window closes.
- During the window the server accepts both the old and the new field, and the old one stays in the contract tests until removal.

## Versioning mechanism

Whether the version is a URI prefix (`/v2/orders`) or a header is a per-project decision recorded in an ADR, not set by this skill. Whichever it is, the contract's API section names the version, and a new version gets its own entries in `openapi.json`.

## Sources

- RFC 9110, HTTP Semantics (STD 97, June 2022), sections 15.5.1, 15.5.2, 15.5.4, 15.5.5, 15.5.10, 15.5.21, 15.6.1: https://www.rfc-editor.org/rfc/rfc9110
- RFC 9457, Problem Details for HTTP APIs (July 2023, obsoletes RFC 7807), sections 3 and 3.2: https://www.rfc-editor.org/rfc/rfc9457
- OpenAPI Specification 3.0.4, `deprecated` fields of the Operation, Parameter, Header, and Schema Objects: https://spec.openapis.org/oas/v3.0.4.html
- IETF draft "The Idempotency-Key HTTP Header Field", draft-ietf-httpapi-idempotency-key-header-08 (22 October 2026), section 2.7, for its use of problem details: https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/08/
- openapi-typescript documentation, 7.x, CLI page (`--exclude-deprecated`): https://openapi-ts.dev/cli
