## 4. Rules

### 4.1 Components

**REQUIRED**
- A component renders UI from props and state. It does not contain business rules, data
  transformation beyond display formatting, or multi-step async orchestration. Those go in
  hooks and pure functions.
- Props are typed explicitly. No `any`, no untyped spread of unknown objects into the DOM.
- A list's `key` is a stable identifier from the data. Array index is acceptable only for a
  list that is append-only and never reordered, filtered, or deleted from. Index keys on a
  mutable list cause React to reuse the wrong DOM node, which shows up as input values
  jumping between rows.
- No side effects during render. Fetching, subscriptions, timers, storage writes, and
  analytics calls belong in effects, event handlers, or the query layer.
- Conditional rendering never hides a hook. Hooks run unconditionally, in the same order,
  every render.
- A component in `features/<name>/ui/` is pure: props in, callbacks out. No query hooks, state
  hooks, HTTP, storage, or navigation, so it can be generated from a mockup and tested with no
  providers. Purely visual state needs a disable comment with a reason. A connected component in
  `components/` reads state and passes plain values down. Enforced in 11.1. The folder is
  optional, and always used for UI generated outside the codebase.

**DEFAULT**
- Keep a component under roughly 150 lines, and treat anything past that as a review
  trigger rather than a violation. The usual cause is several components in one file or
  logic that wants to be a hook.
- Prefer composition over configuration. A component with twelve boolean props that switch
  layout is three components.
- Prop drilling two levels is fine. Four levels means composition (pass the element) or
  context.

### 4.2 React Server Components and the client boundary

**Applies only if your framework has server components** (Next.js App Router, React Router
in framework mode, and similar). Skip this subsection entirely for a client-only SPA or
React Native; nothing else in the document depends on it.

**REQUIRED**
- Server by default. Add `"use client"` only where the component needs state, effects, event
  handlers, or browser APIs.
- `"use client"` is a boundary, not a file header. Everything imported by a client component
  becomes client code, so put the directive as far down the tree as possible. One at the top
  of a layout ships the whole page to the browser.
- Never import server-only code (database clients, secrets, server SDKs) into a module that
  a client component can reach. Mark those modules `server-only` so the mistake fails the
  build instead of leaking into the bundle. This is one more reason `npm run build` is in
  the CI gate and `tsc --noEmit` alone is not: the leak is a bundler-graph error, and the
  type checker is happy with it.
- Fetch on the server where it fits. For data a page needs on first paint, with
  authorization available server-side, a server component that reads it directly beats a
  client component fetching on mount: no loading state, no client bundle cost. It is not a
  blanket win. Prefer the client when the data is driven by interaction (search as you type,
  a filter the user changes), when it should be cached and shared across views by the query
  layer, or when moving it to the server creates a sequential waterfall of server fetches
  that a parallel client fetch would avoid. Decide per view, and know which of the two
  mistakes you are avoiding.
- Know your framework's caching semantics and state them in the repo. Request-level caching,
  route caching, and revalidation differ by framework and version, and a wrong assumption
  here shows up as users seeing stale or other people's data. Use the explicit cache option
  on every fetch rather than relying on a default.

### 4.3 State

**REQUIRED.** Classify state before storing it. Nearly every state-management problem is
state in the wrong category.

| Kind of state | Where it lives | Examples |
|---|---|---|
| Server state | Query layer cache | Lists, records, anything the API owns |
| URL state | The URL | Filters, sort, page, tab, selected id, search text |
| Form state | Form library | Field values, touched, errors, submitting |
| Ephemeral UI state | `useState` in the component | Dropdown open, hover, local toggle |
| Global client state | Context or a small store | Theme, session, feature flags, toasts |

- **Never copy server data into `useState`.** `const [rows, setRows] = useState([]);` followed
  by a fetch is the most common architectural mistake in React codebases. It gives you two
  sources of truth, a stale cache, manual refetching, and the race conditions in section 6.
  The query layer owns the data; components read it.
- **Anything that should survive a refresh, a shared link, or the back button goes in the
  URL.** Filters, pagination, the open tab, the selected row. Storing these in `useState`
  silently breaks sharing and back-navigation, and users notice.
- **Derive instead of storing.** If a value can be computed from props, server state, or
  other state, compute it during render. A second `useState` kept in sync with the first by
  an effect is a bug waiting for a race.
- `useEffect` is for synchronizing with something outside React: a subscription, a browser
  API, a non-React widget. It is not for computing values, not for reacting to prop changes
  in order to set state, and not for fetching when the query layer can do it.

