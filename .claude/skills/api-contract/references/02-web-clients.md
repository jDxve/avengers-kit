# Web clients: React and Next.js

How a React or Next.js app consumes the published contract: where the types come from, how the one client uses them, and how server-side calls in Next.js stay on the same path. The rules are owned by `react-standards`: wire types are generated, never hand-written ([section 2 (`03-stack.md`)](../../react-standards/references/03-stack.md), "Wire types" row, and [4.4](../../react-standards/references/05-rules.md)); all network access goes through one client in `lib/api/` (4.4); the generated file is checked for staleness in CI ([11.6](../../react-standards/references/12-enforcing-this-automatically.md)). This file adds how those rules meet the backend side in `01-nestjs-publishing.md`.

## Where the schema comes from

`$API_SCHEMA` in react 11.6 is a committed `openapi.json` or a pinned, versioned URL, never a live dev server.

| Layout | `$API_SCHEMA` | Who bumps it |
| --- | --- | --- |
| Monorepo, backend and web together | Path to the backend's committed `openapi.json` | The change that edits the schema regenerates the web types in the same commit |
| Separate repos | A URL to a released copy of `openapi.json`, pinned to a tag or commit | A web change that bumps the pin and regenerates the types |

Either way, the commit that changes `types.gen.ts` is the one where the web app first sees the API change, and its diff is the review.

## Generating the types

The command and the check script are in react 11.4 and 11.6 (`api:types`, `api:check`, `scripts/verify-api-types.sh`). From the openapi-typescript 7.x docs:

- It reads OpenAPI 3.0 and 3.1, as JSON or YAML, from a file or a URL. It does not list 3.2 (see `01-nestjs-publishing.md` on choosing the version).
- It needs Node.js 20 or higher (recommended in its setup).
- It produces types only, with no runtime code. A response is not checked at run time because a type exists for it.
- It has a `--check` flag that checks the generated types are current. The react 11.6 script does the same with a diff and also prints the fix command; either satisfies 11.6.
- Flags such as `--enum`, `--immutable`, `--root-types`, and `--default-non-nullable` change the shape of every generated type. Set them once in `api:types`. Changing one regenerates the whole file, and that diff no longer reads as an API change.

## Using the types in the one client

The generated file exports `paths` and `components`. Look up names in `openapi.json`: nestjs-zod suffixes output schemas registered with `.meta({ id })` with `_Output` (`01-nestjs-publishing.md`).

```ts
// src/lib/api/types.ts: names the rest of the app imports. Adapters, not wire types.
import type { components, paths } from './types.gen';

export type ApiError = components['schemas']['ErrorResponse'];
export type Order = components['schemas']['Order_Output'];
export type CreateOrderBody =
  NonNullable<paths['/orders']['post']['requestBody']>['content']['application/json'];
export type ListOrdersQuery = paths['/orders']['get']['parameters']['query'];
```

What the client in `src/lib/api/client.ts` ([react section 3 (`04-structure.md`)](../../react-standards/references/04-structure.md)) does with them:

- Every error response is normalized to `ApiError` in one place, and callers branch on `code` (react 4.4, nestjs 4.3). Copy for each code lives in the web app, not in `message` (`04-errors-and-versioning.md`).
- The `requestId` reaches the error UI and the error tracker (react 4.4, [4.6](../../react-standards/references/05-rules.md)).
- Where the response shape matters, parse it with a Zod schema at the boundary before use (react 4.4). The generated types have no runtime part, so this parse is the only thing that fails loudly when the server sends something else.
- A request body is built from the generated request type, so the form submits only fields the API defines. Backend request schemas are `.strict()`, so an extra key is a 400 (react 4.5, nestjs 4.3).
- A retried irreversible submit reuses one `Idempotency-Key` for the same user intent (react 4.5; server behavior in `05-idempotency-and-pagination.md`).
- List queries put the cursor or page in the URL and in the query key (react [4.3](../../react-standards/references/05-rules.md), 4.4). The client passes the cursor back exactly as received and never parses it.

A hand-maintained `interface OrderResponse` is not acceptable, whatever the contract format (react section 2, "On the wire-types row"). An adapter that maps a wire type to a view model is fine, and is visibly an adapter (react 4.4).

## Server-side calls from Next.js

`react-standards` [4.2](../../react-standards/references/05-rules.md) owns the server and client boundary. What it means for the API client:

- A server component that reads data for first paint calls the backend through the same `lib/api/` module, so error normalization and the `code` branch exist once (react 4.4). A second fetch wrapper for the server is the "fifteen slightly different versions" that 4.4 forbids.
- The module that holds server-only configuration (the backend base URL for server calls, anything read from a secret) is marked `server-only`, so importing it from a client component fails the build (react 4.2).
- Every server fetch states its cache option explicitly (react 4.2). A per-user response must never land in a shared cache ([nestjs section 11 (`12-api-behavior-and-external-dependencies.md`)](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) "HTTP", "Correct status codes, and an explicit `Cache-Control` policy").
- Caching semantics, revalidation, server actions, and cookie auth to the NestJS backend belong to the `react-standards` reference [`17-nextjs-app-router.md`](../../react-standards/references/17-nextjs-app-router.md).

## Contract tests on the web side

- The staleness check (react 11.6) proves `types.gen.ts` matches the schema it was generated from.
- `tsc --noEmit` then proves the app compiles against the new types. A removed or renamed field becomes a compile error at each use, which is the reason the types are generated.
- MSW handlers in `src/test/` (react section 3) return bodies typed with the generated types, so a mock cannot drift from the contract silently. Which tests to write is in the `testing-strategy` skill, `05-contract-tests.md`.

## Sources

- openapi-typescript documentation, 7.x (npm latest 7.13.0), Introduction and CLI pages, read 2026-11-04: https://openapi-ts.dev/introduction and https://openapi-ts.dev/cli
- nestjs-zod README, main branch at commit a7157f0, npm latest 5.5.0, section "Reusable schemas", "Schema names": https://github.com/BenLorantfy/nestjs-zod
