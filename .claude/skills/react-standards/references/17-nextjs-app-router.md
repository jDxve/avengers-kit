## Next.js App Router (kit addition)

Scope: what a Next.js App Router project needs beyond the rest of this standard: the version it is written against, the server and client boundary, caching and revalidation, route handlers and server actions, middleware, cookie auth to a NestJS backend, and deployment. It extends [05-rules.md](05-rules.md) 4.2 (server components) and [04-structure.md](04-structure.md) (the `src/app/` layout) and does not restate them. Security checks with their verify steps live in `security-engineering` [10-web.md](../../security-engineering/references/10-web.md) (`SEC-WEB-*`) and are cited by id. The repo's established convention beats this file, and you say so when they differ, except Zod, which repo convention never overrides. Statements about Next.js behavior come from the documentation listed under Sources; the rest is marked kit rule or links the standard that owns it.

### 1. Version first

Read `next` in `package.json` and `next.config.*` before applying anything below, and write in the repo which major is in use and which caching model is on (4.2 already requires the caching semantics to be stated). Everything below is written against the Next.js 16.4.5 documentation, read on 2026-11-08. The upgrade guide for v16 says the docs bundled with the installed version live in `node_modules/next/dist/docs/` from 16.2 on; on any other version, read those instead of trusting this table.

| What | On v16, per the docs | Earlier |
| --- | --- | --- |
| Middleware file | `middleware.ts` is deprecated and renamed `proxy.ts`, with a `proxy` export. Proxy runs on the Node.js runtime only; a project that needs the edge runtime keeps `middleware.ts` | `middleware.ts` |
| Request APIs | `cookies()`, `headers()`, `draftMode()`, `params`, and `searchParams` are async only; synchronous access is removed | v15 had a temporary synchronous compatibility period |
| Caching model | Two models. Cache Components (`cacheComponents: true`, `use cache`, `cacheLife`, `cacheTag`) is on in new apps created with the recommended `create-next-app` defaults. The previous model uses `fetch` cache options and route segment config | Previous model only |
| `fetch` default | `auto no cache`: caching is opt-in through `cache: 'force-cache'` | Check the docs of the installed version |
| `GET` route handlers | Dynamic by default (changed in v15.0.0-RC, per the route handler version history). With Cache Components, `GET` handlers follow the same prerendering model as pages | Static by default before v15 |
| Revalidation | `revalidateTag(tag, profile)` needs the second argument (`'max'` recommended); `updateTag(tag)` is new and works only in Server Actions | `revalidateTag(tag)` |
| Node.js | 20.9 minimum | Check the docs of the installed version |

When the installed major differs from this table, the project records the difference next to its caching statement, and the reference is updated through the kit, never from memory.

### 2. Server components and the client boundary

The rules are in 05 4.2: server by default, `"use client"` as low as possible, no server-only code reachable from a client component, and an explicit cache option on every fetch. What this adds:

- Every module that reads a secret, a non-public env var, the backend's server-to-server credential, or a database client starts with `import 'server-only'`, so a client import fails the build (4.2). The Next.js data security guide recommends a Data Access Layer as the only code that reads `process.env` and talks to data sources; in this standard that is the server half of `lib/api/` and `lib/config/` ([04-structure.md](04-structure.md); kit rule). Check: `SEC-WEB-15`.
- Props passed from a server component to a client component, and values a Server Action returns, are serialized to the browser. Pass a mapped view type, never a raw API or database record. Check: `SEC-WEB-16`.
- Server components call the backend through the same `lib/api/` client as the browser does, so errors are normalized once (4.4). How the generated types meet that client is in `api-contract` [02-web-clients.md](../../api-contract/references/02-web-clients.md).
- No mutation during render. The docs state that cookies cannot be set during Server Component rendering and that mutations (sign-out, writes, cache invalidation) belong in a Server Action or route handler.

### 3. Caching and revalidation

Kit rules, applied to the model the project recorded in section 1:

1. **Every cache decision is explicit.** Previous model: every server `fetch` states `cache: 'no-store'`, `cache: 'force-cache'`, or `next: { revalidate: <seconds> }`. Cache Components: every `use cache` scope sets a `cacheLife`; the docs recommend this and apply an implicit `default` profile otherwise.
2. **Per-user data never lands in a shared cache.** This is the `Cache-Control` rule in `nestjs-standards` [12-api-behavior-and-external-dependencies.md](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) (HTTP), applied to the Next.js server's own caches:
   - The `fetch` docs say `force-cache` will cache any request, including `POST` and requests that send `authorization` or `cookie` headers, keyed by URL, method, headers, and body. A per-user backend call uses `cache: 'no-store'`, so a response for one credential is not stored on the server at all.
   - A `use cache` function cannot read `cookies()` or `headers()`; the docs say to read them outside and pass the values in, and arguments become part of the cache key. Per-user data goes into `use cache` only when the user id is an argument and the contract says so. `use cache: private` is the docs' option for functions that must read request data; in production it is not stored in a server cache across requests.
   - Dynamically rendered pages get `Cache-Control: private, no-cache, no-store, max-age=0, must-revalidate` (self-hosting guide). A route handler that returns per-user data sets `Cache-Control: private, no-store` itself, and any CDN in front must honor it (`SEC-API-17` is the backend half).
