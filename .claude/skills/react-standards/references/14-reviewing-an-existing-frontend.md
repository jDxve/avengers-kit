## 13. Reviewing an existing frontend

Fast pass in this order. Each question usually finds something.

1. **Server data in `useState`.** Grep for `useState` followed by `useEffect` with a fetch.
   This is the highest-yield check in the list, and it is usually where the race conditions,
   stale data, and manual refetching all come from.
2. **Effects with no cleanup.** Grep for `useEffect` containing `fetch`, `.then`,
   `setTimeout`, or `addEventListener` and check for a return function. Each one is a
   potential out-of-order write.
3. **The 401 path.** Find the interceptor. Is the refresh single-flight, is the refresh
   request itself exempt, and does a failed *replay* log the user out? Then prove it: block
   the API, load a page that fires several queries with an expired token, and watch the
   network tab for the number of refresh calls (section 6, race 8).
4. **`exhaustive-deps` disables.** Every one is a stale closure until proven otherwise.
5. **State that should be in the URL.** Open a filtered list, copy the URL, open it in a new
   tab. If the filters are gone, they are in the wrong place. Then press the back button.
6. **Keyboard pass.** Tab through the primary flow without touching the mouse. Can you reach
   everything, see where you are, and escape every overlay? This takes two minutes and finds
   more than a review of the markup.
7. **`div` with `onClick`.** Grep. Each one is a button that is invisible to keyboard and
   screen-reader users.
8. **`dangerouslySetInnerHTML`.** Grep, and trace each one's data back to its source.
9. **Unhandled rejections.** Open the console, use the app for five minutes, and look for
   them. Then check whether anything is listening for `unhandledrejection` at all; if not,
   every one of those was invisible in production.
10. **Client-only permission checks.** Find a hidden admin control, then call the endpoint
    behind it directly. If it works, the server is not enforcing.
11. **Cross-feature internal imports.** Grep for `features/*/` imports from other features.
    These are what make a refactor expensive later.
12. **The four states.** Throttle the network to slow 3G and block the API. Do you get
    spinners that never end, blank screens, or a usable error with a retry?
13. **Index keys on mutable lists.** Grep for `key={index}` or `key={i}`. Then reorder or
    delete a row and watch the inputs.
14. **Bundle composition.** Run the analyzer. Look for a date library with every locale, a
    whole icon set, a chart library on the login route, or two of anything.
15. **Secrets in the bundle.** Search the built output for the strings that should not be
    there: key prefixes, internal hostnames, tokens.
16. **The checks themselves.** Break something on purpose and confirm CI goes red. A gate
    nobody has watched fail is not a gate.
17. **`any`, `as`, `!`, `console.log`.** Grep and review each occurrence.

---

