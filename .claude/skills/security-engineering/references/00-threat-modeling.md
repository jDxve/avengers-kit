# Threat modeling

Scope: how to model the threats to one feature and write them into the contract's Security section, so every threat has a control and every control has a test. This file holds the method, a STRIDE table per trust boundary, the abuse-case template, how a row becomes a test, and the Security section filled for the orders example in `contract-first/assets/contract-template.md`. Stack rules are not restated here; each control names the checklist id that holds it.

## The four questions

The OWASP Threat Modeling Cheat Sheet, citing the Threat Modeling Manifesto, frames the work as four questions. The six steps below answer them in the order a contract needs.

| Question | Steps |
| --- | --- |
| What are we working on? | 1 assets, 2 actors, 3 trust boundaries, 4 entry points |
| What can go wrong? | 5 STRIDE per boundary, 6 abuse cases |
| What are we going to do about it? | A response per threat, and a control with a checklist id |
| Did we do a good enough job? | Each control has a test, and the review checks the table against the code |

## The six steps

1. **Assets.** Data and capabilities worth stealing, changing, or stopping: personal data, tokens, money movement, an admin action, availability of a flow users depend on.
2. **Actors.** Every role that uses the feature, plus the ones that must not succeed: another signed-in user, a signed-out caller, a user with a lower role, an automated script, a compromised third-party provider.
3. **Trust boundaries.** Where data crosses from one trust level to another. In this kit's stacks the usual ones are: browser or app to API; Next.js server to NestJS; API to database; API to a third-party provider; provider to API (webhooks); device storage; CI to the artifact registry.
4. **Entry points.** Each endpoint, server action, route handler, deep link, webhook, upload, queue consumer, and scheduled job that crosses a boundary from step 3.
5. **STRIDE per boundary.** Walk the six categories at each boundary (table below). Record a threat only when it is plausible for this feature; an empty cell is fine.
6. **Abuse cases.** One per actor from step 2 who should not succeed. Each becomes a row with a control and a test.

The cheat sheet adds that a threat model is maintained with the system, not written once. Kit rule: a contract change that adds an entry point or a boundary updates its Security section in the same edit.

## STRIDE at a boundary

The category and the property it violates are from the OWASP Threat Modeling Cheat Sheet. The prompts and controls are kit rules pointing at checklist ids.

| Category | Violates | Prompt at a boundary | Typical control |
| --- | --- | --- | --- |
| Spoofing | Authentication | Can a caller act as someone else: a forged or replayed token, an unverified webhook, a spoofed correlation id? | Verified tokens (`SEC-API-04`), webhook signatures (`SEC-API-20`), session storage (`SEC-WEB-07`, `SEC-MOB-01`) |
| Tampering | Integrity | Can a caller change a field, a price, a status, or an id they do not own? | Strict schemas (`SEC-API-03`), owner scoping (`SEC-API-01`), server-computed totals |
| Repudiation | Accounting | Could a user deny an action, and could we show they did it? | Business event logs with actor and `requestId` (`SEC-LOG-09`, `SEC-LOG-10`) |
| Information disclosure | Confidentiality | Can data leak through a response, a log, a URL, a cache, a backup, or an error? | Response shapes (`SEC-API-07`), cache policy (`SEC-API-17`), logs (`SEC-LOG-01`), errors (`SEC-LOG-07`) |
| Denial of service | Availability | Can one caller exhaust a resource, or lock another user out? | Limits (`SEC-API-08`), rate limits (`SEC-API-05`), business-flow limits (`SEC-API-12`) |
| Elevation of privilege | Authorization | Can a caller reach a function or a record above their role? | Function-level authorization (`SEC-API-10`), owner scoping (`SEC-API-01`) |

When the feature is a business flow that can be abused while working as designed (bulk buying, invite spam, coupon reuse), the cheat sheet points to misuse and abuse cases as the better technique than STRIDE. Use step 6 for those, and see `SEC-API-12`.

## Responding to a threat

Each threat gets one of the responses the cheat sheet lists from Shostack: mitigate, eliminate (remove the feature or component), transfer (to another party, with the remaining controls and owner written down), or accept. Kit rule: only Dave accepts a risk, and an accepted row says so with his reason in the contract's Open decisions until he answers.

## Abuse-case template

```markdown
- Actor: <who should not succeed>
- Goal: <what they want>
- Path: <entry point and the steps they take>
- Precondition: <what they already have: an account, a leaked id, a stolen device>
- Control: <the mechanism, with the SEC-* id>
- Test: <the test name or the assertion, and its level>
```

Write the path as concrete requests, not intentions. "B sends `POST /orders/<A's id>/cancel` with B's token" is testable; "B tries to cancel someone else's order" is not.

## From row to test

Kit rule: the test sits at the lowest level that exercises the real control. A control that only exists in a guard, a database constraint, or a header is tested through the layer that holds it.

| Control lives in | Test level | Example assertion |
| --- | --- | --- |
| A NestJS guard, policy, or scoped query | e2e against a real database, per `nestjs-standards` 05 4.11 | B gets 404 for A's id |
| A Zod schema | e2e, plus a unit test of the schema | Unknown nested key returns 400 |
| A database constraint or conditional update | Concurrency test with two operations | Exactly one of two cancels succeeds |
| An HTTP header or cookie attribute | e2e reading the response headers | `Set-Cookie` has `HttpOnly`, `Secure`, `SameSite` |
| A client-side redaction or storage rule | Unit or widget test | Logger output contains no bearer token |
| A CI gate | The workflow step, run on a pull request | Audit step fails on a seeded finding |
| A platform setting only a device shows | Release checklist on a real device | Recorded in the release ticket |

