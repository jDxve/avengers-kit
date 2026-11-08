## 12. Governance

A standard that cannot change becomes ignored, and a standard that changes silently becomes
folklore. This section is how the playbook evolves without either.

### 12.1 Architecture decision records

Every significant decision, and every deviation from this document, is an ADR in `docs/adr/`.
Short is fine; unrecorded is not.

```markdown
# ADR-NNN: <decision in one line>

- Status: proposed | accepted | superseded by ADR-MMM
- Date: YYYY-MM-DD
- Revisit when: <the concrete trigger that would reopen this>

## Context
What forces the decision. Facts, not opinions.

## Decision
What we do, stated so a reviewer can check a PR against it.

## Alternatives considered
Each with the reason it lost.

## Consequences
What gets easier, what gets harder, what we now have to maintain.
```

The decisions this playbook already rests on:

| ADR | Decision | Revisit when |
| --- | --- | --- |
| 001 | Feature-first folders over the official layer-first layout | the app shrinks below about four features |
| 002 | Riverpod `Notifier` over `ChangeNotifier` + `provider`; Riverpod is the default state library (ADR-011) | Riverpod's major version changes the notifier model |
| 003 | `Result<T>` in data, `DataState<T>` in UI | never, without a replacement for both |
| 004 | Navigator 1.0 until a `go_router` trigger in §4 holds | any trigger holds |
| 005 | 401 replay only for idempotent methods or requests with an `Idempotency-Key` | the backend documents that auth precedes execution on every route |
| 006 | Session in memory with write-through to secure storage; scoped recovery | the platform plugin changes its failure modes |
| 007 | Native analyzer plugins for architecture rules (supersedes `custom_lint`) | the plugin API reaches 1.0, or `flutter analyze` starts reporting plugin diagnostics |
| 008 | `flutter_screenutil` behind the `Dimensions` facade | tablets, foldables, or web become targets |
| 009 | A feature's public API is its `domain/` plus one root file | a feature must expose more than providers and domain types |
| 010 | Visual state in `ui/` (see `docs/adr/010-visual-state-in-ui.md`) | see the ADR |
| 011 | Flutter state management: Riverpod by default (see `docs/adr/011-flutter-state-riverpod-default.md`) | Riverpod's major version changes its state model |

### 12.2 Exception policy

A rule with no way to deviate gets deleted by frustration. A rule with a free way to deviate
gets deleted by attrition. The way to deviate here costs one paragraph:

1. Write the ADR explaining why this case is different and what bounds the exception.
2. Suppress the specific lint on the specific line, with the ADR cited directly above it:

   ```dart
   // ADR-013: the legacy importer reads billing DTOs until the v3 API ships (2027-Q2).
   // ignore: app_lints/no_cross_feature_imports
   import 'package:app/features/billing/data/dto/invoice_dto.dart';
   ```

3. Review: a PR that adds or widens an exception needs a second reviewer's approval.

`tool/check_architecture.dart` fails CI on any suppression of an architecture rule without an
`// ADR-NNN` line directly above it. `ignore_for_file` for these rules is allowed only with the
same citation and should be rare enough that every one is known by name.

### 12.3 Dependencies and compatibility

**Supported baseline.** One Flutter version, pinned in CI (`3.47.8`, Dart `3.13.7`, at the time
of writing), and the Dart SDK it ships. The reference app's lockfile records the rest:
`flutter_riverpod 3.4.3`, `riverpod_lint 3.1.9`, `dio 5.11.1`, `retrofit 4.10.0`,
`flutter_secure_storage 11.2.0`, `analysis_server_plugin 0.3.25`, and `freezed 4.0.3` where it is used. The Android `minSdk` and iOS deployment target are recorded in the
reference app and raised only by ADR, because raising them drops users.

**Upgrade cadence.**

