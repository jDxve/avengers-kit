## 10. New Feature Checklist

Adding a networked feature `<feature>`. Start from the template:

```bash
dart run tool/new_feature.dart notes
```

It writes ten files, everything the steps below call for in its simplest form: a domain model
and contract, a DTO, a Retrofit service, the repository with `guard`, the root file with the
provider, a Pattern 1 notifier, a screen that renders all four states, and repository and widget
tests (four states, 2.0x text, accessibility). CI renders the template under a throwaway name,
runs `build_runner`, analyzes it with both plugins, and runs its tests on every PR, so the
template cannot rot into code that violates the rules it is meant to teach. Then adapt it:

```
lib/features/notes/
  notes.dart                                  # root: notesRepositoryProvider + exports
  domain/models/notes_item.dart
  domain/repository/notes_repository.dart
  data/dto/notes_item_dto.dart
  data/services/notes_service.dart            # run build_runner next
  data/repository/notes_repository_impl.dart
  presentation/notifier/notes_notifier.dart   # Pattern 1, load()
  presentation/screens/notes_screen.dart      # loading / success / empty / error + retry
test/features/notes/
  data/notes_repository_impl_test.dart        # Ok, Err(server), changed JSON shape
  presentation/notes_screen_test.dart         # four states, 2.0x text, accessibility
```

The steps, for what the template cannot decide for you:

1. **Folders**: `dart run tool/new_feature.dart <feature>`, or by hand: `features/<feature>/{data/{dto,services,source,repository},domain/{models,repository},presentation/{notifier,screens,components}}`.
2. **Domain models** (`domain/models/`): plain Dart, immutable, `const`, `required` fields. No JSON.
3. **Repository contract** (`domain/repository/`): `abstract interface class` returning `Future<Result<T>>` for networked operations the UI surfaces, plain `Future<T>` for local or fire-and-forget.
4. **DTOs** (`data/dto/`): plain classes with `fromJson`, `toJson`, `toDomain()`.
5. **Service** (`data/services/`): Retrofit `@RestApi` abstract class with `part '<feature>_service.g.dart'`. `@Extra({kSkipAuth: true})` on every endpoint that authenticates by body. `@Header(kIdempotencyKeyHeader)` on every non-idempotent write that must survive a refresh.
6. **build_runner**: `dart run build_runner build --delete-conflicting-outputs`, and commit the output.
7. **Local source** (`data/source/`), only if the feature caches or persists. It belongs to this repository and nothing else may touch it. Never secure storage: that is the session's.
8. **Repository impl** (`data/repository/`): `with RepositoryGuard implements <Feature>Repository`. Use `guard(...)`; use explicit try/catch plus `mapError` where there are side effects to undo, and catch non-Dio throws too.
9. **Root file** (`features/<feature>/<feature>.dart`): declare `<feature>RepositoryProvider` typed by the interface, reading `dioProvider`; `ref.watch(authStateProvider)` there if the repository caches per-user data. Export the domain types other features may use.
10. **Notifier** (`presentation/notifier/`): import the root file for the repository provider. **Default to Pattern 1**. Pattern 2 only for state seeded from storage or a stream. Pattern 3 only when all three gate conditions in §5 hold. `if (!ref.mounted) return;` after every await. `ref.watch(authStateProvider)` inside `build()` if it holds per-user data.
11. **Screen** (`presentation/screens/`): thin view with `static const String routeName`; compose components; kick off loads in a post-frame callback guarded by the idle state.
12. **Components** (`presentation/components/`): every non-trivial widget. Four states including empty. `ref.listen` for navigation and toasts, `errorToMessage(exception)` for copy. Semantics labels on icon-only controls. Pure rendering may move to `presentation/ui/`, with the component passing values and callbacks (§5).
13. **Strings and assets**: add copy to `Strings`, paths to `assets.dart`. No inline literals.
14. **Route and guard**: register in `router.dart`; wrap protected routes in `AuthGuard`.
15. **Shell**: if it is a tab, add it to `main_shell.dart`'s `IndexedStack`.
16. **Tests**: repository (`Ok`, `Err`, non-Dio throw, cache if any); notifier (transitions, double-tap); widget (four states, accessibility, 2.0x text). If it is the app's critical business flow, a flow test. Any test that pins an invariant gets a `// Sabotage:` comment and an entry in `tool/check_sabotage.dart`.
17. **Verify locally**: `dart analyze --fatal-infos` (not `flutter analyze`), `dart run tool/check_architecture.dart`, `flutter test`. CI runs the same and more.
18. **Deviation?** If any rule here does not fit, write the ADR first (§12.1). An `ignore:` without one fails CI.

**Rules that never bend.** DTOs stay in `data`. Domain models stay platform-independent.
Presentation depends only on the domain interface, reached through the feature's root file. Repositories return `Result` and are the
single source of truth for their data, including cache. Notifiers own `DataState`, are the only
place `loading` and `idle` exist, and check `ref.mounted` after every await. Errors travel as
`AppException` and become strings exactly once, at the UI edge, via `errorToMessage`. Only
`SessionStore` touches credentials. Only a server verdict ends a session; a network failure
never does. Nothing is sent twice unless it is safe to send twice. A test that pins an invariant
must be able to fail, and a machine checks that it can. Screens orchestrate,
components connect state, and `ui/` only renders. Imports are `package:` and never cross a boundary the lints forbid.

---
