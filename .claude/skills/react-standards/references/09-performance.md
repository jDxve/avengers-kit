## 8. Performance

**REQUIRED**
- A measurement before an optimization. React DevTools Profiler, Lighthouse, or a trace.
  "This felt slow so I added `memo`" is not a reason, and it makes the code harder to read
  for nothing.
- Route-level code splitting. A user on the sign-in page should not download the
  reporting module.
- Heavy dependencies loaded dynamically: charts, rich text editors, PDF viewers, date
  pickers with locale data, anything over a few tens of kilobytes that is not on the first
  screen.
- Images have explicit dimensions or an aspect ratio so layout does not shift, are served
  in a modern format, and are sized for their container rather than scaled down from
  originals.
- A bundle budget, checked in CI, failing the build when it is exceeded. Without a gate,
  bundles only grow.
- Lists beyond a few hundred visible rows are virtualized. Pagination counts as a solution.
- No render-blocking work in a `useLayoutEffect` beyond measurement, and no synchronous
  parsing of large payloads on the main thread.

**DEFAULT**
- Fix the cause before reaching for memoization. Most slow React is one of: state too high
  in the tree causing a whole page to re-render, a context holding too many unrelated values,
  a new object or function identity passed to a memoized child every render, an unkeyed or
  index-keyed list, or rendering ten thousand rows.
- `memo`, `useMemo`, and `useCallback` are for a measured problem, or for a stable identity
  a memoized child or an effect dependency genuinely requires.
- Core Web Vitals tracked from real users, not only from the lab. A good Lighthouse score on
  a developer laptop is not evidence.

---

