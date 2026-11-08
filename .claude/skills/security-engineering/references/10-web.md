# Web security (React and Next.js)

Scope: verifiable checks for a React or Next.js frontend. The rules are owned by `react-standards`: the checklist and verification matrix in [10-security.md](../../react-standards/references/10-security.md), the server and client boundary in [05-rules.md](../../react-standards/references/05-rules.md) 4.2, and errors in 4.6. Next.js App Router detail (caching, route handlers, middleware, cookie auth to NestJS) belongs to `react-standards/references/17-nextjs-app-router.md` once that reference exists; until then, the Next.js items below are the kit's floor. This file adds the verify step to each rule and the items the standard does not yet hold: CSP rollout, security headers, cookie attributes, open redirects, and server actions as public endpoints.

The backend half of each control (CSRF enforcement, CORS, headers on API responses) is in `20-api.md`. The OWASP Top 10:2025 categories most of these items serve are A01 Broken Access Control, A02 Security Misconfiguration, A05 Injection, and A07 Authentication Failures.

## Script injection

- [ ] SEC-WEB-01 `dangerouslySetInnerHTML` is never given API, user, or CMS content without a sanitizer (`react-standards` 10). Verify: `react/no-danger` is an error in `eslint.config.js` and `npm run lint` passes; `grep -rn "dangerouslySetInnerHTML" src app` and trace each hit to a constant or a sanitizer call; a test that renders a `<script>` payload from a mocked API response and asserts it appears as text.
- [ ] SEC-WEB-02 A URL from data is validated before it becomes an `href`, `src`, or `window.location` value (`react-standards` 10). The OWASP XSS Prevention Cheat Sheet notes that framework protection against `javascript:` URLs does not replace application-specific URL validation. Verify: unit tests of the validator with `javascript:alert(1)`, `data:text/html,x`, a protocol-relative `//evil.example`, and an allowed URL; `grep -rnE "href=\{|src=\{" src app` and trace each dynamic value to the validator or a constant.
- [ ] SEC-WEB-03 Every `target="_blank"` link carries `rel="noopener noreferrer"` (`react-standards` 10). Verify: `grep -rn 'target="_blank"' src app` and confirm each hit has the `rel` attribute on the same element.

## Content Security Policy and headers