A row whose test column would read "by inspection" is a row nobody checks twice, as `react-standards` [10-security.md](../../react-standards/references/10-security.md) puts it. Write the test, or mark the control unverified in the contract.

## Worked example: the orders contract

The template's orders feature lists orders (`list(page)`) and cancels one with an idempotency key (`cancel(id, idempotencyKey)`). The Security section, filled:

```markdown
## Security

| Boundary | Threat (STRIDE) | Abuse case | Control | Test |
| --- | --- | --- | --- | --- |
| client to `POST /orders/:id/cancel` | Elevation of privilege | User B cancels user A's order | Lookup scoped to owner (SEC-API-01) | B gets 404 for A's order id |
| client to `POST /orders/:id/cancel` | Tampering | Client sends `{ "status": "refunded" }` or a nested unknown key | Strict schema on every object (SEC-API-03) | Unknown key at any depth returns 400 |
| client to `POST /orders/:id/cancel` | Denial of service | Double tap or a retried request cancels twice or races a refund | Idempotency key and conditional update (`nestjs-standards` 07) | Two concurrent cancels: one succeeds, one gets the stored result |
| client to `POST /orders/:id/cancel` | Spoofing | Request with an expired, unsigned, or wrong-audience token | Verified tokens (SEC-API-04) | `alg: none`, expired, and wrong-audience tokens get 401 |
| client to `GET /orders?page=` | Information disclosure | B lists A's orders | List query scoped to owner (SEC-API-02) | B's list never contains A's ids |
| client to `GET /orders?page=` | Denial of service | `pageSize=100000` | Maximum page size (SEC-API-08) | Page size over the maximum returns 400 |
| API to logs and crash reports | Information disclosure | Bearer token or full body logged on a 500 | Redaction (SEC-LOG-01, SEC-MOB-03) | Logger and reporter tests assert no token |
| API to client on error | Information disclosure | Driver error text shown to the user | Generic error with `requestId` (SEC-LOG-07) | Forced database error returns only `code`, `message`, `requestId` |
| device storage | Information disclosure | Tokens restored from a backup onto another device | `SessionStore` and backup exclusion (SEC-MOB-01, SEC-MOB-02) | `check_release_config.dart`, `secure_storage_test.dart` |

- Sensitive data, and where it must never appear (logs, URLs, analytics, crash reports, push payloads): order totals and delivery address stay out of URLs, analytics, and push payloads; tokens appear nowhere.
- Rate limits: cancel is limited per account (SEC-API-12); sign-in limits are the auth module's (SEC-API-05).
- Checklist items that apply (`SEC-*` ids): SEC-API-01, 02, 03, 04, 08, 12; SEC-LOG-01, 07; SEC-MOB-01, 02, 03.
```

Abuse cases, one per actor who should not succeed:

- Another signed-in user (B) cancels or reads A's order: the first and fifth rows.
- A signed-out caller cancels any order: the global guard (`SEC-API-10`), tested by a cancel with no token returning 401.
- The owner cancels an order the business rule forbids (already shipped): a domain error with a stable code, tested by a cancel on a shipped order returning that code.
- A script cancels and re-orders in a loop to hold stock: `SEC-API-12`.

## Checklist

- [ ] SEC-TM-01 Every entry point the feature adds or changes appears as a boundary row in the contract's Security section. Verify: list the feature's controllers, route handlers, server actions, deep links, and webhooks with `grep -rnE "@(Get|Post|Put|Patch|Delete)\(|'use server'|export async function (GET|POST|PUT|PATCH|DELETE)" <feature paths>` and match each to a row.
- [ ] SEC-TM-02 Every actor who should not succeed has an abuse case with a control and a test. Verify: read the Actors list against the abuse cases; each case names a test that exists in the tree.
- [ ] SEC-TM-03 Every control names a `SEC-*` id or a standard section, and every id cited exists in this skill. Verify: `grep -oE 'SEC-[A-Z]+-[0-9]+' docs/contracts/<feature>.md | sort -u` and confirm each with `grep -rn "<id>" .claude/skills/security-engineering`.
- [ ] SEC-TM-04 Every test named in the Security table exists and fails when its control is removed. Verify: find the test by name; comment out the control locally and run that one test to see it fail, then restore.
- [ ] SEC-TM-05 No row is accepted without Dave's written reason. Verify: each row with response "accept" has a matching entry in the contract's Open decisions or a reason in Dave's words.

## Sources

- OWASP Threat Modeling Cheat Sheet, living document without a version number, read 2026-11-04, https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html
- Adam Shostack, *Threat Modeling: Designing for Security*, first edition (2014, per the author's book page, which also announces a second edition for February 2027); book text not read, so every STRIDE claim above is taken from the OWASP cheat sheet, which cites it. https://shostack.org/books/threat-modeling-book
- Kit standards: `react-standards` [10-security.md](../../react-standards/references/10-security.md), `nestjs-standards` [05-rules.md](../../nestjs-standards/references/05-rules.md) 4.11, [07-concurrency-and-data-integrity.md](../../nestjs-standards/references/07-concurrency-and-data-integrity.md).
