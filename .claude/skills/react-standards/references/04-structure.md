## 3. Structure

### Top level

Organize by feature, not by file type. `components/`, `hooks/`, and `utils/` as top-level
buckets for everything means every feature is scattered across four folders and nothing can
be deleted with confidence.

Everything below `src/` is the same in any React project. Only the routing folder differs
by framework, and that difference is isolated to one directory on purpose.

```
<repo>/
├── src/
│   ├── features/               one folder per business capability
│   │   ├── auth/
│   │   ├── orders/
│   │   └── <feature>/
│   │       ├── components/     connected components only this feature uses
│   │       ├── ui/             pure components: props in, callbacks out (4.1)
│   │       ├── hooks/          stateful logic for this feature
│   │       ├── api/            queries, mutations, query keys
│   │       ├── schemas/        Zod schemas for this feature's forms and responses
│   │       ├── lib/            pure functions: the feature's business rules
│   │       ├── types.ts        types this feature owns (not wire types)
│   │       └── index.ts        the feature's PUBLIC surface, and the only entry
│   │                           other features may import
│   │
│   ├── components/
│   │   ├── ui/                 design-system primitives: Button, Input, Dialog, Table
│   │   └── layout/             app shell, nav, page frames
│   │
│   ├── lib/
│   │   ├── api/
│   │   │   ├── client.ts       the one HTTP client: base URL, auth, error normalization
│   │   │   ├── refresh.ts      single-flight token refresh (section 6, race 8)
│   │   │   └── types.gen.ts    GENERATED from the API contract. Never edited by hand
│   │   ├── config/
│   │   │   └── env.ts          schema-parsed environment, validated at module load
│   │   ├── format/             money, dates, numbers. Explicit locale and zone
│   │   ├── observability/
│   │   │   └── global-errors.ts  window error + unhandledrejection handlers (4.6)
│   │   └── <util>.ts           pure helpers. No React, no I/O
│   │
│   ├── hooks/                  hooks used by more than one feature
│   ├── styles/                 tokens, global stylesheet, theme
│   └── test/                   setup files, MSW handlers, render helpers
│
├── e2e/                        Playwright specs for critical flows
├── fixtures/                   deliberately invalid code. Excluded from build, lint, tests
│   ├── boundaries/
│   │   ├── allowed/            legal imports. The rules must NOT reject these
│   │   └── forbidden/          illegal imports. The rules MUST reject these
│   └── lint/                   import paths that pin the no-restricted-imports behaviour
├── scripts/
│   ├── verify-boundaries.sh    (11.1)
│   ├── verify-lint-rules.sh    (11.2)
│   ├── verify-api-types.sh     (11.6)
│   └── verify-env.sh           (11.7)
├── public/                     static assets served as-is
├── .nvmrc                      the Node major, used by CI
├── .dependency-cruiser.cjs     the boundary rules (11.1)
└── .size-limit.json            the bundle budget (section 8)
```

**Next.js (App Router).** Routes live in `src/app/`, and nothing else does:

```
src/app/
├── layout.tsx                  root shell. No "use client" here (4.2)
├── page.tsx
├── error.tsx                   root error boundary
├── not-found.tsx
├── (marketing)/                route group: shares a layout, adds nothing to the URL
│   └── pricing/page.tsx
├── orders/
│   ├── page.tsx                composes from features/orders. No business logic
│   ├── loading.tsx             the route's loading state
│   ├── error.tsx               the route's error boundary, not just the root one
│   └── [orderId]/page.tsx
└── api/                        route handlers: server-only work, secret-holding calls
    └── <name>/route.ts
```

**Vite or any client-only SPA.** Routes live in `src/routes/`, and the router config is the
one place that knows the URL map:

```
src/
├── main.tsx                    mounts the app, installs providers, installs global
│                               error handlers (4.6)
├── router.tsx                  the route table, with lazy() per route for code splitting
└── routes/
    ├── root-layout.tsx
    ├── error-boundary.tsx
    ├── orders/
    │   ├── orders-page.tsx     composes from features/orders
    │   └── order-detail-page.tsx
    └── not-found.tsx
```

**React Native or Expo.** Identical `features/`, `lib/`, and `hooks/`. Replace
`components/ui/` with your native primitives and `src/app/` with the Expo Router tree or
your navigator config. Sections 4.3 through 4.9 and section 6 apply unchanged; section 7's
checklist maps onto the platform accessibility APIs, and section 8's bundle rules become
startup time and bridge traffic. In section 4.6, the global handlers become the platform's
global error handler and the unhandled-rejection tracking your error reporter installs.

**What goes in a feature versus a shared layer.** The test is one question: would this code
exist in a different product? A date formatter, a `Button`, an HTTP client: yes, so they are
shared. A function that decides whether an order can be cancelled: no, so it belongs to the
`orders` feature. When two features need the same domain logic, one of them owns it and
exports it, or it becomes its own feature. Never a copy in each, and never a quiet move into
`lib/`, which is how a shared folder turns into the place nobody can delete anything from.

**A feature's public surface** is small on purpose. Export the components, hooks, and types
other features actually use, and nothing else:

```ts
// src/features/orders/index.ts
export { OrderTable } from './components/order-table';
export { useOrders, useCreateOrder } from './api/orders.queries';
export { canCancelOrder } from './lib/order-rules';
export type { Order, OrderStatus } from './types';
// components/, schemas/, and the rest stay private to this feature.
```

**If your repo does not look like this**, do not stop to restructure it. Point new features
at the new shape, move a feature into it the next time you have real work in that feature,
and turn on the boundary check in 11.1 as a warning first so the existing violations are
visible without blocking every PR. A big-bang reorganization produces an enormous diff, no
behavior change, and a week of merge conflicts.

**The boundary rules** mirror the backend's module rules, and for the same reason:

- A feature's `index.ts` is its public API. Other features import from `features/x`, never
  from `features/x/components/...` or `features/x/api/...`.
- Features may depend on `components/`, `lib/`, and `hooks/`. Those may never import from
  `features/`. The test: would this code exist in a different product? If yes it is shared.
  If no it belongs to a feature.
- Two features needing the same thing means it belongs in a shared layer, or one of them
  owns it and exports it. Not a copy in each.
- Cycles between features are forbidden.

All four are enforced mechanically in 11.1, and the enforcement is itself tested.

**Routes compose, they do not implement.** A page file assembles feature components, sets
metadata, and handles layout. When a page file grows past assembly it is holding something
that belongs in a feature.

### Component files

**REQUIRED**
- One component per file. The filename matches the component.
- `kebab-case` for every file (`order-table.tsx`, `order-rules.ts`, `use-orders.ts`) and
  `PascalCase` for the component inside, consistently within the repo.
- Colocate what belongs to a component: its test, its styles, and its subcomponents that
  nothing else uses.
- Accessibility assertions live in `*.a11y.test.tsx`, so they can be run as their own suite
  without depending on how a test happens to be named (11.5).

```
features/orders/components/order-table/
├── order-table.tsx
├── order-table.test.tsx
├── order-table.a11y.test.tsx
├── order-row.tsx            used only here
└── index.ts
```

**DEFAULT**
- Barrel `index.ts` at the feature root, yes, because that is the public surface. Barrels
  everywhere else, no: they defeat tree shaking and turn one import into a graph of loaded
  modules.

---

