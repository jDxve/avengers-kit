## 15. Decisions this document deliberately does not make

This standard says how to build. It does not invent your numbers or your policies. Record
these per project, in the repo, and keep them current:

- **Platform:** browser support matrix, minimum screen width, and whether the app must work
  without JavaScript.
- **Auth.** This one gets its own table because the frontend cannot be correct without the
  answers, and half of them live on the backend. Fill it in before writing the HTTP client,
  not after the first mystery logout.

  | Question | Why the frontend needs it |
  |---|---|
  | Cookie or bearer token? | Decides whether you need CSRF protection or token storage, and they are different problems |
  | If a cookie: `SameSite`, `Secure`, `httpOnly`, and the CSRF scheme | `SameSite=Lax` does not cover cross-site POSTs; something has to |
  | If a token the page can read: where, and what XSS exposure you accepted | Section 9 requires this written down, not assumed |
  | Access token lifetime | Sets how often race 8 happens, which is how often it bites |
  | **Does the backend rotate refresh tokens?** | If yes, concurrent refresh is a correctness bug, not an efficiency one. This is the single answer that decides how strictly section 6's race 8 must be implemented |
  | Refresh token lifetime and absolute session cap | Determines whether "signed in" can be silently false |
  | What the server returns for an expired versus an invalid refresh | The client must distinguish these to avoid logging out on a network blip |
  | What happens to an in-flight form when the session expires | Either preserve the draft or tell the user, but decide |
  | What sign-out must clear besides the session | The query cache is the one teams forget (section 9) |
- **API contract:** the contract format (OpenAPI, GraphQL schema, tRPC router), where the
  pinned schema lives, and who owns regenerating the types.
- **Performance:** the bundle budget per entry point, the Core Web Vitals targets, and the
  network profile you consider the baseline user.
- **Data:** `staleTime` policy per data category, what may be cached offline, and what must
  never be persisted on the device.
- **Design system:** the token set, which primitives are owned here versus imported, and who
  approves a new variant.
- **Accessibility:** the conformance target (commonly WCAG 2.2 AA), which assistive
  technologies are tested, and how often.
- **i18n and formatting:** locales supported, the source of the user's timezone, and the
  money and date formatting rules, which must agree with the API's representation.
- **Observability:** which client errors page someone, what analytics is collected, and what
  is scrubbed before it leaves the browser.
- **Release:** flag strategy, rollout and rollback procedure, and how a user on a stale
  bundle is handled when the API moves.

If one does not apply, write down why. If one is unknown, mark it unresolved rather than
quietly picking a value, because an unresolved decision someone can see is safer than a
default nobody chose.

### Starting values

A blank table gets filled in with nothing. These are defensible opening positions for a
typical business application, meant to be argued with and edited on day one, not adopted
silently. None of them is a recommendation for your product, and every one of them should
carry a name and a date once you have changed it.

```md
<!-- docs/project-decisions.md -->
Profile:            standard                  (section 2)
Browsers:           last 2 versions, >0.5% usage, not dead
Min width:          360px
Works without JS:   no

Auth:               httpOnly cookie, SameSite=Lax, double-submit CSRF token
Access token:       15 min   Refresh: 30 days, rotating, absolute cap 90 days
On expiry mid-form: preserve the draft in memory, re-auth in a dialog, resubmit

Bundle budget:      180 KB gzipped on the first route, 90 KB per lazy route
Web Vitals:         LCP < 2.5s, INP < 200ms, CLS < 0.1 at p75 on real users
Baseline network:   4G, mid-range Android

staleTime:          reference data 1h · lists 30s · dashboards 0 · user profile 5m
Never persisted:    anything from the auth or billing features

Accessibility:      WCAG 2.2 AA · tested with VoiceOver + Safari and NVDA + Firefox
                    full pass each release, axe on every PR

Locales:            en only today, strings externalised anyway
Timezone source:    the user's profile setting, never the browser
Money:              minor units as integers over the wire, formatted with Intl at the edge

Errors that page:   auth failures above 1% of sessions, checkout errors at any rate
Scrubbed:           email, full name, any field under billing/, all URL query values
Release:            flags on anything touching money; rollback by redeploying the
                    previous build hash, exercised quarterly
```

Put this file on a recurring review. A decision that nobody has looked at in a year is a
default nobody chose, which is the thing this section exists to prevent.