- **Patch and minor** updates arrive weekly as one grouped Dependabot PR. CI green is sufficient to merge.
- **Major** updates are one dependency per PR, never grouped, with the checklist below in the description.
- **The Flutter SDK** moves in its own PR, after the new stable has had its first hotfix, so a toolchain regression reads as a toolchain regression.

**Watched dependencies.** A major bump of any of these needs the named re-check, not just a
green build:

| Dependency | Re-check |
| --- | --- |
| `flutter_secure_storage` | §3 platform options (`resetOnError` default), all three SharedPreferences file names in `data_extraction_rules.xml` against the plugin's Android source, `SessionStore` suite on a real device |
| `dio` | `AuthInterceptor` suite, `DioException` types in the mapper, `QueuedInterceptor` semantics |
| `flutter_riverpod` / `riverpod_lint` | `ref.mounted`, retry and pause behavior (§6), notifier lifecycle on rebuild |
| Dart SDK / `analysis_server_plugin` / `analyzer` | fixture run and root canary, `dart analyze` at the root still reports plugins, the plugin still loads in the IDE |
| `retrofit`, `build_runner`, and `freezed` where used | regenerate, diff the generated output, `@Extra` and `@Header` still applied, factory `baseUrl` type still matches |
| `flutter_screenutil` | widget tests at 2.0x text scale |

**Lockfile discipline.** `pubspec.lock` is committed for the app, for `tool/lints`, and for `tool/lints/fixture`.
CI runs `pub get --enforce-lockfile`, so a dependency cannot change without a visible diff.

### 12.4 Reference implementation

The playbook is proven by a small app, not by this document. The reference repository
(`reference_app`, shipped with this version) contains:

- `auth` exactly as in §5: login, the guard, session expiry, sign-out with revoke;
- `profile`, a cached read with `forceRefresh`, a 404-as-empty case, and a session-scoped cache;
- `orders`, a non-idempotent write with an idempotency key owned by the notifier's intent;
- every test in §7, the lint plugin and its fixture, the `tool/` scripts, the feature template and its scaffolder, the ADRs, and the CI workflow in §11.2.

It doubles as the starter repository (Quick start): it passes every check in §11.2 as shipped.

**Snippets come from the reference app.** Every non-conceptual code block in this document was
generated from the reference app's files when this version was cut. When the reference app
changes, the document changes in the same PR, and the reviewer checks the two against each
other. A snippet that no longer matches its source is a documentation bug with a deadline: the
next release.

**A version of this playbook is final only when the reference app's CI is green on GitHub at
that version's pins.** That is what removes `-rc` from the version number.

### 12.5 Versioning and changelog

Semantic versioning, applied to rules rather than code:

- **Major**: a rule changes such that compliant code becomes non-compliant (a new lint, a changed contract).
- **Minor**: a new section, pattern, or optional practice; compliant code stays compliant.
- **Patch**: corrections and clarifications that change no rule.

Each entry says what changed and what an existing app must do about it.

#### 2.2.1-rc.1

2026-11-08. Corrects the CI example in §11.2. Patch: no rule changes, so an existing app needs no change.

- **Fixed:** the §11.2 example pins `actions/checkout` to a full SHA (v7.0.1) with `persist-credentials: false`, and every other action uses the zero-SHA `# PIN` placeholder, so the example no longer contradicts the action pinning rule. It points to `devops-engineering/assets/ci-flutter.yml` and `release-mobile.yml` as the maintained templates.
- **Fixed:** the §11.2 example matches `ci-security.yml` and `ci-flutter.yml`: the `security` job grants `contents: read` and `pull-requests: read` and turns off gitleaks comments and artifact upload, and `verify` validates Gradle wrapper jars.

#### 2.2.0-rc.1

Sets Riverpod as the default state library. Minor: existing Flutter rules apply as before.

- **New:** Riverpod is the default, and another library needs a stated, approved need (ADR-011). Rule index row 42.
- **Changed:** hooks are allowed when needed, with `ui/` purity unchanged: `hooks_riverpod`, `HookConsumerWidget` and `ref` stay out of `ui/`.
- **Changed:** `ui_stateless` also flags `HookWidget` and `StatefulHookWidget`.

