## Rule index

**Mandatory** applies to every app at every size. **Conditional** applies once its trigger is
true, and then it is mandatory. **Optional** is a recommendation. "Review" means no machine
checks it: those are the rows a reviewer owns.

| # | Rule | Level | Enforced by | § |
| --- | --- | --- | --- | --- |
| 1 | `presentation/` and `data/` of a feature meet only at `domain/` | Mandatory, from the first `features/` folder | `layer_boundary` | 1 |
| 2 | Another feature is reachable only through its `domain/` and root file | Mandatory, from the first `features/` folder | `no_cross_feature_imports` | 1 |
| 3 | `core/` and `common/` never import a feature | Mandatory | `shared_layer_independence` | 1 |
| 4 | `domain/` imports only its allowlist | Mandatory | `domain_purity` | 1 |
| 5 | No feature dependency cycles | Mandatory | `check_architecture.dart` | 1, 8 |
| 6 | An architecture suppression cites an ADR on the line above | Mandatory | `check_architecture.dart` | 12.2 |
| 7 | `package:` imports only inside `lib/` | Mandatory | `always_use_package_imports` | 9 |
| 8 | Repositories return `Result<T>`; only notifiers hold `DataState<T>` | Mandatory | types; review | 3 |
| 9 | An `AppException` becomes copy only in `errorToMessage` | Mandatory | exhaustive switch (compiler) | 4 |
| 10 | Server copy is shown only for `rejected`, one line, bounded | Mandatory | mapper test, sabotage | 3 |
| 11 | Only `SessionStore` touches credentials | Mandatory | review | 3 |
| 12 | Session: one key, memory first, scoped recovery, `resetOnError: false` | Mandatory | session suite, sabotage | 3 |
| 13 | Only a server verdict ends a session | Mandatory | interceptor and refresher suites, sabotage | 3 |
| 14 | Nothing is replayed unless sending it twice is safe | Mandatory | interceptor suite, sabotage | 3 |
| 15 | Body-authenticated endpoints carry `kSkipAuth` | Mandatory | repository test; review | 5 |
| 16 | A write that must survive a refresh carries one `Idempotency-Key` per user intent | Conditional: non-idempotent writes | notifier test, sabotage; backend contract | 5 |
| 17 | `if (!ref.mounted) return;` after every `await` in a notifier | Mandatory | review | 5 |
| 18 | Pattern 1 by default; Pattern 2 and 3 only past their gates | Conditional | review | 5 |
| 19 | Every data screen renders loading, success, empty, and error with retry | Mandatory | widget tests | 5, 7.8 |
| 20 | Accessibility guidelines in both themes; no overflow at 2.0x text | Mandatory | widget tests | 4, 7.8 |
| 21 | Text scaling is clamped, never disabled | Mandatory | `App.builder`; review | 4 |
| 22 | All copy in `Strings`; colors, spacing, radii, type and motion via their tokens | Mandatory | review | 4, 9 |
| 23 | Every invariant test names a sabotage that `check_sabotage.dart` applies | Mandatory | `check_sabotage.dart` | 7.3 |
| 24 | Coverage: 80% overall, 90% in `core/network` and `core/session` | Mandatory | `check_coverage.dart` | 7.2 |
| 25 | The critical auth flow and one business flow run headless and on devices | Mandatory | flow tests, `android` and `ios` jobs | 7.9 |
| 26 | `AppConfig` refuses a bad environment in every build mode | Mandatory | `AppConfig` tests, `check_release_config.dart` | 3, 11.1 |
| 27 | The secure store is excluded from backup and device transfer | Mandatory | `check_release_config.dart` | 3 |
| 28 | CI analyzes at the root and proves both plugins loaded | Mandatory | `check_lint_fixture.dart` | 8 |
| 29 | Generated code is committed and current | Conditional: codegen is used | CI `git status --porcelain` | 11.2 |
| 30 | One component per surface: features never style their own toast, dialog or sheet | Mandatory | review | 4 |
| 31 | A fake repository implements the real contract and can fail | Conditional: before the API exists | repository tests | 5 |
| 32 | Every snippet in this document compiles against the pinned versions | Mandatory | §12.6 record | 12.3 |
| 33 | Feature-first folders | Conditional: past about four capabilities, or parallel developers | review | 2 |
| 34 | A local source and cache behind the repository | Conditional: data reused across screens or sessions | repository tests | 5 |
| 35 | `go_router` | Conditional: any trigger in §4 | review | 4 |
| 36 | Certificate pinning, with a backup pin | Conditional: a high-value target | review | 11.3 |
| 37 | The requirements in §11.6 (pagination, offline, l10n, profiling, ...) | Conditional: each has its trigger | as listed there | 11.6 |
| 38 | `flutter_screenutil` behind `Dimensions` | Optional | ADR-008 | 4 |
| 39 | Golden tests | Optional | CI OS only | 7.8 |
| 40 | `presentation/ui/` imports only its allowlist | Conditional: from the first `ui/` folder | `ui_purity` | 5 |
| 41 | `ui/` widgets are stateless; purely visual state cites an ADR | Conditional: from the first `ui/` folder | `ui_stateless`, `check_architecture.dart` | 5 |
| 42 | Riverpod is the default state library; another one, such as GetX, needs a stated and approved need, and two never hold the same state | Mandatory | review (contract and pubspec.yaml); ui_purity inside ui/ | 12.1 (ADR-011) |

---

