## Stack

- **State**: Riverpod by default (ADR-011): `flutter_riverpod` (v3), `Notifier` / `AsyncNotifier` + `NotifierProvider`. Another library, such as GetX, is allowed when the contract or a project ADR states the need and Dave approves it. Two libraries never hold the same state. `setState` and Flutter's controllers stay fine for widget-local visual state.
- **Networking**: `dio` + `retrofit`. Retrofit for typed calls; raw Dio for nullable, 204, or dynamic-shape endpoints.
- **Data-layer result**: hand-written sealed `Result<T>` (`Ok` / `Err`). Two cases, because a completed call has exactly two outcomes.
- **UI state**: hand-written sealed `DataState<T>` (idle / loading / success / error). Owned by notifiers only. Four cases, because a screen genuinely has four.
- **Codegen**: `retrofit` for services, and nothing else by default. `freezed` is **optional**, and earns its place only where a type is too large to hand-write and too easy to get wrong: wire unions, or an error envelope with many fields. A four-case union is neither (§3).
- **Hooks**: `flutter_hooks` and `hooks_riverpod` are allowed under Riverpod when needed. They are optional, never required. `ui/` purity is unchanged: a `ui/` widget may use hooks only for purely visual local state under ADR-010 (for example animation or text controllers), after `flutter_hooks` is added to the `ui_purity` allowlist; hooks holding async or data state (`useFuture`, `useStream`) are not visual state and are caught by review only. `hooks_riverpod`, `HookConsumerWidget`, `ConsumerWidget` and `ref` stay out of `ui/`.
- **Session**: `flutter_secure_storage` behind a single `SessionStore` (§3) that is the only code allowed to touch credentials. `shared_preferences` for preferences and cache.
- **Idempotency**: `uuid` for `Idempotency-Key` headers on non-idempotent writes (§3, §5).
- **Sizing**: `flutter_screenutil` behind a `Dimensions` facade. A default, not an invariant (see §4).
- **Theming**: `ThemeExtension<AppColors>` plus a `BuildContext` extension for ergonomic color access.
- **Testing**: `flutter_test` + `mocktail` (no codegen, matching the hand-written ethos), `integration_test` for the same critical flow on a device. DI is exercised through `ProviderContainer` with providers overridden. Never a real Dio, real keystore, or real socket.
- **Enforcement**: native analyzer plugins (Dart 3.10+): a local `app_lints` plugin for the layering rules and `riverpod_lint`. Five Dart scripts under `tool/` do what a per-file linter cannot: prove the plugins load, find feature cycles, check release config, enforce coverage floors, and prove each invariant test can fail.

---

