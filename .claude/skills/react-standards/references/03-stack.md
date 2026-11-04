## 2. Stack

### Required for every project

Each row states an **outcome** that is required and names the **default** that delivers it.
Swapping the default for something that delivers the same outcome needs a line in the repo
saying what you chose and why. Swapping it for something that does not is a departure from
the standard, not a preference.

The Schema validation row is the exception: Zod has no substitute.

| Concern | Required outcome | Default |
|---|---|---|
| Framework | React with TypeScript, `strict: true` | n/a, this one is the floor |
| Build or meta-framework | One build toolchain, pinned | Next.js, or Vite for a pure SPA |
| Server state | Something owns the cache, deduplicates in-flight requests, survives unmount, and handles section 6 | TanStack Query. RTK Query, SWR, or the framework's loader and action layer qualify if they cover 4.4 |
| Forms | A form library that owns values, touched, errors, and submit, driven by a schema | React Hook Form, or the framework's form action |
| Schema validation | Zod, mandatory. Types are inferred from the schema, not restated | Zod. No substitute qualifies |
| Styling | One approach, project-wide | Tailwind, CSS Modules, or one CSS-in-JS library |
| Routing | One router, the framework's | n/a, never two |
| Testing | A component test runner with React Testing Library, plus a real-browser runner for critical flows | Vitest plus Playwright |
| Linting | ESLint carrying the correctness rules in 11.3 | `react-hooks`, `jsx-a11y`, `@typescript-eslint` |
| Wire types | Generated from the API contract, never hand-written | `openapi-typescript`. GraphQL codegen or tRPC inference qualify (section 15) |

### Adoption profiles

Pick one at kickoff and record it in the repo. A profile decides which **checks** you run,
never which **rules** apply. Section 7's keyboard, label, and focus items and the whole of
section 9 are required at every profile, because the cost of skipping those is paid by users
rather than by the team, and because moving up a profile is a day of work while recovering
from a security or accessibility incident is not something you get to schedule.

| | Baseline | Standard | High assurance |
|---|---|---|---|
| **Use when** | Prototype, internal tool, one or two engineers, short expected life | Most products. The default | Money, health, regulated data, or releases that cannot be rolled back within the hour |
| Structure | `features/` with a public `index.ts` | + boundary rules in CI (11.1) | + fixtures that prove the rules fire (11.1, 11.2) |
| Types | `strict: true`, generated wire types | + staleness check in CI (11.6) | + runtime schema parse at every boundary (4.4) |
| Tests | Pure functions in each `lib/` | + the four states, and section 6's race table | + E2E on every money or irreversible flow |
| Accessibility | Section 7 checklist, one keyboard run | + `jsx-a11y` as errors, axe on key screens | + screen reader pass, Lighthouse budget in CI |
| Performance | Route-level splitting | + bundle budget failing CI | + real-user Core Web Vitals, budget per route |
| Operations | Env validated at boot | + error tracker, source maps, rollback path | + env failure proven in CI (11.7), flags on risky paths |
| CI gate | `typecheck`, `lint`, `test`, `build` | + `boundaries`, `api:check`, `audit`, `size`, `test:e2e` | The full gate in 11.9 |

Two rules about moving between them. Write the profile down, because "we are basically
standard" is how a team ends up at baseline with standard's paperwork. And when you move up,
turn each new check on as a warning first so the existing violations are visible before they
block a PR.

### Platform applicability

Sections 1, 3, 4.1, 4.3 through 4.5, 4.7, 4.9, 6, 12, and 13 are universal: they hold for any
React application on any platform. The rest depends on where the code runs, and a rule
applied to the wrong platform is how a standard earns a reputation for being written by
people who have not shipped on it.