- [ ] SEC-WEB-04 A Content Security Policy ships in report-only mode first, then enforced, with no `unsafe-inline` or `unsafe-eval` unless the reason is written down (`react-standards` 10). MDN and the OWASP CSP Cheat Sheet both describe `Content-Security-Policy-Report-Only` for testing a policy before enforcing it, and nonce- or hash-based strict policies as the alternative to allowlisting hosts. Verify: build and start the app locally, then `curl -sI http://localhost:<port>/ | grep -i '^content-security-policy'`; the enforced header contains no `unsafe-inline` or `unsafe-eval`, or the project's security notes record why.
- [ ] SEC-WEB-05 The response headers the project chose (framing control through CSP `frame-ancestors` or `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, and HSTS where TLS terminates) are set on every page response. Verify: an e2e test, or the local `curl -sI` above, asserting each chosen header on a page, a route handler, and an error page.

## Cookies, sessions, and tokens

- [ ] SEC-WEB-06 Session and refresh cookies set `HttpOnly`, `Secure`, and an explicit `SameSite`, and a cookie scoped to one host uses the `__Host-` prefix, which MDN defines as requiring `Secure`, no `Domain` attribute, and `Path=/`. Verify: an e2e test that signs in and asserts the `Set-Cookie` attributes of each session cookie.
- [ ] SEC-WEB-07 Tokens are out of JavaScript reach, or the project file records that it accepted the exposure and why (`react-standards` 10). Verify: a Playwright test that signs in and asserts `document.cookie` does not contain the session cookie and `localStorage` and `sessionStorage` hold no token-shaped value.
- [ ] SEC-WEB-08 With cookie auth, every state-changing request carries an anti-CSRF token or uses a pattern the OWASP CSRF Prevention Cheat Sheet lists (synchronizer token, signed double-submit cookie), and `SameSite` is treated as defense in depth, not the whole control. Verify: the backend e2e test in `SEC-API-16`, plus a frontend test that the API client attaches the token to every non-`GET` request.
- [ ] SEC-WEB-09 Sign-out clears the query cache and any client state as well as the session (`react-standards` 10). Verify: an e2e test that signs out, navigates back, and asserts no cached data renders and a protected call returns 401.
- [ ] SEC-WEB-10 After sign-in or any privilege change the session id is replaced, as the OWASP Session Management Cheat Sheet requires. Verify: an e2e test that records the session cookie value before and after sign-in and asserts they differ. If the backend issues the session, the test lives with the backend.

## Redirects

- [ ] SEC-WEB-11 A redirect target taken from the request (`returnTo`, `next`, `redirect`) is parsed and checked against an allowlist of destinations, or limited to same-origin relative paths, as the OWASP Unvalidated Redirects and Forwards Cheat Sheet advises. Verify: unit tests of the redirect validator with `https://evil.example`, `//evil.example`, `/\evil.example`, `javascript:alert(1)`, and an allowed path.

## Next.js server code

- [ ] SEC-WEB-12 Every server action validates its input with Zod and checks authentication and authorization inside the action. The Next.js data security guide (docs for v16) states that an exported server action is reachable by a direct POST request and that a page-level authentication check does not extend to the server actions defined in it. Verify: `grep -rln "'use server'" app src` and trace each exported action to a schema parse and an auth check before any read or write; an e2e test that posts to one action with no session and asserts it does nothing.
- [ ] SEC-WEB-13 Route handlers are public endpoints with the same rules as any API route: Zod input, authorization inside, and no secret in the response. Verify: `grep -rlnE "export async function (GET|POST|PUT|PATCH|DELETE)" app` and trace each to a schema parse and an auth check; an e2e test per handler with no session.
- [ ] SEC-WEB-14 Middleware (named `proxy.ts` in the Next.js v16 guide) handles redirects and headers only; it is never the only authorization check, because the API and each server entry point enforce. Verify: for each matcher in the middleware file, trace the routes it covers and confirm each page, route handler, and action it protects also checks authorization itself.
- [ ] SEC-WEB-15 Modules that hold a secret or a database client import `server-only`, so a client import fails the build (`react-standards` 05 4.2). Verify: `grep -rLn "server-only" <server module paths>` returns nothing for modules that read secrets; `npm run build` passes.
- [ ] SEC-WEB-16 Server action return values and server component props carry only what the UI needs, never raw records. The Next.js guide notes that action return values are serialized to the client. Verify: trace each action's return and each server-to-client prop to a mapped type; a test asserting the exact keys of one action's result.

## Secrets, data, and third parties

- [ ] SEC-WEB-17 No secret is in the bundle or a public env prefix (`NEXT_PUBLIC_*`, `VITE_*`) (`react-standards` 10). Verify: the CI step from the `react-standards` 10 matrix that greps the built output for key prefixes, internal hostnames, and token shapes; `grep -rnE "NEXT_PUBLIC_|VITE_" .env.example` and confirm none names a secret.
- [ ] SEC-WEB-18 No sensitive data in `localStorage`, the URL, or analytics payloads (`react-standards` 10). Verify: `grep -rn "localStorage\.\(setItem\|getItem\)" src app` and trace each key; read the analytics event definitions and confirm no field holds personal or account data.
- [ ] SEC-WEB-19 Third-party scripts are inventoried and loaded with integrity where the host allows it (`react-standards` 10). Verify: `grep -rnE "<script|next/script" src app public` and match each external source to the inventory; each static external script has an `integrity` attribute or a written reason.
- [ ] SEC-WEB-20 The UI never shows exception text; it shows a generic message and the `requestId` (`react-standards` 4.6). Verify: the test from the `react-standards` 10 matrix that an unexpected 500 renders the generic message and never the exception text.

## Sources

- OWASP Top 10:2025, read 2026-11-04, https://owasp.org/Top10/2025/
- OWASP Application Security Verification Standard 5.0.0 (published 30 May 2025), chapters V3 Web Frontend Security and V7 Session Management, https://owasp.org/www-project-application-security-verification-standard/
- OWASP Content Security Policy Cheat Sheet, living document, read 2026-11-04, https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html
- OWASP Cross-Site Request Forgery Prevention Cheat Sheet, living document, read 2026-11-04, https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html
- OWASP Session Management Cheat Sheet, living document, read 2026-11-04, https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
- OWASP Cross Site Scripting Prevention Cheat Sheet, living document, read 2026-11-04, https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
- OWASP Unvalidated Redirects and Forwards Cheat Sheet, living document, read 2026-11-04, https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html
- MDN, `Set-Cookie` header reference, living document, read 2026-11-04, https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie
- MDN, Content Security Policy guide, living document, read 2026-11-04, https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP
- Next.js documentation, "How to think about data security in Next.js", App Router docs for v16 (the version the page labels Latest), read 2026-11-04, https://nextjs.org/docs/app/guides/data-security
- Kit standards: `react-standards` 10 and 05, linked in the scope paragraph.
