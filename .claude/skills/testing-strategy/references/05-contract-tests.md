# Contract tests

Scope: the three tests that keep the NestJS API, the web client, and the Flutter client agreeing on the wire format. How the contract is published and consumed (Zod schemas, the generated `openapi.json`, `openapi-typescript`, `retrofit` DTOs) belongs to the `api-contract` skill. This file covers what each test checks, where it runs, and how to see it fail.

The kit's chain is provider-published: the server's schemas generate the OpenAPI document, and each client checks itself against the committed document. Fowler's article also describes consumer-driven contract tests, where each consumer publishes its expectations and the provider runs them. The kit does not use that model by default; a project that needs it records the choice in its contract.

## The three checks

| Check | Fails when | Runs | Rule it enforces |
| --- | --- | --- | --- |
| OpenAPI staleness | The spec generated from the current DTOs differs from the committed `openapi.json` | NestJS CI, `npm run openapi:check` ([`nestjs-standards` 11, CI gate](../../nestjs-standards/references/11-enforcing-this-automatically.md)) | OpenAPI generated from the DTOs and exported in CI ([05, 4.3](../../nestjs-standards/references/05-rules.md)) |
| Web types staleness | Types generated from the pinned schema differ from the committed `types.gen.ts` | React CI, `npm run api:check` ([`react-standards` 12, 11.6 and 11.9](../../react-standards/references/12-enforcing-this-automatically.md)) | Wire types are generated, never hand-written (react SKILL.md) |
| Flutter DTO decode | A DTO's `fromJson` throws or loses a field on an example payload from `openapi.json` | Flutter `flutter test`, every PR | Hand-written DTOs checked against the spec (`flutter-standards` 04 keeps `retrofit` with no other codegen) |

## OpenAPI staleness

- The committed `openapi.json` is the reviewed contract. A DTO change that does not regenerate it fails CI, so an API change cannot land without a diff a reviewer reads.
- The check regenerates into a temporary file and compares; it never overwrites the committed file in CI. The script shape in react 11.6 is the model.
- See it fail: add an optional field to a response schema, do not regenerate, run the check.

## Web types staleness

- Already specified in full in react 11.6, including the reason the schema source is a committed file or a pinned versioned URL and never a live dev server. Link it; do not copy the script into a project's docs.
- See it fail: change the committed `openapi.json` without regenerating `types.gen.ts`, run the check.

## Flutter DTO decode test

The test, its fixture path, and where the examples live in the spec are owned by `api-contract` [03-flutter-clients.md](../../api-contract/references/03-flutter-clients.md) ("Where the test gets the spec", "Where the examples come from", "The contract test"). Follow it; do not restate the path or the example rules in a project's docs. What this skill adds is how to judge the test:

- **It must be able to fail.** An operation with no example fails the test rather than passing silently, the failure mode 7.3 of `flutter-standards` 12 warns about.
- **Fails on a missing or renamed field.** `json['id'] as String` on a missing key throws a `TypeError` (checked with Dart 3.13.7), and the DTOs cast this way ([`flutter-standards` 10, data/dto](../../flutter-standards/references/10-feature-anatomy-worked-example-auth.md)), so a renamed required field fails the decode. An optional field renamed on the server decodes to `null` silently (`as String?`); 03 says how the example and the test cover that.
- **Location.** Next to the feature's other data tests ([`flutter-standards` 12, 7.1](../../flutter-standards/references/12-testing.md), Repository row, `test/features/<f>/data/`).
- See it fail: rename a field in the fixture's example, run the test.

## What a contract test is not

- It does not prove behavior. "The server returns 409 when the order is not pending" is a NestJS e2e test (`04-nestjs-e2e-and-db.md`). The contract test proves only that both sides read the same shape.
- It does not replace the error-shape check. That the error body is `{ code, message, requestId }` on every error is an e2e assertion against the running app (05, 4.3).
- Breaking-change rules (what counts as breaking, versions, deprecation windows) are in `api-contract` and [05, 4.3](../../nestjs-standards/references/05-rules.md). A staleness diff shows the change; review decides whether it is allowed.

## Sources

- Ham Vocke, "The Practical Test Pyramid", martinfowler.com, section "Contract Tests", published 26 February 2018 (final installment), read 2026-11-04. https://martinfowler.com/articles/practical-test-pyramid.html
- Dart SDK 3.13.7 (with Flutter 3.47.8), a local run on 2026-11-04 of `json['id'] as String` on a map without `id` (throws `TypeError`) and `as String?` on a missing key (yields `null`). Command output, no URL.
- OpenAPI Specification: the facts this file relies on are cited in [`api-contract/references/03-flutter-clients.md`](../../api-contract/references/03-flutter-clients.md), Sources.
