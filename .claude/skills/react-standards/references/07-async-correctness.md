## 6. Async correctness

**This is the section most frontends get wrong.** It is the frontend's version of the
backend's concurrency problem, and it has the same shape: something happens between the
start of an operation and its completion, and naive code assumes nothing did.

**1. Out-of-order responses.** The classic. A user types `a`, then `ab`. Two requests go out.
The response for `a` arrives last and overwrites the results for `ab`. The UI now shows the
wrong data with no error anywhere, and it reproduces only on a slow network.

A query library solves this for you, which is most of why it is in the required stack. When
you must fetch in an effect, cancel or ignore:

```tsx
useEffect(() => {
  let ignore = false;
  fetchResults(query).then((data) => {
    if (!ignore) setResults(data);   // a stale response resolves, and does nothing
  });
  return () => { ignore = true; };
}, [query]);
```

`AbortController` is better where the request supports it, because it stops the work as well
as the update.

**2. Updates after unmount.** The component is gone and the promise resolves. The same
cleanup fixes it. The rule is not that every async effect needs identical cleanup, it is
that **every async effect owes an answer to "what happens if this resolves late".** A fetch
whose result is written to state needs cancellation or an ignore flag. Fire-and-forget
analytics needs neither. Subscriptions and timers need teardown regardless. Say which case
you are in; the bug is not having thought about it.

**3. Stale closures.** A callback captured the state value from the render that created it.
Intervals, subscriptions, and debounced handlers are where this bites. The fix is the
functional updater (`setCount(c => c + 1)`), a ref for a value you need to read later, or
correct dependencies. It is never an `exhaustive-deps` disable.

**4. Double submission.** Users double-click, and connections drop mid-request so clients
retry. Disable the control while the mutation is in flight, and for anything irreversible
send an idempotency key so the server collapses the duplicate. This is the same invariant as
the backend's, enforced from both ends.

**5. Optimistic updates need a rollback.** Writing to the cache before the server confirms
means owning the failure path: snapshot the previous value, apply the optimistic change, and
restore the snapshot if the mutation rejects. An optimistic update without a rollback shows
the user a change that silently did not happen, which is worse than a spinner.

**6. StrictMode double-invokes effects in development.** That is a feature, not a glitch. If
your effect breaks when it runs twice, it is not idempotent, and it will break in production
for a different reason. Fix the effect.

**7. Race between route change and in-flight work.** A navigation mid-request leaves a
response landing on a screen that no longer exists, or worse, writing into the wrong screen's
state. Key queries by route parameters so the cache entry belongs to the route rather than
to the component instance.

**8. Concurrent token refresh.** This is the race with a security consequence, and it is the
one most commonly missing. A page mounts, fires six queries, the access token has just
expired, and all six come back 401. A naive interceptor starts six refreshes. With a backend
that rotates refresh tokens, the first rotation invalidates the token the other five are
holding, so five of them fail and the user is thrown to the sign-in screen in the middle of
a working session. The symptom is a random logout on page load that nobody can reproduce.

Single-flight the refresh: at most one refresh in the air, with every waiting request queued
behind the same promise.

```ts
// src/lib/api/refresh.ts
let inFlight: Promise<void> | null = null;

/** All concurrent callers share one refresh. The promise is cleared on settle,
 *  so the next 401 after this one starts a fresh attempt. */
export function refreshOnce(doRefresh: () => Promise<void>): Promise<void> {
  inFlight ??= doRefresh().finally(() => { inFlight = null; });
  return inFlight;
}
```

Three rules go with it, and each is a separate bug if you miss it:

- **The refresh request itself never goes through the 401 interceptor.** It is exempt, or a
  failed refresh triggers a refresh and you have an infinite loop.
- **Replay each queued request exactly once.** A second 401 after a successful refresh is a
  real authorization failure, not a reason to refresh again.
- **Propagate the replay's own error, and expire the session only on an authentication
  failure.** If the refresh succeeded and the replay then fails with a 500 or a dropped
  connection, the caller must see that failure, not the original 401. Signing a user out
  because the network blipped after a successful refresh is the bug this rule exists to
  prevent, and it is the same mistake in every codebase that gets it wrong.

```ts
// the shape, inside the one HTTP client from 4.4
async function onUnauthorized(request: Request, original: Response): Promise<Response> {
  if (isRefreshRequest(request)) return original;       // never recurse
  try {
    await refreshOnce(doRefresh);
  } catch (err) {
    if (isAuthFailure(err)) { expireSession(); throw err; }  // refresh genuinely rejected
    throw err;                                               // network failure: session intact
  }
  return send(request);   // replayed once; its own error propagates to the caller
}
```

**Test it.** These are small tests and they catch the whole class:

| Test | Assert |
|---|---|
| Two requests, different latencies | The newest result wins |
| Submit clicked twice | One request leaves the client |
| Mutation rejects after an optimistic write | The snapshot is restored |
| Six concurrent 401s | Exactly one refresh request is sent |
| Refresh responds 401 | Session expires once; all queued requests reject with an auth error |
| Refresh fails with a connection error | Session is NOT expired; callers see a network error |
| Replay responds 500 after a successful refresh | The caller sees 500, not 401, and stays signed in |

The last four pair with the backend standard's refresh-rotation rules and are the frontend
half of that contract.

---

