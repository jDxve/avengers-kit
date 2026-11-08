# Flutter clients

How a Flutter app consumes the published contract. The kit keeps `retrofit` services with hand-written DTOs, as [`flutter-standards` "Stack" (`04-stack.md`)](../../flutter-standards/references/04-stack.md) sets ("Codegen: `retrofit` for services, and nothing else by default"), and checks those DTOs against `openapi.json` with a contract test instead of generating a Dart client (kit-skills contract, Decision 4). A generated Dart client stays open as kit-skills OD-6 and would need a change to `flutter-standards` "Stack" and an ADR. This file adds the contract test and the mapping from the spec to a DTO; the service and DTO patterns are owned by [`flutter-standards` section 5 (`10-feature-anatomy-worked-example-auth.md`)](../../flutter-standards/references/10-feature-anatomy-worked-example-auth.md) ("data/services (Retrofit)", "data/dto").

## Why a test is needed

Hand-written decoding has no compile-time link to the server. The Flutter JSON documentation says it directly: with manual decoding, a typo in a field name throws at run time, not at compile time. On the web the generated types turn a renamed field into a compile error (`02-web-clients.md`). In Flutter the decode test is what turns it into a failing test before release, and in a repository this mapping failure surfaces as `AppException.unexpected` ([flutter section 3 (`08-core-layer.md`)](../../flutter-standards/references/08-core-layer.md), "AppException").

## Reading the spec into a DTO

For each response DTO, read the response schema in `openapi.json` (follow its `$ref` into `components.schemas`) and mirror it by hand:

| In the schema | In the DTO |
| --- | --- |
| Property listed in `required` and not nullable | Non-nullable field, cast with `as T` |
| Property not in `required`, or nullable | Nullable field, `as T?` |
| Nullable, OpenAPI 3.0 | `nullable: true` on the property |
| Nullable, OpenAPI 3.1 | `anyOf` (or a `type` list) that includes `null` |
| `$ref` to another schema | A nested DTO with its own `fromJson` |
| `enum` of strings | A Dart enum. nestjs 4.3 does not say whether a new value is breaking, so the contract states what the app does with an unknown one |

The 3.0 and 3.1 forms come from the nestjs-zod `cleanupOpenApiDoc` table (`01-nestjs-publishing.md`); the project's chosen version decides which one the test reads. Request DTOs mirror the request schema the same way, and send only properties the schema lists, because backend request schemas are `.strict()` and reject unknown keys with a 400 ([nestjs 4.3](../../nestjs-standards/references/05-rules.md)).

DTOs stay plain classes with `fromJson`, `toJson`, and `toDomain()`, and never leak past the repository (flutter section 5, "data/dto").

## Where the test gets the spec

This file owns the fixture path and the location of the examples; other references link here rather than restate them. The test reads a pinned copy of `openapi.json` at `test/fixtures/openapi.json`, taken from the same source the web app uses: the backend's committed file or a pinned released URL, never a running server ([react 11.6](../../react-standards/references/12-enforcing-this-automatically.md) states the rule for the web side). Updating that copy is a deliberate change, and its diff is where the Flutter side first sees an API change.

## Where the examples come from

The kit's export script writes OpenAPI 3.0 (`setOpenAPIVersion('3.0.0')` in `01-nestjs-publishing.md`), so the test reads examples where OpenAPI 3.0 puts them, in this order:

1. The response's Media Type Object: `example` (one payload) or `examples` (a map of Example Objects, each holding its payload in `value`). The two are mutually exclusive.
2. Otherwise the response schema's `example`, after following its `$ref`. In OpenAPI 3.0 the Schema Object has only `example`, singular; it has no `examples` keyword.

OpenAPI 3.1 and 3.2 differ: there the Schema Object is a JSON Schema draft 2020-12 schema, so it carries an `examples` array and `example` is deprecated. A project that exports 3.1 or later reads that array instead of step 2, and records the choice in its contract.

The specification says an example SHOULD be compatible with its schema and that tooling MAY validate this, so an example is only evidence when something checks it. On the backend, Zod's `.meta({ examples: [...] })` stores examples in the schema's metadata, which `z.toJSONSchema` carries into the generated schema as a JSON Schema `examples` array (Zod metadata and JSON Schema docs). That array is not a 3.0 Schema Object field, so open the exported `openapi.json` and confirm the project's toolchain emits each example in one of the two places above. If it does not, record that in the contract's Tests section; do not invent a separate fixture format.

An operation with no example fails the test (`_obj` on `null`), because a DTO with nothing to decode is unchecked. An optional field renamed on the server decodes to `null` silently (`as String?`), so the spec carries one example with every optional field the app reads set, and its decode test also asserts that each of those fields is non-null.

## The contract test

One file per feature, beside the repository tests in the flutter test matrix ([7.1](../../flutter-standards/references/12-testing.md)). No Dio, no mock server: it reads JSON and calls `fromJson` and `toJson`.

