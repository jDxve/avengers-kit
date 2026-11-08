# Payments

Scope: taking money through a third-party payment provider, from the price shown in a Flutter or React client to the provider's webhook and the reconciliation that catches what the webhook missed. Provider-neutral on purpose: the provider is an Open decision in the project's contract, and its documentation is the source for every provider-specific detail (event names, signature scheme, idempotency support). The money, concurrency, and webhook rules live in `nestjs-standards` and are linked; this recipe puts them in order for one flow.

## When it is justified

The project's contract states that users pay in the product, and names the provider as an Open decision for Dave (AGENTS.md rule 6; kit rule). The recipe names no provider. Card data and the compliance scope that comes with it are decided at this point, not after the first build: PCI DSS applies to every entity that stores, processes, or transmits cardholder data, or that could affect the security of the cardholder data environment (PCI SSC, "PCI Data Security Standard"). Which self-assessment questionnaire applies is a question for the project's assessor and the provider's documentation; the kit read neither.

## Contract sections it fills

- Domain: an order or payment with an amount in minor units, a currency, a status machine (for example `pending`, `succeeded`, `failed`, `refunded`), the provider's reference, and the idempotency key.
- API: create payment (with `Idempotency-Key`), get status, the webhook endpoint, refund if in scope. Error codes the client branches on (`api-contract` `04-errors-and-versioning.md`).
- Authorization: who may pay for, view, and refund what; refunds are privileged.
- Security: the boundary rows below; card data is listed as never touching the project's servers, logs, or analytics.
- Invariants, Failure paths, Tests, Release (provider secrets by name, webhook signing secret), Open decisions (provider, currencies, refund policy).

## Invariants and enforcers

