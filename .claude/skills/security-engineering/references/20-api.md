# API security (NestJS)

Scope: verifiable checks for a NestJS API on Drizzle and Zod, grouped by the OWASP API Security Top 10 2023 categories. The rules are owned by `nestjs-standards`: [09-security-baseline.md](../../nestjs-standards/references/09-security-baseline.md), [05-rules.md](../../nestjs-standards/references/05-rules.md) 4.1, 4.3, 4.6, and 4.8, [07-concurrency-and-data-integrity.md](../../nestjs-standards/references/07-concurrency-and-data-integrity.md), and [12-api-behavior-and-external-dependencies.md](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md). Each item below names its rule's home and adds how to verify it. Category names and numbers are copied from the 2023 edition; the `SEC-API-*` ids are the kit's own and stay stable across editions.

Where a check says e2e, it means the real-database e2e suite of `nestjs-standards` 05 4.11, run locally. Nothing here runs against a shared or live system.

## API1:2023 Broken Object Level Authorization

The 2023 edition says object level authorization checks should be considered in every function that accesses a data source using an ID from the user. The kit rule is in `nestjs-standards` 09 ("IDOR checked") and 05 4.1.

- [ ] SEC-API-01 Every lookup by an id from the request (path, query, body, or header) is scoped to the caller's owner or tenant in the query itself, so another user's id returns 404, not the record. Verify: an e2e test where user B requests, updates, and deletes user A's resource by id and gets 404 each time; then trace each repository method the controller reaches and confirm its `where` includes the owner or tenant column, not only `eq(<table>.id, id)`.
- [ ] SEC-API-02 List, search, export, and count endpoints are scoped the same way, and a child id in a nested path (`/orders/:id/items/:itemId`) is checked against its parent and the caller. Verify: an e2e test that seeds rows for A and B and asserts B's list, search, and export contain none of A's ids, plus one that requests A's child id under B's parent and gets 404.

## API2:2023 Broken Authentication

Owned by `nestjs-standards` 05 4.8. NIST SP 800-63B-4 section 3.2.2 (Rate Limiting) requires verifiers to limit consecutive failed attempts and lists delays that grow with each failure, bot challenges, and risk signals as ways to reduce lockout of the real user; 4.8 states the kit's preference for escalating delay over indefinite lockout.

Mass assignment is `SEC-API-03`, under API3, where the 2023 edition files it.