**DEFAULT**
- Reach for a store only when global client state has real transitions. Context is enough
  for a value that rarely changes, such as theme or session.
- Split context by update frequency. One context holding session, theme, and toasts
  re-renders every consumer whenever a toast appears.

### 4.4 Data fetching and mutations

**REQUIRED**
- All network access goes through one typed client in `lib/api/`. No bare `fetch` scattered
  through components, because retries, auth headers, error normalization, base URLs, and
  token refresh then exist in fifteen slightly different versions, and the refresh race in
  section 6 becomes unfixable.
- Query keys are structured and derived from parameters, so the cache invalidates correctly:
  `['orders', { customerId, status, page }]`, never a hand-built string.
- Mutations invalidate the queries they affect, or write the result into the cache. Never
  trigger a manual refetch from a component, and never reload the page.
- **Wire types are generated from the API contract** (section 2). Hand-written code on top of
  generated types is fine and often right: an adapter that maps a wire shape to a view model,
  or a domain type that exists because the UI needs a concept the API does not have. The rule
  is that the generated type is the source of truth at the boundary, and the adapter is
  visibly an adapter. The generated file is checked for staleness in CI (11.6).
- Validate at the boundary when the response shape matters: parse with the schema before
  using the data. An API that changes shape should fail loudly in one place, not produce
  undefined three components deep.
- Read the error contract rather than the status code alone. The backend standard requires a
  stable `code` and a `requestId`. Branch on `code`, and surface the `requestId` in the error
  UI so a user report maps to a server log line.

**DEFAULT**
- Set sensible `staleTime` per query type instead of accepting the default everywhere.
  Reference data that changes monthly and a dashboard that changes per minute should not
  share a policy.
- Optimistic updates where the mutation almost always succeeds and the latency is visible.
  Always with a rollback path, and section 6 has the shape.

### 4.5 Forms

**REQUIRED**
- A form library plus a schema. Hand-rolled `useState` per field loses validation, touched
  state, error association, and submit handling, and it gets rebuilt worse each time.
- The schema is the single source of truth for validation, and the field types derive from
  it (`z.infer`), so the form cannot drift from what it validates. The backend's request
  schemas are `.strict()`, so a form submits only the fields the API defines; an unknown key
  returns 400.
- **Client validation is UX, never enforcement.** The server validates independently, as the
  backend standard requires. Mirror the rules for fast feedback and assume nothing about the
  client's checks holding.
- Submission is guarded against double-fire: disable the control while in flight. For
  anything irreversible or financial, also send an idempotency key, which pairs with the
  backend's idempotency rule. A double-clicked submit should not create two orders.
- Server-side field errors are mapped back onto the fields, not dropped into a generic
  toast. The user needs to know which field, not that something was wrong.
- Every input has a programmatically associated label, and every error is associated with
  its input via `aria-describedby` and announced. Section 7 covers this.

### 4.6 Errors

**REQUIRED**

- **Classify the failure before deciding where it is handled.** Most error-handling mess
  comes from treating four different things as one.

  | Class | Example | Handled where | The user sees |
  |---|---|---|---|
  | Expected domain failure | 403, 404, validation rejected, conflict | At the call site, or the query's error state | A specific message in place, with a next step |
  | Transient infrastructure failure | Timeout, 503, dropped connection | Query layer retry, then its error state | A retry affordance, session intact |
  | Programmer error during render | Reading a property of undefined, a broken invariant | The nearest error boundary | That section's fallback, and a way to recover |
  | Escaped async failure | A rejected promise in a click handler | Global handlers, tracker only | Usually nothing, which is the problem |

  Only the third class is an error boundary's job. The first two are ordinary control flow
  and must never reach one: a boundary firing on a 404 means somebody threw where they
  should have returned. The fourth is not a UI state at all, it is a bug with no symptom,
  which is why the global handlers below exist to make it visible rather than to handle it.
  **Global handlers supplement explicit handling, they never substitute for it.** A rejected
  promise that only the tracker knows about is still a broken feature.
- Error boundaries per route or per major section, not one at the root. A failure in a chart
  should not blank the page.
- **Know precisely what an error boundary catches,** because the common one-line version of
  this rule is wrong and leads people to skip the handling they actually need.

  | Where the throw happens | Reaches a boundary? |
  |---|---|
  | During render | Yes |
  | In an effect's setup or cleanup function, synchronously | Yes |
  | In a `useMemo`, a lazy initializer, or a reducer during dispatch | Yes |
  | In an event handler | No |
  | After an `await`, or in a `.then` / `.catch` | No |
  | In a `setTimeout`, `setInterval`, or subscription callback | No |
  | In a rejected promise nobody caught | No |

  The dividing line is whether React is still on the call stack. It is for render and for
  the synchronous body of an effect, because React invokes both. It is not for anything that
  runs later, which is why "boundaries do not catch effects" is a misleading shorthand: the
  effect body is caught, the async continuation inside it is not.
