## 0. Relationship to the Official Flutter Architecture

The Flutter team publishes an architecture guide that splits an app into a **UI layer** and a
**Data layer**, with four components. The dependency direction is:

```
View  ->  Notifier  ->  Repository  ->  Service
```

This playbook implements that guide. The mapping is one-to-one:

| Official guidance | This playbook | Notes |
| --- | --- | --- |
| **View** | `presentation/screens/` + `presentation/components/` + `presentation/ui/` | Thin. Widgets, layout, gesture handlers. `ui/` is the pure part (§5). |
| **Notifier** | **`Notifier`** / `AsyncNotifier` in `presentation/notifier/` | The guide's UI-state component. I call it a **Notifier**: it is the Riverpod class name and the Flutter convention. |
| **Command** | Public intent methods on the notifier | `login()`, `removeMember()`. See §5. |
| **Repository** | `data/repository/<Feature>RepositoryImpl`, wired in `features/<f>/<f>.dart` | Single source of truth. Owns caching and retry. |
| **Service** | `data/services/<Feature>ApiService` (Retrofit) | Wraps one endpoint group. Stateless. |
| **Domain (optional)** | `domain/models/` + `domain/repository/` | Models and the repository contract. No use-case classes until one is shared. |
| **`Result<T>`** | `core/result/result.dart` | `Ok` / `Err`. Returned by every repository. |

The guide describes that component as holding the state the view needs so it can rebuild
without losing data, and exposing callbacks (commands) that the view attaches to event handlers.
A Riverpod `Notifier` does exactly this. The guide's own samples use `ChangeNotifier`; the guide
itself is state-management agnostic.

### The two places I deviate, and why

**1. Feature-first folders instead of layer-first.** The official sample app groups by layer at
the top level (`lib/ui/`, `lib/data/`, `lib/domain/`). I group by feature, with the layers
inside each feature. The reason is deletion and ownership: a feature is the unit of work, and
removing one should be removing one directory, not touching four. This is a folder decision,
not an architecture decision. Every dependency arrow in the table above still points the same
direction. Past roughly six features, layer-first top-level folders start costing more than
they save. Recorded as ADR-001 (§12.1).

**2. Riverpod `Notifier` instead of `ChangeNotifier`.** Riverpod covers both the UI-state role
and dependency injection with one tool, which removes a second DI mechanism from the stack.
`ChangeNotifier` plus `provider` would satisfy the guide equally well; this is a stack
preference, and the boundaries it enforces are stricter, not looser. Recorded as ADR-002.

### One thing I explicitly adopt from the guide

The guide separates **the result of a data operation** from **the state of a screen**. A
repository returns success or failure. "Loading" and "idle" are things a *Notifier* knows, not
things a finished network call can be. One four-case `DataState<T>` used everywhere means
every repository signature advertises two outcomes it can never produce, so the two are split:
`Result<T>` below the repository boundary, `DataState<T>` above it. See §3 and ADR-003.

---