3. **After a mutation, revalidate by tag or path.** From a Server Action, `updateTag(tag)` gives read-your-writes. From a route handler, use `revalidateTag(tag, 'max')` or `revalidatePath(path)`. Neither works in proxy or a client component. If client components also hold the same resource in the query layer, the mutation invalidates that query too (4.4), and the project avoids caching one resource in both places (`03-stack.md`, "On the server-state row").
4. **User B never sees user A's page.** Prove it with a Playwright test: sign in as A in one browser context and load a per-user page; sign in as B in a fresh context, load the same URL, and assert none of A's markers render; then assert the page response carries `Cache-Control: private`. Where there is no e2e suite yet, record the same steps as a manual check in the contract's Tests section, with who ran it and when.

### 4. Route handlers and server actions

Both are public endpoints. The data security guide states that an exported Server Action is reachable by a direct POST request, not only through the UI, and the proxy docs add that Server Actions are POSTs to the route that uses them, so a proxy matcher change can silently remove its coverage. Every handler and every action therefore does, in order:

1. Parse its input with a Zod schema from the feature's `schemas/` ([04-structure.md](04-structure.md)). Route params count as input: the guide's audit list calls bracketed folders user input.
2. Authenticate and authorize inside itself, including ownership of the resource, never only in a layout, page, or proxy. Checks: `SEC-WEB-12` (actions), `SEC-WEB-13` (handlers).
3. Call the backend through the `server-only` part of `lib/api/`, with a timeout and bounded retries (nestjs 12, "Outbound calls"). A retried irreversible submit forwards the user's one `Idempotency-Key` (4.5, `api-contract`).
4. Return only what the UI needs, and map failures to the generic message plus `requestId` (4.6). Check: `SEC-WEB-16`, `SEC-WEB-20`.

More rules:

- A route handler that calls NestJS server to server holds the base URL and credentials in server env only, never under `NEXT_PUBLIC_`, which is inlined into the client bundle at build time (self-hosting guide). Check: `SEC-WEB-17`.
- The base URL comes from server config, never from the request, so a handler cannot be pointed at another host (kit rule).
- Server Actions compare `Origin` with `Host` (or `X-Forwarded-Host`) and abort on a mismatch. Add domains to `serverActions.allowedOrigins` only for the project's own proxy or CDN, and record why. The docs describe no such check for route handlers, so a cookie-authenticated route handler that changes state needs the CSRF control in `SEC-WEB-08` (kit rule).
- Closure variables of an inline Server Action are encrypted and sent to the client and back; the docs advise against relying on that encryption to hide sensitive values. Do not close over secrets.

### 5. Middleware (`proxy.ts` on v16)

Use it for redirects, rewrites, headers (security headers, a CSP nonce), and an early redirect to sign-in that only improves the experience. It is never the authorization layer: the NestJS API enforces, and every page, route handler, and Server Action checks for itself (kit rule; `nestjs-standards` [09-security-baseline.md](../../nestjs-standards/references/09-security-baseline.md)). Check: `SEC-WEB-14`.

The published example: CVE-2025-29927 (GitHub advisory GHSA-f82v-jwr5-mffw, critical, published 2025-03-21), "Authorization Bypass in Next.js Middleware". The advisory states that authorization checks could be bypassed if they occur in middleware, fixed in 15.2.3, 14.2.25, 13.5.9, and 12.3.5, with the workaround of blocking external requests that carry the `x-middleware-subrequest` header. An app that also authorized in each route stayed protected.

Also from the proxy docs:

- Without a `matcher`, proxy runs on every request, including `_next/static`, image optimization, and `public/`. Set a matcher, and exclude static paths so a redirect cannot block CSS or JS.
- The runtime is Node.js and cannot be configured; setting `runtime` throws.

### 6. Cookie auth to a NestJS backend

Two patterns. Which one a project uses is a decision in its contract, with the reason.

| | Backend for frontend (BFF) | Direct |
| --- | --- | --- |
| Browser talks to | Next.js only | NestJS, on the same site as the app |
| Session cookie set by | A Next.js route handler or Server Action, through `cookies().set` with `httpOnly`, `secure`, and `sameSite` (the options the `cookies` docs list) | NestJS |
| Next.js to NestJS | Server to server with a bearer token that never leaves the server, held in the server-side session or an encrypted cookie | A server component forwards the incoming session cookie |
| CSRF | Server Actions: the origin check in section 4. State-changing route handlers: `SEC-WEB-08` | NestJS per `nestjs-standards` 09 (`SEC-API-16`), and CORS limited to known origins with credentials (`SEC-API-14`) |
| Token refresh runs | On the Next.js server, single-flight per session (07, race 8, applied server side; kit rule) | In the browser client, single-flight ([07-async-correctness.md](07-async-correctness.md), race 8) |