- **Install global handlers at boot.** The four "No" rows above reach no boundary and, by
  definition, no `catch`. Without these, a rejected promise in a click handler is a
  completely silent production failure.

  ```ts
  // src/lib/observability/global-errors.ts
  export function installGlobalErrorHandlers(report: (e: unknown, kind: string) => void) {
    window.addEventListener('error', (event) => {
      report(event.error ?? event.message, 'uncaught');
    });
    window.addEventListener('unhandledrejection', (event) => {
      report(event.reason, 'unhandled-rejection');
    });
  }
  ```

  Call it once, where the app mounts, before anything else runs. On React 19 and later,
  `createRoot(el, { onUncaughtError, onCaughtError, onRecoverableError })` is the right place
  to hook the tracker for the render-phase errors, and the two listeners above still cover
  everything React never sees.
- Async failures in data flow surface through the query layer's error state, which is the
  normal path and needs no boundary at all.
- Error UI says what failed and what to do next, and offers a retry where retrying could
  work. "Something went wrong" with no action is a dead end.
- Never swallow an error silently. The same rule as the backend: catching is for translating
  a failure you expected, never for hiding one you did not.
- Expected failures are not crashes. A 403 renders a permission message, a 404 renders a
  not-found view, a validation error renders on the field. Only genuinely unexpected
  failures reach the boundary.
- Client errors go to the same error tracker as the server, with the release version and the
  `requestId` attached when there is one.
- Never put an exception's own message in front of a user. It can carry a stack frame, an
  internal hostname, or a fragment of a payload. Keep the original for the tracker, render a
  generic message plus the `requestId`, and allow only messages from your own validation
  layer through to the UI. This is the same rule as the backend's, from the other side.

### 4.7 Types

**REQUIRED**
- `strict: true`. No `any`: use `unknown` plus narrowing. No non-null assertion (`!`) to
  silence a real nullable, and no `as` to force an incompatible shape into place.
- Derive types rather than duplicating them: `z.infer` from schemas, generated types from
  the API contract, `ReturnType` from hooks. A type written twice diverges.
- Make illegal states unrepresentable where it is cheap. A discriminated union on status
  beats three independent booleans that allow `loading && error && data`.
- `@ts-expect-error` over `@ts-ignore` when one is unavoidable, with a comment saying why,
  because it fails when the underlying problem is fixed.

### 4.8 Styling

**REQUIRED**
- One styling approach per repo. Two means every component is a coin flip and the bundle
  carries both.
- Design tokens, not literals. Colors, spacing, radii, and typography come from the system;
  a hex code in a component is a bug in the system or an unapproved exception.
- Responsive by default, mobile first. A fixed pixel width that overflows a phone is not
  finished work.
- Respect `prefers-reduced-motion` for anything that animates, and never convey information
  by color alone.

**DEFAULT**
- Compose primitives from `components/ui/` rather than styling raw elements in features.
  When a feature needs a new variant, add it to the primitive.

### 4.9 Testing

**REQUIRED**
- Query by role, label, or text, the way a user finds things. `getByTestId` is a last resort
  for something genuinely unidentifiable, and a test suite full of test ids is testing the
  DOM rather than the behavior.
- Test behavior, not implementation. No asserting on state variables, no shallow rendering,
  no reaching into instances. A test that breaks when you rename a prop while the UI works
  identically is testing the wrong thing.
- Mock at the network boundary (MSW), not by stubbing the query hooks. Stubbing the hooks
  tests your mocks; intercepting the network tests your code.
- Unit tests are required for: money and date formatting, permission and visibility rules,
  any reducer or state machine, and every pure function in a feature's `lib/`.
- Critical user flows have an end-to-end test: sign in, the primary task, and anything
  involving money or irreversible action.
- The four states are tested, not just the happy path: loading, error, empty, loaded.
- The async races in section 6 that a feature introduces are tested. Section 6 ends with the
  specific list.

**DEFAULT**
- Tests next to the code. End-to-end specs in `e2e/`.
- An accessibility assertion (`jest-axe` or the Playwright equivalent) on each major screen,
  in a `*.a11y.test.tsx` file. It catches missing labels and contrast failures that manual
  review misses.

---