#### 2.1.0-rc.1

Adds an optional pure layer, so UI can be generated or reviewed in isolation. Minor: existing
code stays compliant, because the rules apply only inside `presentation/ui/`.

- **New:** `presentation/ui/`, with the `ui_purity` and `ui_stateless` lints (§5, §8). An app adopting it adds both rules and their fixture.
- **Fixed:** "Views orchestrate, components render" contradicted §5 and §10, where components read notifiers. The roles are now screens, components, and `ui/`.
- **Fixed:** Rule index numbers 30 to 32 were used twice. The second block is now 33 to 39. The theme notifier heading now shows its current path, and the session section says four properties, not three.

#### 2.0.0

The release candidate did its job: every item below was found by **building two features
against rc.3** in a real app, not by review. Three are corrections to defects in the document
itself, and one of those was a snippet that did not compile.

Corrections:

- **`DataState` is hand-written** (§3), for the reason `Result` already was: Dart 3 sealed
  classes give the exhaustiveness this type exists for, and `@freezed` was buying four cases
  and two getters at the price of `build_runner` in every app. `freezed` leaves the required
  stack and becomes optional, for wire unions and large error envelopes. *Migrate:* replace
  `data_state.dart` with the hand-written version; call sites are unchanged, since the case
  names and the `switch` ergonomics are identical. Delete the dependency if nothing else uses it.
- **The `pumpApp` helper did not compile** (§7.8). It took `List<Override>`, a type
  `flutter_riverpod` 3.x does not export, so the helper most teams copy first failed on the
  version §12.3 pins. It now takes a `ProviderContainer` the test builds with
  `ProviderContainer.test(overrides: [...])`, which infers the type at the call site. It also
  no longer hard-codes `ScreenUtilInit`, which contradicted §4 making ScreenUtil optional.
  *Migrate:* replace `test/helpers/pump_app.dart`; call sites pass `container:` instead of
  `overrides:`.
- **App-wide UI state has a home** (§2). `common/notifiers/` holds theme, toasts and the
  offline banner. Through rc.3 the theme notifier lived in `core/theme/`, inside a folder
  whose own comment read "no UI", which left every later piece of app-wide UI state
  homeless. *Migrate:* move `theme_notifier.dart` to `common/notifiers/`.

New sections:

- **§5 Before the API exists.** The screens-first phase, which most apps spend months in and
  rc.3 did not mention: the real contract, a fake repository behind it, `Ok(null)` for absent
  versus `Err` for unreachable, latency as a constructor parameter, and the one-line swap in
  the feature root file. Says what *not* to build yet.
- **§4 Accessibility.** Expanded from one paragraph. Names for icon-only controls, live
  regions for anything that appears unbidden, `scopesRoute`/`namesRoute` for dialogs,
  reduce-motion, text scale, contrast, and the 44/48 tap-target collision between an iOS
  design spec and `androidTapTargetGuideline`: keep the visual, grow the hit area.
- **§4 Design tokens.** Spacing, radius, type, motion and elevation get the same treatment
  color already had, with role names over value names, and one component per surface.
- **Quick start: what you actually need to read.** Six sections build a feature; the rest is
  reference for the parts you touch once.

One rule added:

- **Every snippet compiles against the versions §12.3 pins**, and §12.6 records it. A
  document that ships code is a dependency like any other.

#### 2.0.0-rc.3

From a second external review. No existing rule is relaxed; one is added (server copy).