- [ ] SEC-API-04 Tokens are verified, not decoded: the accepted algorithm is pinned, and issuer, audience, and expiry are checked. Verify: unit or e2e tests that send a token with `alg: none`, a token signed with the wrong key, an expired token, and a wrong-audience token, and assert 401 for each.
- [ ] SEC-API-05 Login, OTP, password reset, registration, and invite redemption are rate limited on both account and source, and repeated failures slow the caller rather than lock the owner out indefinitely. Verify: an e2e test that exceeds the configured limit for one account from two sources, and for two accounts from one source, and asserts the limit applies in both cases; read the limit values from config, never hard-code them in the test.
- [ ] SEC-API-06 Logout, password change, and role change revoke sessions as 4.8 specifies, and the four refresh rotation paths have their own tests. Verify: the four 4.8 refresh tests exist and pass (`npm run test:e2e -- -t refresh` or the project's equivalent filter), plus an e2e test that changes a password and asserts the old refresh token gets 401.

## API3:2023 Broken Object Property Level Authorization

The 2023 edition merges the 2019 categories Excessive Data Exposure and Mass Assignment into this one. Owned by `nestjs-standards` 05 4.1 (mapped response types) and 4.3 (strict schemas).

- [ ] SEC-API-03 Every request schema, and every nested object inside it, uses `.strict()`, so an unknown key such as `role`, `isAdmin`, or `status` returns 400 at any depth. Verify: `grep -rn "z.object(" src/modules/<module>` and confirm each request-side object chains `.strict()`; an e2e test that sends an unknown key at the top level and inside a nested object and asserts 400 for both.
- [ ] SEC-API-07 Every response goes through a defined response schema or mapper, never a raw Drizzle row, so internal columns (password hashes, tenant ids, soft-delete flags, internal notes) never leave the API. Verify: an e2e test per endpoint that asserts the exact key set of the response body; trace each controller method's return value and confirm it is a mapped response type, as `nestjs-standards` 05 4.1 requires.

## API4:2023 Unrestricted Resource Consumption

Owned by `nestjs-standards` 09 (payload limits, uploads) and 12 (HTTP limits, pagination, timeouts, uploads).

- [ ] SEC-API-08 Body, header, and URL size limits are set to what the endpoints accept, every list has a maximum page size, and outbound calls have connect and read timeouts. Verify: e2e tests that send a body over the limit (expect 413) and a page size over the maximum (expect 400); trace the HTTP client factory and confirm both timeouts are set.
- [ ] SEC-API-09 Uploads are size-limited before any processing, validated by content rather than extension or client MIME type, stored under server-generated keys outside any web root, and downloaded through the same authorization as any resource. Verify: e2e tests with an oversized file, a file whose extension and declared MIME type lie about its content, and B downloading A's file (expect 404); trace the storage key and confirm it never uses the client filename.

## API5:2023 Broken Function Level Authorization

Owned by `nestjs-standards` 05 4.1 (global guard, explicit per-route authorization, guard ordering).

- [ ] SEC-API-10 The auth guard is global, public routes opt out with an explicit decorator, and every non-public route declares its authorization (`@Roles(...)` or an equivalent policy). Verify: an e2e or unit test that walks the application's routes with Nest's `DiscoveryService` and `Reflector` and fails on any route with neither the public marker nor an authorization declaration; an e2e test that calls one admin route with a user token (expect 403) and with no token (expect 401).
- [ ] SEC-API-11 Global guards that read `request.user` are registered after the auth guard. Verify: trace the `APP_GUARD` providers in `app.module.ts` in registration order; an e2e test for each policy guard (password age, MFA enrollment) passes with a real authenticated request.

## API6:2023 Unrestricted Access to Sensitive Business Flows

The 2023 edition describes flows such as buying a ticket or posting a comment that harm the business when automated, without needing an implementation bug. The contract's abuse cases name them (`00-threat-modeling.md`).

- [ ] SEC-API-12 Every business flow the contract marks as sensitive (checkout, invites, referrals, comments, cancellations that release stock) has a per-account limit or an anti-automation control, and its writes are idempotent per `nestjs-standards` 07 (idempotency keys). Verify: an e2e test that repeats the flow past the configured limit and asserts the rejection code; a concurrency test with two identical requests sharing an idempotency key that asserts one effect.

## API7:2023 Server Side Request Forgery

No kit standard owns this yet. Kit rule until one does.

- [ ] SEC-API-13 Any URL the server fetches that a user can influence (webhooks the user registers, image or link previews, imports) is checked against an allowlist of schemes and hosts after parsing, redirects are not followed or are re-checked at each hop, and resolved addresses in loopback, private, and link-local ranges are refused. Verify: unit tests of the URL validator with `file:///etc/passwd`, `http://127.0.0.1/`, `http://localhost/`, a private-range address, and an allowed host that redirects to a refused one; trace each outbound fetch whose URL comes from data and confirm it calls the validator.

## API8:2023 Security Misconfiguration

Owned by `nestjs-standards` 09 (CORS, headers, CSRF), 05 4.8 (cookies), and 12 (`Cache-Control`, correlation ids).

- [ ] SEC-API-14 CORS allows only the known origins from config, and never a wildcard with credentials. Verify: an e2e test that sends a preflight with an unknown `Origin` and asserts no `Access-Control-Allow-Origin` echo; `grep -rn "enableCors\|origin:" src` and confirm the origin list comes from validated config.
- [ ] SEC-API-15 Security headers are set by Helmet or an equivalent. Verify: an e2e test that asserts each header the project's configuration sets is present on a normal response and on an error response.
- [ ] SEC-API-16 Where the browser attaches credentials automatically (cookie sessions or a refresh cookie), state-changing routes require CSRF protection. Verify: an e2e test that sends a state-changing request with the cookie and without the CSRF token and asserts rejection.
- [ ] SEC-API-17 Per-user responses are never cacheable in a shared cache. Verify: an e2e test that asserts the `Cache-Control` header on each authenticated `GET`.
- [ ] SEC-API-18 A caller-supplied correlation id is validated and length-limited or replaced, and is never used for authorization. Verify: an e2e test that sends an oversized and a malformed id and asserts the logged and returned `requestId` is the server's own; `grep -rn "request-id\|requestId" src/common` and trace that no guard reads it.

## API9:2023 Improper Inventory Management

Owned by `nestjs-standards` 05 4.3 (OpenAPI generated from DTOs, served in non-production, exported in CI). The `api-contract` skill owns the publishing workflow.

- [ ] SEC-API-19 The exported OpenAPI matches the routes the app registers, the interactive docs are not served in production, and no debug or test-only route is registered in production. Verify: the CI step that regenerates the OpenAPI document fails on a diff; an e2e test that boots with the production environment and asserts the docs path and any debug route return 404.

## API10:2023 Unsafe Consumption of APIs

Owned by `nestjs-standards` 12 (External integrations). The 2023 edition notes that developers tend to trust third-party data more than user input.

- [ ] SEC-API-20 Every provider response is parsed with a Zod schema before use, and every webhook verifies its signature against the raw body before parsing, applies replay protection where the provider supports it, and handles redelivery idempotently. Verify: unit tests that feed a malformed provider payload and assert a handled error; e2e tests that post a webhook with a bad signature (expect rejection), a valid one twice (expect one effect), and one with a stale timestamp where supported (expect rejection).
- [ ] SEC-API-21 Outbound calls have bounded retries with backoff only on operations safe to repeat, and an irreversible operation that timed out is reconciled by idempotency key or status lookup before any retry. Verify: a unit test with a provider stub that times out after succeeding, asserting the code looks the operation up instead of sending it again.

## Sources

- OWASP API Security Top 10, 2023 edition, read 2026-11-04 (the project page still names 2023 as current), https://owasp.org/API-Security/editions/2023/en/0x11-t10/ and https://owasp.org/www-project-api-security/
- OWASP Application Security Verification Standard 5.0.0 (published 30 May 2025), chapters V4 API and Web Service, V6 Authentication, V8 Authorization, V13 Configuration, read 2026-11-04, https://owasp.org/www-project-application-security-verification-standard/ and https://github.com/OWASP/ASVS/tree/v5.0.0_release/5.0/en
- NIST SP 800-63B-4, Digital Identity Guidelines: Authentication and Authenticator Management (published July 2025), section 3.2.2 Rate Limiting (Throttling), https://pages.nist.gov/800-63-4/sp800-63b.html and https://csrc.nist.gov/pubs/sp/800/63/b/4/final
- Kit standards: `nestjs-standards` 05, 07, 09, 12, linked in the scope paragraph.
