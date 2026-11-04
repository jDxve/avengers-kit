## 5. Anti-patterns

| Anti-pattern | Why it hurts | Instead |
|---|---|---|
| Server data in `useState` + `useEffect` fetch | Two sources of truth, stale cache, races | The query layer owns it (4.3) |
| Filters or pagination in `useState` | Breaks refresh, sharing, and the back button | Put it in the URL (4.3) |
| `useEffect` that sets state from props | Extra render, stale window, race | Derive during render (4.3) |
| Fetch in an effect with no cancellation | Out-of-order responses overwrite fresh data | Abort or ignore stale (section 6) |
| A 401 handler that refreshes per request | Concurrent refreshes, rotated token, spurious logout | Single-flight refresh (section 6, race 8) |
| Logging the user out when a replayed request fails | A flaky network becomes a session loss | Only an auth failure expires the session (section 6) |
| No `unhandledrejection` handler | Async failures vanish with no boundary and no catch | Global handlers at boot (4.6) |
| `eslint-disable react-hooks/exhaustive-deps` | Almost always hiding a stale closure | Fix the dependency or restructure |
| Array index as `key` on a mutable list | React reuses the wrong node; inputs jump rows | A stable id from the data |
| State or data hooks inside `features/x/ui/` | The component can no longer be built or tested alone | Connected parent passes props (4.1) |
| `"use client"` at the top of a layout | Ships the whole page to the browser | Push the boundary to the leaves (4.2) |
| Importing `features/x/components/...` from feature y | Breaks encapsulation silently | Import from `features/x` (section 3) |
| `div` with `onClick` | Not focusable, not announced, no keyboard | A real `button` (section 7) |
| `dangerouslySetInnerHTML` with API or user content | Stored XSS | Render as text, or sanitize deliberately (section 9) |
| An exception's message rendered to the user | Leaks internals, sometimes payload data | Generic message plus `requestId` (4.6) |
| Tokens in `localStorage` without a stated reason | Any XSS becomes full account takeover | httpOnly cookie, or document the risk (section 9) |
| Client-side role check as the only gate | The bundle is editable; the data is not protected | Server enforces, client only hides (section 9) |
| Secrets in client env vars | Anything in the bundle is public | Server-side only (section 9) |
| `memo` and `useCallback` everywhere | Cost with no measured benefit, harder to read | Profile first (section 8) |
| One error boundary at the root | A broken widget blanks the whole app | Per route or section (4.6) |
| Only the loaded state implemented | Spinners forever, blank screens, no retry | Four states always (4.6) |
| Hand-written API response types | Drift silently until it is a production undefined | Generate from the contract (4.4) |
| A CI check nobody has watched fail | Passes forever, including when it is broken | Fixtures that must fail (section 11) |
| Barrel files at every level | Defeats tree shaking, inflates the bundle | Barrel at the feature root only (section 3) |
| Two styling systems | Both ship, every component is a coin flip | Pick one (4.8) |
| `getByTestId` as the default query | Tests the DOM, not the behavior | Role, label, text (4.9) |
| Stubbing query hooks in tests | Tests your mocks | Intercept the network (4.9) |
| `any`, or `as` to force a shape | Erases the point of TypeScript | `unknown` plus narrowing (4.7) |
| `console.log` left in committed code | Noise, and sometimes leaked data | Remove it, or use the logger |

---