- **Server copy is constrained.** `_extractServerMessage` strips control characters, line separators and bidirectional overrides, and drops empty or over-long messages, so `errorToMessage` falls back to generic copy. *Migrate:* replace `dio_error_mapper.dart`.
- **Threat model and limits (§3).** Each protected scenario mapped to the test that proves it, and what the design does not protect against.
- **Backend idempotency contract (§5).** Five requirements and a staging check; the client cannot verify exactly-once on its own.
- **Quick start and Rule index.** One page to adopt the playbook; every rule labeled mandatory, conditional, or optional, with what enforces it and which rows a reviewer owns.
- **Feature template.** `dart run tool/new_feature.dart <name>` writes ten files that already pass the rules; CI renders and tests the template on every PR.
- **Physical-device session script (§11.4)** and a **run record template (§12.6)**.
- **§11.6 rewritten** as conditional requirements: pagination, offline and sync, caching and invalidation, localization, accessibility audits, performance, crash-free monitoring, and more, each with a trigger and its evidence.
- New tests: server-copy sanitization; the first-launch keychain wipe. 29 sabotages, all killed.

#### 2.0.0-rc.2

Every item below was found by building and running the reference app, not by review. An
existing rc.1 app must migrate where it says so.

Correctness and security:

- **The boundary lints moved to a native analyzer plugin.** `custom_lint` 0.8.1 and `riverpod_lint` 3.x no longer resolve together. *Migrate:* replace `tool/lints` with the native plugin (§8), drop `custom_lint`, add the `plugins:` block, and change suppressions to `app_lints/<rule>`.
- **CI analyzes with `dart analyze` at the root.** On Flutter 3.47.8, `flutter analyze` and path-scoped `dart analyze` report no plugin diagnostics, and a wrong plugin path is silent. *Migrate:* replace the analyze step; add `check_lint_fixture.dart`, which now also plants a canary in the app.
- **The worked example violated its own layer rule.** Repository providers lived in `data/` and every notifier imported them. *Migrate:* move each `<feature>RepositoryProvider` to `features/<f>/<f>.dart` (ADR-009). Cross-feature reads of `authStateProvider` go through `auth.dart`.
- **`layer_boundary` now forbids `data/` importing `presentation/`.** rc.1 promised every rule an enforcer; this one had none.
- **The invariant-2 interceptor test could not fail.** Two mechanisms each covered the other; with its named sabotage applied, the test stayed green. `_failedGeneration` is gone; `_expired` stops refresh after teardown, and the epoch bump quiets siblings, each with its own test. *Migrate:* replace `auth_interceptor.dart`.
- **Android silently overrode the session contract.** `flutter_secure_storage` 11 defaults `resetOnError` to `true`, deleting undecryptable keys and reporting them as absent. *Migrate:* pass `resetOnError: false`.
- **Backup rules missed the key file.** `FlutterSecureKeyStorage.xml` and `FlutterSecureStorageConfiguration.xml` are now excluded from cloud backup and device transfer, and CI checks all six exclusions. *Migrate:* replace `data_extraction_rules.xml`.
- **The session is one write.** Both tokens are stored as one JSON value under one key, so a crash mid-rotation cannot strand a consumed refresh token. *Migrate:* none; `SessionStore.load` migrates the two-key layout on first launch.
- **The storage chain cannot be poisoned.** `_serial` catches and reports what an operation lets escape, so one failure cannot skip every later storage call.
- **Smaller fixes.** 429 maps to `retryable`. `DataState.from` moved onto the class and returns `DataState<T>.idle()`, not an inferred `DataIdle<Never>`. Retrofit factories take `String? baseUrl`. Flavor names use `manifestPlaceholders` (AGP rejects `resValue` by default). `SessionExpiry` replaces the raw `StreamController` provider. OSV is pinned to a real version.

Verification (new):

- `tool/check_sabotage.dart` applies all 27 named sabotages and fails if any test survives, does not compile, or no longer exists. 27 of 27 are killed.
- `tool/check_coverage.dart` replaces `lcov` and `grep -oP`.
- The critical flow runs headless on every PR and on an emulator and a simulator in CI, from one shared function, and asserts the token each request carried.
- New tests: session contract rows for atomic rotation, a hanging keystore, legacy migration and the chain; secure-storage options; logger and reporter redaction; refresher classification; every `ErrorType` mapping; `AppConfig.parse`; idempotency intent; profile cache expiry; accessibility in both themes.
- The `android` and `ios` jobs, and §11.4's platform coverage table.

