# Flutter integration tests

Scope: running the critical Flutter flow on an emulator, simulator, or device with the `integration_test` package, sharing its body with the headless flow test, and wiring flavors in CI. The pattern itself, with the shared `signInRefreshSignOut` function, the scripted backend, and the four-line device entry point, is [`flutter-standards` 12, 7.9 Flow tests, headless and on a device](../../flutter-standards/references/12-testing.md). The CI jobs are [`flutter-standards` 16, 11.2 CI pipeline](../../flutter-standards/references/16-production-and-release.md). This file adds the setup steps, the reasons, and what to check when a device run fails.

## The shape, in one paragraph

The flow is a function that takes a `WidgetTester`. `test/flows/` calls it headless on every PR; `integration_test/` calls it on a device after `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`. Both pump the real `App` with a scripted `HttpClientAdapter` and in-memory secure storage, so the router, guard, interceptor, refresher, and session store all run (7.9). A failure on the device but not headless is therefore a platform difference, not a logic difference, which narrows the search.

## Setup

1. Add the package as a dev dependency from the SDK. The Flutter docs give:

   ```bash
   flutter pub add "dev:integration_test:{sdk: flutter}"
   ```

2. Create `integration_test/` at the project root. Each file there is a test entry point.
3. In the entry point, call `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` before any `testWidgets`. The docs describe it as the binding that runs tests on a device.
4. Import the flow function from `test/flows/`, as 7.9 shows. Do not copy its body; two copies drift.

## Running it

| Target | Command | Notes from the Flutter docs |
| --- | --- | --- |
| Connected Android or iOS device, or a booted emulator or simulator | `flutter test integration_test/app_test.dart` | Check the app was removed after the run; if not, later runs can fail |
| Linux desktop in CI | `flutter test integration_test -d linux` under `xvfb-run` | Without an X server the run fails with a debug connection error |
| Web | `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d chrome` | Needs ChromeDriver running; `-d web-server` runs headless |
| CI, this kit | The `android` and `ios` jobs in 11.2 | Android with `--flavor dev --dart-define-from-file=config/dev.json`; iOS with `--dart-define-from-file` only |

`flutter test --help` on Flutter 3.47.8 states that `--concurrency` is ignored for integration tests, so device runs are serial. Keep the number of device flows small; 7.9 sets the limit (auth plus one business flow, and more than two or three usually means widget tests are missing).

## Scripted backend, never a real server

- The device run uses the same scripted backend as the headless run (7.9). It never calls a real or shared API: the emulator's network is one more source of failure with no bearing on the flow's logic, and a shared server makes the result depend on whose data is there (kit rule, consistent with AGENTS.md rule 10).
- The scripted backend should assert what each request carried, not only what the screen shows. 7.9's flow checks the bearer on each `GET /profile` for that reason.
- What only a real backend can show (server validation, the database guard) is proven on the server (`04-nestjs-e2e-and-db.md`) and the client-server agreement by the contract test (`05-contract-tests.md`).

## Flavors

- Android `productFlavors` (`dev`, `staging`, `prod`) give distinct application ids, so the device job runs the `dev` flavor without touching a `prod` install ([16, 11.1](../../flutter-standards/references/16-production-and-release.md)).
- Config arrives through `--dart-define-from-file=config/<env>.json`, the same file the app build uses, so a flow test never needs its own config path.
- iOS schemes per flavor are added only when iOS needs them; until then the iOS job runs the single scheme (11.1). A device test that needs a flavor-specific iOS behavior is the moment to add the scheme, through the project's contract.

## When the device run fails and headless passes

Check in this order:

1. **Platform channels.** The device run exercises real platform plugins; headless uses fakes. Name the plugin in the report.
2. **Timing.** `pumpAndSettle` waits for frames, not for platform work. A wait that only passes headless is the "time" or "unawaited async" class in `07-flaky-tests.md`.
3. **Leftover app state.** The docs warn that an app left installed after a run can break the next. Uninstall between runs on a shared device.
4. **Environment.** Emulator API level and simulator model are pinned in the CI job (11.2: API 34, the first available iPhone). A failure on a different local device is reported with the device and OS version.

Release-time checks on physical devices are not CI tests; they are the checklist in [16, 11.4](../../flutter-standards/references/16-production-and-release.md).

## Sources

- Flutter documentation, "Check app functionality with an integration test", site reflects Flutter 3.47, page last updated 2026-09-29, read 2026-11-04. https://docs.flutter.dev/testing/integration-tests
- `flutter test --help` output, Flutter 3.47.8 stable, Dart 3.13.7, run locally on 2026-11-04 (command output, no URL of its own).
- Flutter documentation, "Testing Flutter apps" (overview that places integration tests among unit and widget tests), page last updated 2026-05-05, read 2026-11-04. https://docs.flutter.dev/testing/overview
