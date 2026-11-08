# Publishing the contract from NestJS

How a NestJS service turns its Zod schemas into a committed `openapi.json` that clients build against, and the CI step that fails when the committed file is stale. The validation rules themselves (global `ZodValidationPipe`, `.strict()` request schemas, response DTOs, the error shape) are owned by [`nestjs-standards` 4.3](../../nestjs-standards/references/05-rules.md) and are not repeated here. This file adds the wiring between those rules and the published document.

## The pieces and what each one does

| Piece | Role | Source |
| --- | --- | --- |
| `createZodDto(schema)` | One class that the validation pipe validates against and `@nestjs/swagger` documents | nestjs-zod README, `createZodDto` |
| `ZodValidationPipe` (global) | Validates `@Body()`, `@Query()`, `@Param()` | nestjs-zod README; required by nestjs 4.3 |
| `ZodSerializerInterceptor` (global) | Validates and strips response bodies against the response DTO | nestjs-zod README, Response Validation |
| `@ZodResponse({ type: Dto })` | Sets the run-time serializer, the compile-time return type, and the documented response from one declaration | nestjs-zod README, `ZodResponse` |
| `cleanupOpenApiDoc(doc)` | Post-processes the document so it is valid for the chosen OpenAPI version | nestjs-zod README: required when using `@nestjs/swagger` |
| `SwaggerModule.createDocument` | Builds the document from routes and DTOs | NestJS OpenAPI docs, Introduction |

Response DTOs are required by nestjs 4.3, and `@ZodResponse` is the way to declare them. The nestjs-zod README recommends it over separate `@ZodSerializerDto` and `@ApiOkResponse` decorators, because those three declarations can drift apart. It also emits the "output" variant of the schema, which matters for schemas whose input and output types differ (defaults, coercion, codecs).

With Zod 4.2 or later, `@nestjs/swagger` can also convert schemas itself through the Standard JSON Schema extension (NestJS OpenAPI docs, "Standard Schema (Zod, Valibot)"). The kit's path is nestjs-zod (nestjs 4.3, ADR-012). Do not configure a second converter; if a repo already has one, report it rather than choosing between them.

```ts
// src/modules/orders/orders.controller.ts
@Post()
@ZodResponse({ status: 201, type: OrderDto })
create(@Body() body: CreateOrderDto): Promise<OrderDto> {
  return this.orders.create(body);
}
```

## The OpenAPI version

- `@nestjs/swagger` builds the document with `openapi: '3.0.0'` unless `DocumentBuilder.setOpenAPIVersion()` sets another (read in the `@nestjs/swagger` source, `lib/fixtures/document.base.ts`).
- `cleanupOpenApiDoc` takes `version: '3.0' | '3.1' | 'auto'`, default `auto`, which follows the document's own version. The output differs: a nullable string is `nullable: true` under 3.0 and an `anyOf` with `null` under 3.1 (nestjs-zod README).
- OpenAPI patch versions change no features: tooling should treat 3.0.0 and 3.0.4 alike (OpenAPI Specification 3.0.4, "Versions").
- The latest published OpenAPI Specification is 3.2.1. `openapi-typescript` 7.x documents support for 3.0 and 3.1 only, so a move to 3.2 waits until every consumer's tool supports it.

Pick one version per project, set it in `DocumentBuilder` and in `cleanupOpenApiDoc`, and write it in the project's decisions file. Flutter's decode test reads `nullable` differently in 3.0 and 3.1 (see `03-flutter-clients.md`).

## Reusable schemas and names

- A schema with `.meta({ id: 'Money' })` becomes `components.schemas.Money` and is referenced by `$ref` (nestjs-zod README, Reusable schemas).
- For output schemas, nestjs-zod suffixes that id with `_Output` (for example `Money_Output`), so the request and response variants do not collide. Web types are looked up by these names (`02-web-clients.md`), so renaming an `id` renames a type in every client: treat it as a breaking change to the generated code even when the wire shape is unchanged.

## The error shape in the document

The error contract in nestjs 4.3 is part of the API, so it belongs in `openapi.json`:

- Define the error response once as a Zod schema with `.meta({ id: 'ErrorResponse' })`, and reference it from each operation's error responses with `@ApiResponse({ status, type })` (NestJS OpenAPI docs, Operations, Responses).
- nestjs-zod's own failures do not use the kit shape by default. A failed request parse throws `ZodValidationException`, whose default body is `{ statusCode, message, errors }`; a failed response serialization throws `ZodSerializationException`, which becomes a plain 500 (nestjs-zod README). The exception filter from [nestjs 4.6](../../nestjs-standards/references/05-rules.md) maps the first to a 400 carrying a stable `code` and the `requestId`, and treats the second as an unexpected failure: a generic 500 with the request id, logged and sent to error tracking.
- The kit shape has no member for field-level errors, while [`react-standards` 4.5](../../react-standards/references/05-rules.md) maps server field errors onto form fields. A feature that needs field errors records that in its contract's Open decisions; adding a member is a change to nestjs 4.3, which Dave decides.