Governance: ADR-007 superseded, ADR-009 added, mandatory-versus-proportional table in §2, a
debugging procedure for false-positive lints in §8, §12.6 verification record.

#### 2.0.0-rc.1

Correctness and security fixes (existing apps must migrate):

- **Boundary lints now actually run in CI.** `flutter analyze` never reported `custom_lint` rules; CI adds `dart run custom_lint` and a fixture run. *Migrate:* add both steps, then fix whatever they report.
- **Release config can no longer ship a LAN URL.** `AppConfig.fromEnvironment()` throws in every build mode; unknown `APP_ENV` is an error; CI validates release configs. *Migrate:* replace `app_config.dart`, add `appConfigProvider` override in `main()`.
- **Account switch can no longer replay user A's request with user B's token.** Session epochs in `AuthInterceptor`; `startSession()` and `endSession()` replace `onSessionStarted()`. *Migrate:* call `endSession()` in sign-out.
- **A network failure during refresh no longer logs the user out.** `RefreshOutcome` replaces a nullable token; only 400/401/403 from the refresh endpoint end a session.
- **Wrong password no longer says "session expired".** `kSkipAuth` on body-authenticated endpoints; 401 there maps to `rejected`. 403 maps to `forbidden`. *Migrate:* add `@Extra({kSkipAuth: true})` to login, register, refresh, revoke, reset.
- **Non-idempotent requests are no longer replayed blindly.** Replay requires an idempotent method or an `Idempotency-Key`; otherwise `retryable`. *Migrate:* add idempotency keys to writes that must survive a refresh.
- **Secure-storage recovery is scoped.** `SessionStore` replaces `safeRead`; no `deleteAll()` on read failure; reads that fail before first unlock no longer sign the user out. *Migrate:* route all credential access through `SessionStore`.
- **iOS keychain items no longer restore onto other devices.** `first_unlock_this_device` replaces `first_unlock`.
- **Android 12+ device transfer excluded.** `dataExtractionRules` added; CI checks the manifest.
- **Refresh and replay clients share transport policy** with the main client via `buildDio`, so certificate pinning cannot be bypassed.
- **Crash reports carry `NetworkFailure`, not raw `DioException`,** so query strings and ids stay out of the dashboard; 4xx verdicts are no longer reported.
- **Notifier fixes.** `ref.mounted` after every await; Pattern 3 no longer uses `late final` assigned in `build()`; `setAuthenticated` waits for a pending cold-start restore.
- **`common/` no longer depends on a feature.** `AuthGuard` moved to `features/auth/presentation/`; enforced by `shared_layer_independence`. The guard is now the single navigation authority on session end.

Enforcement and verification (new):

- Two new lints, `shared_layer_independence` and `domain_purity`; resolution by `Uri.resolve` instead of the analyzer element API; export and conditional-import coverage.
- `tool/check_architecture.dart` for feature cycles and ADR-backed suppressions; replaces the unverified third-party cycle check.
- Generated-code check uses `git status --porcelain` so untracked output is caught.
- Coverage: 80% overall, 90% on `core/network` and `core/session`, with a helper so untested files count.
- Test matrix (§7.1), test honesty rules (§7.3), session suite, interceptor suite expanded from six to eleven cases, widget tests with accessibility and text-scale checks, integration test shape.
- `security` and `integration` CI jobs; Dependabot for actions and pub; SHA-pinning policy.

Production and governance (new):

- Production readiness gates with evidence (§11.4), performance budgets, rollout, rollback, and incident procedure (§11.5).
- ADRs, exception policy, dependency and compatibility policy, reference implementation, and this changelog (§12).

### 12.6 Verification record

