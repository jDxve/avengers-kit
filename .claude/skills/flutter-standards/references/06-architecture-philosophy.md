## 1. Architecture Philosophy

**Mental model:** feature-first on the outside, layered on the inside.
The app is a set of self-contained features. Each feature owns its full vertical slice
(`data`, `domain`, `presentation`). Cross-cutting infrastructure lives in `core`;
reusable UI and helpers live in `common`.

**Why feature-first:** a feature is the unit of work. Everything needed to build, test, or
delete a feature sits in one folder. You never hunt across top-level `models/`, `services/`,
`screens/` buckets.

**Why layering inside a feature:** the UI must not know how data is fetched, and the data
layer must not know how data is displayed. The `domain` layer (plain Dart models plus an
abstract repository interface) is the contract between them. Presentation depends on the
domain interface, never on Dio, Retrofit, or DTOs.

**Dependency direction (always inward):**

```
presentation      ->  domain   <-  data
(View + Notifier)   (contract)   (Repository + Service)
```

Each rule below names the lint or script that enforces it (§8). A rule without an enforcer is
a convention, and this document says so where that is the case.

- `presentation` depends on `domain` (models plus the abstract repository), on its feature's root file, and on `core` / `common`. It never imports its own feature's `data/`. *Enforced by `layer_boundary`.*
- `data` depends on `domain` (it implements the interface and maps DTOs to domain models). It never imports `presentation/`. *Enforced by `layer_boundary`.*
- **One file per feature sees both sides**: `features/<f>/<f>.dart`, the feature's public API. It wires the `data/` implementation to the `domain/` contract as a provider typed by the interface, and exports what other features may use (ADR-009).
- `domain` depends only on `core/result/` (`Result`, `AppException`), other features' `domain/`, and a short allowlist of pure Dart libraries. No Flutter, no Dio, no `dart:io`. *Enforced by `domain_purity`.*
- A feature may import another feature's `domain/` and its root file, and nothing else of it. `data/` and `presentation/` are internals. *Enforced by `no_cross_feature_imports`.*
- `core/` and `common/` never import a feature. *Enforced by `shared_layer_independence`.*
- The dependency graph between features stays **acyclic**. If `orders` needs `billing` and `billing` needs `orders`, the shared concept belongs to one of them, or to a third feature, or to `common/`. *Enforced by `tool/check_architecture.dart`.*

**On the word "pure".** The domain layer is **platform-independent and transport-independent**:
no Flutter, no Dio, no HTTP, no `dart:io`. It is not dependency-free, and I do not claim it is.
It depends on two project-level types, `Result` and `AppException`, which live under
`core/result/` precisely because they are not network types. If you need a genuinely
dependency-free domain, extract it to its own Dart package; for an app of this size that is
ceremony without a payoff.

**What goes where:**

- **`core/`**: app-wide infrastructure with no UI. Config, the session, the HTTP client factory and interceptors, `Result`, `AppException`, the repository guard, theme state, storage keys, launch bootstrap. If two unrelated apps could share it verbatim, it is probably core.
- **`common/`**: shared presentation-side building blocks. Reusable widgets, resources (theme, strings, dimensions, assets), UI utils and validators. Depends on `core`; never on a feature.
- **`features/<name>/`**: one product capability, full vertical slice. Depends on `core`, `common`, and other features' `domain/` and root file only.
- **`features/<name>/<name>.dart`**: that feature's public API and wiring. Repository providers live here, typed by the domain interface, so no `presentation/` file ever sees an `Impl` (ADR-009). In rc.1 they lived in `data/repository/`, which every notifier imported: the playbook broke its own `layer_boundary` rule in its own worked example, and nothing noticed because the rules had never run.

**Views are minimal.** A screen composes components and wires notifiers. It holds no
business logic and no inline widget tree of significance. The guide allows a view to own
purely visual logic: animation state, layout decisions based on screen size or orientation,
and simple routing. Everything touching data belongs in the notifier.

---

