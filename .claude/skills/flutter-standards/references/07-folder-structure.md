## 2. Folder Structure

### The standard tier (what this document describes)

```
lib/
  main.dart              # bootstrap: config, reporter, error hooks, launch init, theme preload, runApp
  main_shell.dart        # bottom-nav shell (IndexedStack) + tab-state notifier
  router.dart            # onGenerateRoute, named routes, global navigatorKey, transitions

  core/                          # app-wide infrastructure. Imports no widget, holds no UI state
    config/
      app_config.dart            # AppConfig.fromEnvironment(): validated in every build mode
    result/                      # pure Dart: imports nothing but dart:core
      result.dart                # Result<T>: Ok<T> | Err<T>  (data-layer outcome)
      app_exception.dart         # AppException + ErrorType: no Dio, no Flutter, no HTTP
    reporting/
      reporter.dart              # crash-reporter facade + NoopReporter
    session/                     # the ONLY code that touches credentials
      secure_storage.dart        # secureStorageProvider (platform options)
      session_store.dart         # SessionStore: in-memory session, write-through, scoped recovery
      storage_keys.dart          # kSession (one key), legacy keys, kSessionStorageKeys
    network/                     # everything that knows about Dio lives here
      http_client.dart           # buildDio(), appConfigProvider, httpAdapterFactoryProvider
      request_flags.dart         # kSkipAuth, kIdempotencyKeyHeader
      dio_error_mapper.dart      # mapDioException(): the one DioException -> AppException site
      repository_guard.dart      # RepositoryGuard mixin: guard() wraps a call into Result
      token_refresher.dart       # TokenRefresher + RefreshOutcome (Refreshed | Rejected | Unavailable)
      auth_interceptor.dart      # bearer inject, single-flight refresh, session epochs, replay policy
      logging_interceptor.dart   # pretty request/response logs (debug only, redacts auth)
      reporting_interceptor.dart # forwards actionable failures, redacted, to the crash reporter
      dio_providers.dart         # SessionExpiry, authInterceptorProvider, dioProvider
      models/
        error_response.dart      # error envelope (freezed optional; see Stack)
    state/
      data_state.dart            # DataState<T> sealed union (UI state, notifiers only)
    utils/
      launch_utils.dart          # first-install wipe, onboarding flags, prefs cache keys

  common/                        # shared presentation building blocks; never imports features/
    models/                      # tiny cross-feature value types (e.g. SimpleOption)
    notifiers/                   # app-wide UI state: theme, toasts, connectivity banner
    resources/
      app_theme.dart             # color primitives, AppColors ThemeExtension, AppTheme, context ext
      strings.dart               # all user-facing copy as static const
      dimensions.dart            # Dimensions.pxNN sizing facade
      assets.dart                # asset path constants
    utils/
      ui_utils.dart              # errorToMessage(), validators, formatters
      constants.dart
      animations/
    widgets/                     # reusable widgets (buttons, inputs, toast, shimmer, ...)

  features/
    <feature>/
      <feature>.dart             # public API: repository provider (typed by the interface) + exports
      data/
        dto/                     # request/response DTOs: fromJson + toJson + toDomain()
        services/                # Retrofit @RestApi abstract class (+ .g.dart)
        source/                  # local source: TTL cache, DAO, prefs wrapper
        repository/              # <Feature>RepositoryImpl (wired in <feature>.dart)
      domain/
        models/                  # plain Dart domain models
        repository/              # abstract interface class <Feature>Repository
      presentation/
        notifier/                # Notifier<State> + NotifierProvider
        screens/                 # thin view screens (routeName lives here)
        components/              # connected widgets: read state, resolve it to values and callbacks
        ui/                      # pure widgets: parameters in, callbacks out (§5)
    auth/
      presentation/
        auth_guard.dart          # route gate; lives here because it reads auth state (see §4)
```

**`core/` or `common/notifiers/`?** Ask what the thing would do with no screens attached.
A session store, an HTTP client and an interceptor all still have work to do; they are
infrastructure, and they live in `core/`. A theme preference, a toast and an offline banner
exist only to be rendered; they are app-wide **UI state**, and they live in
`common/notifiers/` with the widgets that read them. Through rc.3 the theme notifier sat in
`core/theme/`, inside a folder whose own comment said no UI, which left every later piece of
app-wide UI state without an obvious home. *Migrate:* move `theme_notifier.dart` to
`common/notifiers/`; nothing else changes.

