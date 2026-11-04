## 9. Security

REQUIRED for every project. The threat model starts from a user who can edit the bundle, the
requests, and the local storage.

- [ ] **Nothing is enforced on the client.** Permission checks, validation, and limits here
      are user experience. The server enforces, as its own standard requires. A hidden
      button is not a protected endpoint
- [ ] No secrets in client code. Anything in the bundle or in a publicly prefixed env var
      (`NEXT_PUBLIC_*`, `VITE_*`) is public. API keys that must stay secret are used from a
      server route
- [ ] `dangerouslySetInnerHTML` only with content you control, or with a sanitizer, and
      never with API, user, or CMS content by default. This is the main XSS vector in React
- [ ] URLs from data are validated before becoming an `href` or `src`. A `javascript:` URL
      in a user-supplied link is script execution
- [ ] `target="_blank"` carries `rel="noopener noreferrer"`
- [ ] Token storage is a deliberate, documented decision. An httpOnly cookie keeps the token
      out of JS reach; `localStorage` means any XSS is a full account takeover. If you choose
      storage the page can read, write down that you accepted it and why
- [ ] Token refresh is single-flight, the refresh endpoint is exempt from the 401
      interceptor, and only an authentication failure expires the session (section 6, race 8)
- [ ] With cookie auth, CSRF protection, because the browser attaches the cookie whether or
      not your code asked it to. This pairs with the backend's CSRF rule
- [ ] A Content Security Policy, and no `unsafe-inline` or `unsafe-eval` without a stated
      reason
- [ ] No sensitive data in `localStorage`, in the URL, or in analytics payloads. URLs end up
      in logs, referrers, and shared screenshots
- [ ] No internal exception text in the UI. The tracker gets the original, the user gets a
      generic message and the `requestId` (4.6)
- [ ] Third-party scripts are inventoried, justified, and loaded with integrity and the
      narrowest permissions available. Every one can read the page it runs on
- [ ] Dependency audit clean in CI, or exceptions documented with an expiry date
- [ ] Sign-out clears client caches as well as the session, so the next user on a shared
      machine does not see the previous one's data in the query cache

### Verifying these controls

A checklist records intent. This matrix records how you would know, and who answers for it.
Fill in the owner column with names, because a control owned by "the team" is owned by
nobody.

| Threat | Control | How it is verified | Owner |
|---|---|---|---|
| Stored or reflected XSS | No `dangerouslySetInnerHTML` with untrusted data; CSP without `unsafe-inline` | `react/no-danger` as an error; a report-only CSP period before enforcing; a test that renders a script payload from a mocked API and asserts it appears as text | Frontend |
| Account takeover via XSS | Token out of JS reach, or the exposure accepted in writing | Read the storage decision in the project file, then confirm in DevTools that the token is unreachable from `document.cookie` and from storage | Frontend |
| CSRF on cookie auth | `SameSite` plus an anti-CSRF token | E2E: send a state-changing request without the token and assert rejection | Backend enforces, frontend sends |
| Privilege escalation | Server enforces, client only hides | Call the endpoint behind a hidden control directly with a low-privilege session and assert 403 | Backend |
| Session that does not end | Sign-out clears the query cache and the session | E2E: sign out, navigate back, assert no cached data renders and a protected call returns 401 | Frontend |
| Silent logout under load | Single-flight refresh, replay errors propagated | The four refresh tests in section 6 | Frontend |
| Secret leakage | Nothing secret in the bundle | A CI step that greps the built output for key prefixes, internal hostnames, and token shapes | Frontend |
| Internal detail disclosure | Generic user message plus `requestId` | A test asserting an unexpected 500 renders the generic message, never the exception text | Frontend |
| `javascript:` or `data:` URL injection | URLs validated before becoming `href` or `src` | Unit tests on the validator covering `javascript:`, `data:`, and a protocol-relative URL | Frontend |
| Known vulnerable dependency | Audit in CI, with a remediation deadline | `npm audit --audit-level=high`, plus the policy in section 10 | Named owner |

Any row whose verification column would read "by inspection" is a row nobody checks twice.
Write the test, or record honestly that the control is unverified.

---