```dart
// test/features/auth/data/auth_contract_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/data/dto/auth_dtos.dart';

typedef Json = Map<String, dynamic>;

final Json _spec =
    jsonDecode(File('test/fixtures/openapi.json').readAsStringSync()) as Json;

Json _obj(Object? value, String where) {
  if (value is! Map<String, dynamic>) fail('openapi.json: no object at $where');
  return value;
}

/// Follows a local `$ref` such as `#/components/schemas/LoginRequest`.
Json _resolve(Json node) {
  final ref = node[r'$ref'];
  if (ref is! String) return node;
  Object? target = _spec;
  for (final part in ref.substring(2).split('/')) {
    target = _obj(target, ref)[part];
  }
  return _obj(target, ref);
}

Json _media(Json container, String where) =>
    _obj(_obj(container['content'], where)['application/json'], where);

Json _operation(String path, String method) =>
    _obj(_obj(_obj(_spec['paths'], 'paths')[path], path)[method], '$method $path');

/// OpenAPI 3.0: Media Type `example` or `examples`, else the Schema Object's `example`.
Json _responseExample(String path, String method, String status) {
  final where = '$method $path $status';
  final responses = _obj(_operation(path, method)['responses'], where);
  final media = _media(_obj(responses[status], where), where);
  final examples = media['examples'];
  final schema = media['schema'];
  final example = media['example'] ??
      (examples is Map<String, dynamic> && examples.isNotEmpty
          ? _obj(examples.values.first, where)['value']
          : null) ??
      (schema is Map<String, dynamic> ? _resolve(schema)['example'] : null);
  return _obj(example, '$where example');
}

Json _requestSchema(String path, String method) {
  final where = '$method $path requestBody';
  final body = _obj(_operation(path, method)['requestBody'], where);
  return _resolve(_obj(_media(body, where)['schema'], where));
}

void main() {
  test('LoginResponseDto decodes the documented 200 example', () {
    final json = _responseExample('/auth/login', 'post', '200');
    expect(() => LoginResponseDto.fromJson(json), returnsNormally);
  });

  test('LoginRequestDto sends exactly the fields the request schema allows', () {
    final schema = _requestSchema('/auth/login', 'post');
    final allowed = _obj(schema['properties'], 'properties').keys.toSet();
    final required = ((schema['required'] as List?) ?? const []).cast<String>().toSet();
    final sent = const LoginRequestDto(email: 'user@example.com', password: 'not-a-real-password')
        .toJson()
        .keys
        .toSet();

    expect(sent.difference(allowed), isEmpty, reason: 'strict schema returns 400 on unknown keys');
    expect(required.difference(sent), isEmpty, reason: 'required field missing from toJson');
  });
}
```

What each case catches:

| Server change | Caught by |
| --- | --- |
| A response field the DTO reads is removed or renamed | Decode test: the cast of the missing key throws |
| A response field changes type | Decode test: the cast throws |
| A request field is renamed or removed | Request test: the DTO sends a key the schema no longer allows |
| A request field becomes required | Request test: the required set is not covered |
| A new optional response field | Nothing fails, which is correct: it is additive (nestjs 4.3) |

Test honesty ([flutter 7.3](../../flutter-standards/references/12-testing.md)) applies: rename one property in the fixture example and watch the decode test fail, and add an unknown key to the DTO's `toJson` and watch the request test fail, before trusting either. Fixture values are obviously fake, as flutter section 5 "Before the API exists" requires of sample data.

## Errors and the key header

- The error body is the kit shape `{ code, message, requestId }` (nestjs 4.3). `flutter-standards` section 3 ("Dio error mapper") classifies by status into `ErrorType` and reads only `message`, sanitized, for `rejected`. It also says that when the backend sends stable codes, map them to local strings and keep the message as the fallback. `AppException` has no `code` field today, so branching on `code` in Flutter needs a change to `flutter-standards` section 3, which Dave decides. Until then, the contract lists which codes the app shows its own copy for.
- `Idempotency-Key` is sent through `@Header(kIdempotencyKeyHeader)`, one key per user intent, owned by the notifier (flutter section 5, "data/services (Retrofit)"). The header's value format is in `05-idempotency-and-pagination.md`.

## Sources

- Flutter documentation, "JSON and serialization", page last updated 2026-07-31, site reflecting Flutter 3.47: https://docs.flutter.dev/data-and-backend/serialization/json
- Dart documentation, "Using JSON", site reflecting Dart 3.13.7, page last updated 2026-02-02: https://dart.dev/libraries/serialization/json
- OpenAPI Specification 3.0.4, Media Type Object, Example Object, and Schema Object `example` ("Working with Examples"): https://spec.openapis.org/oas/v3.0.4.html
- OpenAPI Specification 3.2.1 of 10 September 2026, Schema Object (JSON Schema draft 2020-12 `examples`, `example` deprecated), read 2026-11-04, cited only for the 3.1 and later difference: https://spec.openapis.org/oas/latest.html
- Zod documentation, "Metadata and registries" and "JSON Schema", read 2026-11-04 (site announcing Zod 4.6): https://zod.dev/metadata and https://zod.dev/json-schema
- nestjs-zod README, main branch at commit a7157f0, npm latest 5.5.0, `cleanupOpenApiDoc` table: https://github.com/BenLorantfy/nestjs-zod
