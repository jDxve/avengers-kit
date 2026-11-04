## 6. State Management with Riverpod

Riverpod is both the DI container and the notifier layer. One rule governs all of it: **a
provider lives next to the thing it exposes, and the provider graph points the same way the
layers do.** Outer depends on inner, never sideways.

### The provider graph mirrors the layers

```
appConfigProvider ----------+
httpAdapterFactoryProvider -+--> authInterceptorProvider --> dioProvider --> <feature>RepositoryProvider --> <feature>NotifierProvider --> Widget
secureStorageProvider --> sessionStoreProvider --+                          (features/<f>/<f>.dart)          (notifier)
sessionExpiredProvider --------------------------+

sessionExpiredProvider, authInterceptorProvider, authRepositoryProvider --> authStateProvider
authStateProvider --> any provider whose data belongs to one session (profileRepositoryProvider)
```

- `appConfigProvider`, `httpAdapterFactoryProvider`, `secureStorageProvider`, `sessionStoreProvider`, `sessionExpiredProvider`, `authInterceptorProvider`, `dioProvider`: core infrastructure as `Provider<T>`. Constructed once, injected everywhere, overridable in tests. The only global is `reporter` (§3), for the reason given there.
- `<feature>RepositoryProvider`: DI for the data layer, declared in the feature's root file. A `Provider<<Feature>Repository>` that reads `dioProvider` and builds any local source, returning the concrete `Impl` typed as the interface. Presentation depends on this **interface** provider, never on the `Impl` type.
- `<feature>NotifierProvider`: the notifier. It reads the repository provider; nothing below it can see it.
- A widget only ever watches notifier providers, plus a couple of app-wide ones such as `authStateProvider` and `themeProvider`. It never watches a repository or `dioProvider` directly.

If a widget reaches past its notifier to a repository or Dio, the graph is broken the same way
an import that skips a layer is, and the §8 boundary lints catch the import that makes it
possible.

### Which provider type, and when

| Provider | Use for | Example |
| --- | --- | --- |
| `Provider<T>` | Stateless DI, constructed once | `dioProvider`, `sessionStoreProvider`, `<feature>RepositoryProvider` |
| `NotifierProvider<N, S>` | Per-screen or per-action notifier | `loginNotifierProvider` (Pattern 1), `familyProvider` (Pattern 3) |
| `AsyncNotifierProvider<N, T>` | State seeded from an async source or stream | `authStateProvider` (Pattern 2) |

No `StateProvider` or `ChangeNotifierProvider` for feature state: they hide the transitions the
UI needs to see, and Riverpod 3 moved both to its `legacy` import for that reason.
`FutureProvider` is fine for a read-only derived value with no commands attached, but a screen
with actions gets a `Notifier`.

### `watch` vs `read` vs `listen`

- **`ref.watch`**: reactive dependency. Only inside a `build()` (widget `build`, `Notifier.build`, or a provider body). Watching `authStateProvider` inside a notifier's `build()` is how a feature resets on sign-out.
- **`ref.read`**: one-shot, non-reactive. Only inside callbacks and event handlers, to fire a command. Never `read` in `build` (you would miss updates); never `watch` in a callback (you would rebuild-thrash).
- **`ref.listen`**: side effects that are not UI. Navigation, toasts, dialogs. It lives in a widget `build` but returns nothing. This is the one place a `DataError` becomes a toast.

### Notifier conventions

- `build()` returns the **initial** state and does setup only: `watch` dependencies, subscribe to streams with `ref.onDispose` to cancel. No network call fires from an action notifier's `build()`; the view kicks off the load in a post-frame callback guarded by the idle state.
- Public methods are **commands**: verbs the view calls. They mutate `state`; the UI reacts. Notifiers never return widgets and never touch `BuildContext`.
- After every `await` in a command: `if (!ref.mounted) return;` before touching `state` or `ref`.
- Dependencies are getters over `ref.read`, or locals in `build()`. Never `late final` fields assigned in `build()`.
- Cross-notifier writes go through `.notifier`, never by mutating another provider's state directly.
- Reset ephemeral state with a `reset()` command or `ref.invalidate(provider)`. App-wide teardown flows through `authStateProvider`, not manual resets scattered across notifiers.

### Lifecycle and scope

Providers are **kept alive by default**, because the app is tab-based over an `IndexedStack`:
every tab stays mounted for the app's life, so its notifier should too. Disposing it would
drop scroll position, filters, and loaded data on every tab switch. Riverpod 3 pauses listeners
in widgets that are not visible (an offstage tab), so a keep-alive tab provider costs memory,
not rebuilds.

Add `.autoDispose` when **all** of these hold:

- the provider is scoped to a route that is pushed and popped (a detail screen, a modal, a wizard step), not a persistent tab;
- its state is per-visit and stale on return, so rebuilding from scratch is correct rather than lossy;
- it holds something that must be released promptly: a `StreamSubscription`, a large list, a controller.

```dart
// illustrative
final orderDetailProvider =
    NotifierProvider.autoDispose<OrderDetailNotifier, DataState<Order>>(
  OrderDetailNotifier.new,
);
```

Two escape hatches: `ref.keepAlive()` inside an `autoDispose` provider pins it after a
successful load, and `ref.invalidate(provider)` forces a keep-alive provider to rebuild on
demand, for example on pull-to-refresh, without changing its scope.

**If you cannot point to a push/pop route AND a leak or staleness reason, leave it keep-alive.**

**Riverpod 3 retries failing providers automatically.** That is right for a flaky read and
wrong for anything whose failure is a decision. `authStateProvider` cannot fail by construction
(`restoreSession` never throws). For any other provider where a retry would repeat a side
effect, disable it on that provider rather than globally.

Overrides are the test and bootstrap seam:
`ProviderContainer(overrides: [<feature>RepositoryProvider.overrideWithValue(mock)])`. Because
every dependency is a provider, nothing needs a real Dio or keystore to test.

---