| Invariant | Enforced by |
| --- | --- |
| Amounts are integer minor units (or the database's exact decimal type) end to end, never binary floating point, and every amount travels with its currency | [`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.4 "Money"; `react-standards` [16](../../react-standards/references/16-decisions-this-document-deliberately-doe.md) example ("minor units as integers over the wire, formatted with Intl at the edge"); `database-drizzle` `01-schema-design.md` "Money" |
| The server computes the price from its own catalog. The client sends item ids and quantities; a price, discount, or total in the request is rejected | Strict request schema (`SEC-API-03`), quantity bounds in the schema; the price and quantity tampering checks in [black-widow's review](../../../agents/black-widow.md) |
| Creating a payment carries one `Idempotency-Key` per user intent, and a repeat returns the first result | [`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) item 4 (REQUIRED on payments); `api-contract` `05-idempotency-and-pagination.md`; [`react-standards` 05](../../react-standards/references/05-rules.md) 4.5 (send a key; one key per intent on web is a kit rule); `flutter-standards` [10](../../flutter-standards/references/10-feature-anatomy-worked-example-auth.md) "data/services". Where the provider accepts an idempotency key of its own, the server passes one derived from the same intent (kit rule; provider docs) |
| A webhook is verified against the raw body before parsing, replay-protected where the provider supports it, and handled idempotently | [`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) "External integrations"; `SEC-API-20`; a unique constraint on the provider's event id (kit rule) |
| Payment status comes from the provider (webhook or status lookup), never from the client's redirect or success screen | Kit rule; e2e test that a client "success" call cannot mark an order paid |
| A status moves once: two webhooks, or a webhook and the reconciliation job, cannot both apply the same transition | Conditional update checked by row count ([`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) item 2; `database-drizzle` `03-transactions.md`); two-request concurrency test |
| Card data stays with the provider's hosted fields or SDK. No card number reaches the project's servers, logs, crash reports, or analytics | Kit rule, to keep the project's own systems out of cardholder data handling (PCI SSC scope statement above); `SEC-LOG-01`, `SEC-MOB-18`, `SEC-WEB-18` |
| A timeout is not a failure: an irreversible call that timed out is looked up before any retry | [`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) "A timeout does not mean the operation did not happen"; `SEC-API-21` |
| A reconciliation job compares the project's records with the provider's on a schedule, flags every mismatch, and runs once across instances | Kit rule; [`nestjs-standards` 08](../../nestjs-standards/references/08-multi-instance-gotchas.md) (cron once); `background-jobs.md`; an alert on mismatches (`observability-and-debugging` `05-profiling.md` "Alerts") |
| Refunds and manual adjustments leave an audit trail the actor cannot edit | `SEC-LOG-10`; [`nestjs-standards` 10](../../nestjs-standards/references/10-production-readiness.md) |

## Flutter

Card entry uses the provider's SDK, chosen with the provider. A WebView checkout is added only when the contract states the need (`SEC-MOB-11`). The checkout screen is marked sensitive in the contract (`SEC-MOB-13`). The pay button is disabled while the request is in flight, and the idempotency key is created once per intent, not per attempt ([`flutter-standards` 10](../../flutter-standards/references/10-feature-anatomy-worked-example-auth.md)). After the provider step, the app shows "processing" and reads the status from the API.

## React or Next.js

Card entry uses the provider's hosted fields or hosted page. The provider's script is in the third-party inventory and the Content Security Policy (`SEC-WEB-19`, `SEC-WEB-04`). The form guards double submission and sends the idempotency key ([`react-standards` 05](../../react-standards/references/05-rules.md) 4.5). In Next.js, a server action or route handler that starts a payment validates with Zod and authorizes inside (`SEC-WEB-12`, `SEC-WEB-13`). The return page reads status from the API; it never decides the outcome.

## NestJS

Price computation, the payment row, and the outbox row for the provider call share one transaction; the provider call happens after commit ([`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.4). The webhook route reads the raw body, verifies, records the event id, and hands work to the outbox, so a slow handler does not make the provider redeliver (kit rule). Checkout is a sensitive business flow with a per-account limit (`SEC-API-12`). Business events (payment created, succeeded, refunded) are logged with the actor, the action, and the target id, never the payload (`SEC-LOG-09`).

## Security items

`SEC-API-01`, `SEC-API-03`, `SEC-API-12`, `SEC-API-20`, `SEC-API-21`, `SEC-LOG-01`, `SEC-LOG-09`, `SEC-LOG-10`, `SEC-WEB-04`, `SEC-WEB-12`, `SEC-WEB-13`, `SEC-WEB-18`, `SEC-WEB-19`, `SEC-MOB-11`, `SEC-MOB-13`, `SEC-MOB-18`.

## Failure paths and what the user sees

| Failure | What the user sees |
| --- | --- |
| Card declined | The provider's decline mapped to a project error code and its copy, with a way to try another method; never the provider's raw message (`api-contract` `04-errors-and-versioning.md`) |
| Timeout after submit | "Processing", not "failed"; the client polls the status endpoint. The server reconciles before any retry |
| Double tap, or retry after a dropped connection | One charge; the second request returns the first result |
| Webhook late or lost | "Processing" until the webhook or the reconciliation job settles it |
| Provider down | An error with retry, and no order marked paid |
| Reconciliation mismatch | Nothing to the user; an alert for the operator, and the order held in its last confirmed state |

## Tests

- e2e: a request with `price` or `total` returns 400; a negative or oversized quantity returns 400; the charged amount equals the catalog price times quantity.
- e2e concurrency: two creates with the same key produce one payment and one provider call (provider stub counts calls) (`testing-strategy` `04-nestjs-e2e-and-db.md`).
- e2e webhook: bad signature rejected; the same valid event twice applies once; a stale timestamp rejected where the provider signs one.
- Unit: a provider stub that times out after succeeding; the code looks the payment up instead of charging again (`SEC-API-21`).
- Concurrency: webhook and reconciliation applying the same transition; exactly one succeeds.
- Unit: money arithmetic in minor units, including rounding the contract specifies.
- Unit: reconciliation flags a payment the provider has and the project does not, and the reverse.

## Sources

- PCI Security Standards Council, "PCI Data Security Standard (PCI DSS)" overview page (intended audience and scope), read 2026-11-08. https://www.pcisecuritystandards.org/standards/pci-dss/
- PCI Security Standards Council, Document Library, which lists PCI DSS v4.0.1 as the current standard, read 2026-11-08. https://www.pcisecuritystandards.org/document_library/
- Kit standards: `nestjs-standards` 05 (4.4), 07, 08, 10, 12; `react-standards` 05 (4.5), 16; `flutter-standards` 10; `api-contract` `04-errors-and-versioning.md`, `05-idempotency-and-pagination.md`; `database-drizzle` `01-schema-design.md`, `03-transactions.md`; `security-engineering` `10-web.md`, `20-api.md`, `30-mobile.md`, `50-secrets-logs-errors.md`; black-widow's review step.
- Not read:
  - The PCI DSS v4.0.1 standard's own text (a licensed PDF) was not read, so no requirement number is cited.
  - The payment provider's documentation: named in the project's contract once Dave picks a provider; not read here.