## Export script

The document is built by a script, not fetched from a running server, so the output depends only on the code at that commit ([react 11.6](../../react-standards/references/12-enforcing-this-automatically.md) makes the same point for the client side).

```ts
// scripts/export-openapi.ts
import { writeFileSync } from 'node:fs';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { AppModule } from '../src/app.module';

async function main(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: false });
  const config = new DocumentBuilder()
    .setTitle('API')
    .setVersion('1')
    .setOpenAPIVersion('3.0.0') // the version the project chose
    .build();
  const doc = cleanupOpenApiDoc(SwaggerModule.createDocument(app, config), { version: '3.0' });
  writeFileSync(process.env.OPENAPI_OUT ?? 'openapi.json', `${JSON.stringify(doc, null, 2)}\n`);
  await app.close();
}

main().catch((error: unknown) => {
  process.stderr.write(`${String(error)}\n`);
  process.exitCode = 1;
});
```

```json
{
  "scripts": {
    "openapi:export": "ts-node scripts/export-openapi.ts",
    "openapi:check": "bash scripts/verify-openapi.sh"
  }
}
```

Use the TypeScript runner the repo already has in place of `ts-node`; adding one needs a stated requirement (AGENTS.md rule 6).

Creating the app builds the module graph, so boot-time env validation (nestjs 4.3) runs. Run the export in the CI job that already provides the e2e environment, as the CI gate in [nestjs section 10 (`11-enforcing-this-automatically.md`)](../../nestjs-standards/references/11-enforcing-this-automatically.md) does by placing `openapi:check` after `test:e2e`.

## CI staleness check

The same shape as react 11.6: regenerate into a temp file and diff, without overwriting the committed file.

```bash
#!/usr/bin/env bash
# scripts/verify-openapi.sh
set -euo pipefail
tmp="$(mktemp -t openapi.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

OPENAPI_OUT="$tmp" npm run --silent openapi:export
if ! diff -u openapi.json "$tmp"; then
  echo "FAIL: openapi.json is stale."
  echo "      Run: npm run openapi:export && git add openapi.json"
  exit 1
fi
echo "OK: openapi.json is current"
```

What the check proves: the committed file matches the code. What it does not prove: that the change is compatible. That is the review of the diff against the breaking-change rules in `04-errors-and-versioning.md`.

## Serving the document

nestjs 4.3 serves OpenAPI in non-production only. `SwaggerModule.setup` exposes the UI and the JSON and YAML definitions, and its `ui` and `raw` options turn each off (NestJS OpenAPI docs, Setup options). Clients never build against the served document: they use the committed file or a pinned URL.

## Checklist for a changed endpoint

- [ ] API-PUB-01 Strict request schemas: check and Verify as `SEC-API-03` in [`security-engineering/references/20-api.md`](../../security-engineering/references/20-api.md).
- [ ] API-PUB-02 The response is declared with `@ZodResponse`, and error responses reference `ErrorResponse`. Verify: `grep -n "@ZodResponse\|@ApiResponse" <controller file>` shows one `@ZodResponse` per changed handler; in `openapi.json`, each error response of the operation has `$ref` to `#/components/schemas/ErrorResponse`.
- [ ] API-PUB-03 `openapi.json` is regenerated and committed in the same change. Verify: `npm run openapi:check` prints `OK: openapi.json is current`; `git diff --stat <base>...HEAD -- openapi.json` is not empty when a schema changed.
- [ ] API-PUB-04 The `openapi.json` diff is reviewed against `04-errors-and-versioning.md`, and a breaking change has a new version or a deprecation row in the contract. Verify: read `git diff <base>...HEAD -- openapi.json`; for each removed or renamed field, tightened validation, or changed error code, find the version or the row in the contract's Deprecations table.
- [ ] API-PUB-05 The contract's API section lists the operationId and the codes clients branch on. Verify: each `operationId` added or changed in the `openapi.json` diff has a row in the contract's API table, and each code in that row is in the module's error code list.

## Sources

- nestjs-zod README, main branch at commit a7157f0, npm latest 5.5.0, read 2026-11-04: https://github.com/BenLorantfy/nestjs-zod
- NestJS documentation, OpenAPI Introduction and Operations, docs.nestjs.com repository master branch, read 2026-11-04: https://docs.nestjs.com/openapi/introduction and https://docs.nestjs.com/openapi/operations
- `@nestjs/swagger` source, `lib/fixtures/document.base.ts` and `lib/document-builder.ts`, master branch, npm latest 12.1.0, read 2026-11-04: https://github.com/nestjs/swagger
- OpenAPI Specification 3.0.4, section "Versions": https://spec.openapis.org/oas/v3.0.4.html
- OpenAPI Specification 3.2.1 (latest published, read for the current version only): https://spec.openapis.org/oas/latest.html
- openapi-typescript documentation, 7.x, Introduction (supported OpenAPI versions): https://openapi-ts.dev/introduction
