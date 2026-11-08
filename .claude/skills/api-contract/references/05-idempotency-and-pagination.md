# Idempotency keys and pagination

The server side of the `Idempotency-Key` header, and how list endpoints define and encode pagination. When a key is required is owned by [`nestjs-standards` section 6 (`07-concurrency-and-data-integrity.md`)](../../nestjs-standards/references/07-concurrency-and-data-integrity.md), item 4 (REQUIRED on payments and any irreversible operation). On the client, [`flutter-standards` section 5 (`10-feature-anatomy-worked-example-auth.md`)](../../flutter-standards/references/10-feature-anatomy-worked-example-auth.md) ("data/services (Retrofit)") owns one key per user intent, reused on retry, for Flutter. [`react-standards` 4.5](../../react-standards/references/05-rules.md) requires sending an idempotency key for anything irreversible or financial; that a web client also keeps one key per user intent and reuses it on retry is a kit rule. Pagination semantics are owned by [`nestjs-standards` section 11 (`12-api-behavior-and-external-dependencies.md`)](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) ("HTTP"). This file adds how the server stores and replays a key, and how a cursor is encoded.

## Why the header exists

RFC 9110 (9.2.2) defines a method as idempotent when repeating identical requests has the same intended effect as one, names PUT, DELETE, and the safe methods as idempotent, and says a client SHOULD NOT automatically retry a non-idempotent request unless it knows the semantics are idempotent. The IETF Idempotency-Key draft gives POST and PATCH a way to be retried safely: the client sends a key, and the resource recognizes a retry of the same request.

## What the draft specifies (revision 08)

| Topic | Draft-08 says | Section |
| --- | --- | --- |
| Syntax | An Item Structured Header Field whose value MUST be a String, so on the wire it is quoted: `Idempotency-Key: "8e03978e-40d5-43e8-bc93-6894a57f9324"` | 2.1, 6 |
| Uniqueness | The key MUST be unique and MUST NOT be reused with a different request payload. A UUID or similar random value is RECOMMENDED | 2.2 |
| Expiry | The resource MAY expire keys and SHOULD publish its expiry policy | 2.3 |
| Fingerprint | The resource MAY fingerprint the payload (for example a checksum of the whole body) to detect reuse | 2.4 |
| Publication | Resources MUST publish an idempotency specification, including expiry policy where it applies | 2.5.2 |
| First request | Process normally | 2.6 |
| Retry after completion | Respond consistently with the request having completed per the user's intent | 2.6 |
| Retry while the first is in flight | Resource conflict error, 409 | 2.6, 2.7 |
| Key missing on an operation that requires it | 400 | 2.7 |
| Key reused with a different payload | 422 | 2.7 |
| Security | Validate the key against a fixed published format; use a composite lookup key that combines the client's key with client-specific attributes known only to the resource, because low-entropy keys let attackers read other clients' cached entries | 5 |

The draft is an Internet-Draft, a work in progress that can change. The status codes above come from revision 08 and are cited from it, not from this kit. Its examples return problem details (RFC 9457); the kit returns these errors in its own shape with a stable `code` (`04-errors-and-versioning.md`). The rules in flutter section 5's backend list (scope, stored replay, 422 on a changed body, 409 or wait on a concurrent duplicate, rejection of a missing key) agree with the draft.

## Key format: one decision to record

Draft-08 makes the header a quoted Structured Field String. The `flutter-standards` section 5 example passes the bare `Uuid().v4()` value to `@Header`, which sends it unquoted. The kit does not settle this here. The project's idempotency specification (draft 2.5.2) states the accepted format, the server validates against exactly that format (draft 5), and both clients follow it. Record it in the contract's API section and in ADR-005 where `flutter-standards` section 5 keeps the backend agreement.

## Server storage

One row per key, scoped to the caller. Schema and migrations are owned by `database-drizzle` and its agent; this is what the row must hold, not a schema to paste.

| Column | Holds | Why |
| --- | --- | --- |
| caller id | The authenticated principal, from the session, never from the request | Key scope is per caller (draft 5; flutter section 5 item 1) |
| operation | The route and method, or an operationId | Scope per endpoint (flutter section 5 item 1) |
| key | The validated header value | Draft 2.1 |
| request hash | A hash of the parsed request body in a canonical form (sorted keys) | Detects reuse with a different payload (draft 2.2, 2.4) |
| state | `in_progress` or `completed` | Tells a concurrent duplicate from a retry (draft 2.6) |
| response status and body | What the first request returned | Replay returns it unchanged (flutter section 5 item 2) |
| created at, expires at | The expiry policy | Draft 2.3; flutter section 5 item 1: at least the longest client retry window |