**`2.0.0` status.** The changes in 2.0.0 are to this document and to three files
(`data_state.dart`, `pump_app.dart`, `theme_notifier.dart`'s location). They were found by
building against rc.3 in an app, and the hand-written `DataState` and the corrected
`pumpApp` are both in use there, under `flutter_riverpod` 3.4.3 on Flutter 3.47.8. **The full
matrix below has not been re-run for 2.0.0**; it is the rc.3 record. Before tagging, re-run
it against the reference app, and add the new row: every Dart snippet in this document
extracted and compiled against the pinned versions.

What was executed for `2.0.0-rc.3`, against a clean clone of the reference app, on Linux with
Flutter 3.47.8 / Dart 3.13.7, on 2026-10-28.

| Check | Result |
| --- | --- |
| `pub get --enforce-lockfile` (app, plugin, fixture), `dart format`, `build_runner` then `git status --porcelain` | resolves; formatted; generated code committed and current |
| `dart analyze --fatal-infos` (app, both plugins) | no issues |
| `dart analyze --fatal-infos` (`tool/lints`) | no issues |
| `check_lint_fixture.dart` | 13 expected diagnostics, 4 rules, suppression honored; canary sees both plugins. With the plugin path misspelled: fails, as it should |
| `check_architecture.dart` | 3 features, no cycles. With an `auth -> profile` import planted: fails with `auth -> profile -> auth` |
| `check_release_config.dart` | staging and prod pass. With `APP_ENV: production`, an `http` URL and `API_KEY`: three errors |
| `flutter test --coverage` | 98 tests pass (including the conceptual Pattern 3 compile check) |
| `check_coverage.dart` | 85.5% overall, 93.5% `core/network`, 98.3% `core/session` |
| `check_sabotage.dart` | 29 of 29 killed. A sabotage that does not compile is reported as invalid, not as killed (caught once during this run) |
| `new_feature.dart --check` | 10 files render, analyze, and pass. With a wrong expectation in the template test, or a `presentation -> data` import in the template: fails |
| rc.1 invariant-2 test, reproduced, with its named sabotage | still passes (the defect fixed in rc.2) |
| OSV scan of `pubspec.lock` (v2.7.0) | 118 packages, no issues |
| `flutter build appbundle --flavor prod --release --obfuscate --split-debug-info` | builds (50.1 MB). Merged manifest: `allowBackup=false`, extraction rules present, no cleartext, no `.dev` suffix. Symbols split for arm, arm64, x64 |
| `flutter build apk --flavor dev --debug` (rc.2 code) | builds. Merged manifest: `.dev` suffix, "Reference Dev", cleartext allowed (dev only) |
| Android emulator flow, iOS build and simulator flow, gitleaks | **not run here**: the `android`, `ios` and `security` CI jobs on GitHub |
| Physical-device session script (§11.4) | **not run here**: per app release |

The `-rc` suffix comes off when the emulator, simulator and security jobs are green on GitHub
(§12.4). The device script belongs to each app release, not to the playbook's version.

**Run record template.** Copy this into the release ticket, or into this section for a playbook
version, every time. A result without its commit and versions is not evidence.

```markdown
- Playbook version / app version:
- Commit SHA:
- Flutter / Dart:            (output of `flutter --version`)
- pubspec.lock SHA-256:      (sha256sum pubspec.lock)
- CI run URLs:               verify / security / android / ios
- Devices:                   model, OS version, for each platform
- check_sabotage:            N of N killed
- Coverage:                  overall / core/network / core/session
- Device script (§11.4):     steps 1 to 12, pass or the failing step with a ticket
- Deviations:                any ADR-backed exception added since the last run
```

**`ui_purity` and `ui_stateless`, 2026-11-04.** Compiled and run through `dart analyze` on a
standalone fixture: Dart 3.13.7, analyzer 14.x, on Linux. 12 of 12 expectations fired with none
extra, the ADR suppression silenced its case, and connected components were unaffected.
**Not run:** the reference app, `check_lint_fixture.dart`, or CI. That is why this is an `-rc`.