Note `core/result/`, `core/state/`, and `core/session/`. Filing `Result` and `AppException`
under `core/network/` is what makes the domain layer *look* like it depends on infrastructure.
They are transport-neutral types, so they sit where that is obvious from the import line.
Credentials get their own folder because exactly one class may touch them, and a folder with
one door is easy to review.

Small or leaf features (splash, onboarding) may collapse to `screens/` and `components/` only.
A feature with no networking may omit `data/` and `domain/` entirely.

### Outside `lib/`

```
.github/workflows/ci.yaml # verify, security, android, ios (§11.2)
config/                   # dev.json, staging.json, prod.json (--dart-define-from-file)
docs/adr/                 # architecture decision records (§12.1)
integration_test/         # the critical flow on a device; same body as test/flows/
test/
  helpers/pump_app.dart   # ProviderScope + ScreenUtilInit + theme wrapper for widget tests
  flows/                  # the critical flow headless, against a scripted backend (§7.9)
  core/ common/ features/ # mirror lib/
tool/
  lints/                  # app_lints: native analyzer plugin (lib/main.dart)
    fixture/              # a tiny package whose imports prove each rule fires, and only where it should
  check_lint_fixture.dart     # fixture expectations + a canary proving the app's own config loads both plugins
  check_architecture.dart     # feature cycles + justified suppressions
  check_release_config.dart   # release defines, Android manifest, backup rules
  check_coverage.dart         # coverage floors, read from lcov.info
  check_sabotage.dart         # applies every named sabotage; fails if its test still passes
  new_feature.dart            # scaffolds a feature from templates/; --check renders and tests it in CI
  templates/feature/          # the feature template (.tmpl files: not analyzed until rendered)
  gen_coverage_helper.sh      # makes untested files count as 0%, not as absent
```

### The small-app tier (start here below roughly four features)

Full vertical slices are overhead on a three-screen app. Start layer-first inside one package
and promote later. The layering rules are identical; only the folders differ.

```
lib/
  core/           # config, result, session, network, theme, utils
  common/         # widgets, resources
  data/
    dto/
    services/
    repository/
  domain/
    models/
    repository/
  presentation/
    notifier/
    screens/
    components/
```

**Promote to feature-first when any of these becomes true**, not before:

- more than about four or five product capabilities, so `presentation/screens/` stops being scannable;
- more than one developer working in parallel and colliding in the same folders;
- you find yourself prefixing filenames to disambiguate (`order_list_notifier.dart` vs `product_list_notifier.dart` in one directory);
- a change to one capability keeps forcing edits in four sibling directories.

Promotion is mechanical: create `features/<name>/`, move the matching files, fix imports. The
boundary lints in §8 start paying for themselves at exactly this point, because cross-feature
imports only become possible once features exist. Everything in `core/`, including the session
and the interceptor, is identical in both tiers: the small tier is smaller in folders, not in
safety.

**What is mandatory, and what is proportional.** The rules that protect correctness and
credentials apply at every size. Everything else is adopted when the app has the problem it
solves.

| Always | When the requirement is real |
| --- | --- |
| `SessionStore`, `AuthInterceptor`, `TokenRefresher` as written | A local source and cache (§5): only if the data is reused across screens or sessions |
| `Result` in data, `DataState` in UI, `errorToMessage` | Pattern 2 and Pattern 3 notifiers (§5): only past their gates |
| `AppConfig` validation and `check_release_config` | `flutter_screenutil` (ADR-008): only for pixel-specified phone designs |
| The four boundary rules (from the first `features/` folder) and the plugin canary | More than one integration flow: only for a second flow whose failure is an incident |
| The interceptor and session suites, and `check_sabotage` over them | Golden tests, performance budgets beyond the defaults in §11.4 |
| Four states per data screen, 2.0x text scale, semantics | Feature root files: none needed in the small tier, which has one `data/` |
| The real repository **contract** (§5), from the first screen | The real repository **implementation**: only once the endpoint exists; until then, a fake behind the same interface |
| Hand-written `Result` and `DataState` | Codegen beyond `retrofit`: only for a type too large to hand-write and too easy to get wrong |

---