Invariants for both:

- Session cookies set `HttpOnly`, `Secure`, and a deliberate `SameSite`, and use the `__Host-` prefix when scoped to one host. Check: `SEC-WEB-06`.
- No token is readable by page JavaScript, or the exposure is accepted in writing per [10-security.md](10-security.md). Check: `SEC-WEB-07`.
- Refresh is single-flight, and only an authentication failure ends the session (07, race 8).
- Sign-out runs in a Server Action or route handler that deletes the cookie, clears the query cache and client state, and expires per-user cache tags (10-security.md). Check: `SEC-WEB-09`.
- Server code forwards the session cookie or token only to the project's own API origin from server config, never to a URL built from request data (kit rule).
- NestJS still authorizes every request. A BFF holding a valid token is not a reason to skip an ownership check (`SEC-API-01`).

### 7. Deployment

- Set `output: 'standalone'` in `next.config.*`. The build writes `.next/standalone` with a minimal `server.js`, which does not copy `public/` or `.next/static` by default, and reads `PORT` and `HOSTNAME` from the environment. The template is `devops-engineering` [Dockerfile.nextjs](../../devops-engineering/assets/Dockerfile.nextjs), and the CI template is [ci-web.yml](../../devops-engineering/assets/ci-web.yml), both indexed in the [assets README](../../devops-engineering/assets/README.md).
- Build once and promote the same image (`devops-engineering`, Artifacts). `NEXT_PUBLIC_*` values are inlined at build time, so a value that differs per environment is read on the server at request time instead, as the self-hosting guide describes.
- More than one instance needs the same `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` on every instance (a base64 AES key of 16, 24, or 32 bytes, from the secret store), a `deploymentId` for version skew, and cache tag coordination with a shared cache handler (self-hosting guide).
- A reverse proxy in front must not buffer responses, or streaming stops working (self-hosting guide).

## Sources

- Next.js documentation, version 16.4.5 (from `https://nextjs.org/docs/llms.txt`), read 2026-11-08. Pages, each with the `lastUpdated` date it shows:
  - Upgrading to version 16, 2026-11-06: https://nextjs.org/docs/app/guides/upgrading/version-16
  - How to think about data security in Next.js, 2026-10-06: https://nextjs.org/docs/app/guides/data-security
  - Caching, 2026-10-06: https://nextjs.org/docs/app/getting-started/caching
  - Caching (Previous Model), 2026-08-18: https://nextjs.org/docs/app/guides/caching-without-cache-components
  - `fetch`, 2026-08-18: https://nextjs.org/docs/app/api-reference/functions/fetch
  - `use cache`, 2026-11-06: https://nextjs.org/docs/app/api-reference/directives/use-cache
  - `use cache: private`, 2026-10-15: https://nextjs.org/docs/app/api-reference/directives/use-cache-private
  - `revalidatePath` 2026-06-25, `revalidateTag` 2026-08-25, `updateTag` 2026-08-18: https://nextjs.org/docs/app/api-reference/functions/revalidatePath, https://nextjs.org/docs/app/api-reference/functions/revalidateTag, https://nextjs.org/docs/app/api-reference/functions/updateTag
  - `route.js` (route handlers), 2026-04-30: https://nextjs.org/docs/app/api-reference/file-conventions/route
  - Server Actions guide, 2026-10-15: https://nextjs.org/docs/app/guides/server-actions
  - `proxy.js`, 2026-11-06: https://nextjs.org/docs/app/api-reference/file-conventions/proxy
  - `cookies`, 2026-11-06: https://nextjs.org/docs/app/api-reference/functions/cookies
  - `output`, 2026-09-18: https://nextjs.org/docs/app/api-reference/config/next-config-js/output
  - Self-Hosting, 2026-10-15: https://nextjs.org/docs/app/guides/self-hosting
- GitHub Advisory GHSA-f82v-jwr5-mffw (CVE-2025-29927), "Authorization Bypass in Next.js Middleware", published 2025-03-21, read 2026-11-08: https://github.com/advisories/GHSA-f82v-jwr5-mffw
- OWASP Session Management Cheat Sheet and Cross-Site Request Forgery Prevention Cheat Sheet, and MDN `Set-Cookie`: not re-read for this file. They are cited through `security-engineering` [10-web.md](../../security-engineering/references/10-web.md), which read them on 2026-11-04, and this file makes no claim from them directly.
- Kit standards: `react-standards` 04, 05 (4.2, 4.4 to 4.6), 07, 10; `nestjs-standards` 09 and 12; `security-engineering` 10-web and 20-api; `api-contract` 02; `devops-engineering` SKILL.md and assets, linked in place.