A unique constraint on (caller id, operation, key) is what makes this hold under a race: two requests with the same key cannot both insert the row (nestjs section 6, item 1). A check-then-insert in application code is not a guarantee.

## Request flow

1. No key on an operation that requires one: 400 (draft 2.7; flutter section 5 item 5).
2. Key fails the published format: 400 (draft 5).
3. Insert the row as `in_progress`. The unique constraint decides who is first.
4. Insert succeeded: do the work, then store the response and mark the row `completed`.
5. Insert hit the constraint: read the row.
   - Different request hash: 422 (draft 2.7).
   - `in_progress`: 409 (draft 2.7), or wait for it to finish (flutter section 5 item 4). Never run the work in parallel.
   - `completed`: return the stored status and body without running the work again (draft 2.6; flutter section 5 item 2).

Two cases need a decision in the contract, because the draft does not settle them:

- **Work that calls an external provider.** No external call inside a transaction ([nestjs](../../nestjs-standards/SKILL.md) "Rules that never bend"), so the `in_progress` row is committed before the call, and a crash can leave it there. Before retrying, reconcile by the key or the provider's status lookup; a timeout does not mean the operation did not happen (nestjs section 11, "External integrations").
- **A first attempt that failed.** Whether a failed response is stored and replayed, or the row is released so a retry can run, is per operation. Write which one in the contract.

The stored body is a copy of a response, so it gets the same access rule as the resource it describes: the lookup is scoped to the caller, never to the key alone (draft 5). What else to check is in the `security-engineering` skill.

## Proving it

A concurrency guard with no test is a hope (nestjs section 6). The minimum e2e cases, against a real database (nestjs [4.11](../../nestjs-standards/references/05-rules.md)):

- The same request twice with one key, concurrently: exactly one execution, one record.
- The same request again after completion: the stored status and body, no second record.
- The same key with a different body: 422.
- The same key from a different caller: treated as a new key, never the first caller's stored response.
- No key: 400.

flutter section 5 describes the matching check against staging, run by a person. Where these tests live is in the `testing-strategy` skill.

## Pagination

nestjs section 11 requires a stable sort, a maximum page size, and cursor pagination where offset pagination gets expensive or shifts under inserts. The contract's API section records all three per list endpoint (output format in this skill's SKILL.md).

- **Stable sort.** The sort ends in a unique column, for example `createdAt desc, id desc`, so rows with equal sort values keep one order across pages.
- **Maximum page size.** The query schema enforces it, for example `limit: z.coerce.number().int().min(1).max(100).default(20)`, so a request over the maximum is a 400 like any other validation failure (nestjs 4.3). Check that the exported `openapi.json` shows the bound.
- **Cursor.** The response carries the cursor for the next page, or `null` on the last page. Document it in the response schema.

The cursor is opaque to clients (kit rule):

- The server encodes it, for example base64url of the last row's sort values and id. Clients pass it back exactly as received and never parse, build, or compare it (`02-web-clients.md`; on Flutter the notifier holds it as a string).
- The server decodes it as untrusted input. It is validated by a schema like any other query parameter (nestjs 4.3), and a malformed cursor is a 400.
- Opaque is not secret. Base64 is readable, so a cursor holds nothing the caller may not see. If a tampered cursor would matter, sign it.
- The decoded position is applied inside the same ownership scope as the first page. A cursor never widens what the caller can list.
- Changing the encoding invalidates cursors clients hold. Accept the old form during a deprecation window or answer with the error clients already handle for a bad cursor (`04-errors-and-versioning.md`).

Offset pagination (`page`, `pageSize`) is acceptable where nestjs section 11 allows it. The same stable sort and maximum apply, and the contract says which one the endpoint uses.

## Sources

- IETF draft "The Idempotency-Key HTTP Header Field", draft-ietf-httpapi-idempotency-key-header-08 (22 October 2026, expires 25 April 2027), sections 2.1 to 2.7, 5, 6: https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/08/
- RFC 9110, HTTP Semantics (STD 97, June 2022), section 9.2.2 (idempotent methods), 15.5.10 (409), 15.5.21 (422): https://www.rfc-editor.org/rfc/rfc9110
- RFC 9457, Problem Details for HTTP APIs (July 2023), named only because the draft's examples use it: https://www.rfc-editor.org/rfc/rfc9457