| Section | Client-only web (Vite) | Next.js or another RSC framework | React Native or Expo |
|---|---|---|---|
| 4.2 server components, `"use client"` | Does not apply | Applies | Does not apply |
| 4.6 error boundaries and the taxonomy | Applies | Applies, plus server-render errors | Applies |
| 4.6 global handlers | `window` `error` and `unhandledrejection` | Same, plus the server-side reporter | The platform's global handler, plus your reporter's unhandled-rejection hook |
| 4.8 tokens, reduced motion | Applies | Applies | Applies, with native primitives and the platform reduce-motion setting |
| 7 accessibility | As written (DOM and ARIA) | As written | Maps to the platform accessibility APIs. Focus order, labels, contrast, and announcements all still apply; "zoom to 400%" becomes dynamic type support |
| 8 bundle budget and splitting | Applies | Applies, per route | Becomes startup time, JS bundle size, and bridge traffic |
| 9 CSP, CSRF, `rel="noopener"`, `dangerouslySetInnerHTML` | Applies | Applies | Does not apply. The equivalent is deep-link validation and WebView hardening |
| 9 token storage, server enforcement, no secrets, no internal detail in the UI | Applies | Applies | Applies, with Keychain or Keystore in place of cookies |
| 11.1, 11.2 boundaries and import rules | Applies | Applies | Applies unchanged |
| 11.5 axe and Lighthouse | Applies | Applies | Replace with the platform accessibility scanner and a manual screen-reader pass |

The pattern: architecture and async correctness are universal, DOM-specific controls are not,
and nothing in section 9 that is about trust ever becomes optional. It is only implemented
differently.

### Exceptions

Some rules have honest edges. These four come up on nearly every project, so they are
pre-approved rather than argued case by case:

- **One HTTP client (4.4)** does not cover a vendor SDK that owns its own transport (Stripe,
  Firebase, an analytics SDK) or a streaming connection (SSE, a WebSocket, a live
  subscription). Wrap each in a module under `lib/` so one place still knows about it, and
  route its errors through the same normalizer so the UI sees one error shape.
- **Generated wire types (4.4)** need a contract to generate from. Against an API with no
  schema, hand-write the type once in `lib/api/`, parse every response against a Zod schema at
  the boundary so drift surfaces as a loud error rather than an undefined three components
  deep, and put "get a contract published" on someone's list.
- **A form library (4.5)** is not required for a single uncontrolled field with no
  validation, such as a search box that submits on Enter. The moment it has validation, a
  touched state, or a server error to map back onto a field, it is a form.
- **Error boundaries per route (4.6)** collapse to one for an app with one route.

Anything beyond these is an exception you write down: which rule, why, who owns it, and when
it gets revisited. Keep it in the repo next to the project decisions file, never as an edit
to the rule it departs from. An exception with an owner and a date is a decision. One without
is drift that somebody happened to notice.

**On the wire-types row:** what is not acceptable is a hand-maintained
`interface OrderResponse`, whatever the contract format. It drifts in silence and the first
symptom is an undefined in production.

### Add when a requirement justifies it

| Library | Add it when |
|---|---|
| Client state store (Zustand, Redux) | You have genuinely global client state with non-trivial transitions. Server state and URL state do not count |
| Component library (Radix, React Aria, MUI) | You need accessible primitives such as dialogs, comboboxes, and menus. Building these yourself correctly is a larger job than it looks |
| State machine (XState) | A flow has many states and illegal transitions that keep shipping as bugs |
| Virtualization (TanStack Virtual) | A list renders more than a few hundred rows at once |
| i18n (next-intl, react-i18next) | More than one locale is actually planned, not hypothetical |
| Animation (Framer Motion) | Motion carries meaning. A CSS transition covers most cases |
| Charts (Recharts, visx, ECharts) | You need charts. Load them dynamically; they are large |

A React app with a query library, a form library, and no state store is a normal production
architecture. Do not add libraries to satisfy this document.

**On the server-state row:** the failure to avoid is running a framework's loader layer and a
query library over the same resource. Two caches of one resource is worse than either alone,
because now invalidation has to be right in both and nothing tells you when it is not.

### Pin the toolchain

**REQUIRED.** The same commit builds and checks identically today and in six months, which
means the Node major, the package manager, and every dev dependency are pinned.

```
.nvmrc                 →  22
package.json           →  "engines": { "node": ">=22 <23" }
package-lock.json      →  committed, and CI uses `npm ci`, never `npm install`
```

Some dev tools have narrower peer ranges than their own install command implies, and
installing the newest version of everything can silently disable a check rather than fail it.
Section 11.1 documents one such case that is live today, with the guard that catches it.

---

