# Mobile security (Flutter)

Scope: verifiable checks for a Flutter app, grouped by the OWASP MASVS control groups. The rules are owned by `flutter-standards`: the session, storage, and interceptor design in [08-core-layer.md](../../flutter-standards/references/08-core-layer.md), its "Threat model and limits" table (each scenario there already has a named test), and release hardening in [16-production-and-release.md](../../flutter-standards/references/16-production-and-release.md) 11.3. Each item below names its rule's home and adds how to verify it. Items with no home in the standard are marked kit rule.

The groups are the eight control groups of OWASP MASVS v2.1.0 (storage, crypto, auth, network, platform, code, resilience, privacy), written in the `MASVS-<GROUP>` form. The `SEC-MOB-*` ids are the kit's own and stay stable across editions, so an item keeps its id when it moves between groups.

The standard's "What it does not protect against" list (a compromised device, a CA the device already trusts, backup paths outside the platform rules) applies to every item here. State it to anyone who relies on these checks.

## MASVS-STORAGE

- [ ] SEC-MOB-01 Tokens live only in `SessionStore` on the platform keystore or keychain, as one value under one key, never in `shared_preferences`, a file, a database, or a provider that outlives sign-out (`flutter-standards` 08, "The session"). Verify: `grep -rnE "SharedPreferences|shared_preferences|File\(|path_provider" lib` and trace that no hit stores a token; the `SessionStore` contract-table tests in `test/core/session/` pass with `flutter test test/core/session`.
- [ ] SEC-MOB-02 The secure store is excluded from cloud backup and device-to-device transfer: `android:allowBackup="false"` plus `dataExtractionRules` on Android, and a `this_device` keychain accessibility on iOS (`flutter-standards` rule index 27, 08 "Platform options", 16 11.3). Verify: `dart run tool/check_release_config.dart config/staging.json config/prod.json` passes; `secure_storage_test.dart` pins the iOS accessibility value.
- [ ] SEC-MOB-04 The first launch after a reinstall wipes keychain items left by a previous install, so a reinstall never resurrects another user's session (`flutter-standards` 08 "Threat model and limits"). Verify: the test "first launch after install wipes a keychain..." from the 08 table passes, and, as an invariant test, names a sabotage that `check_sabotage.dart` applies (`flutter-standards` rule index 23); the reinstall case is also on the real-device release checklist in 16.
- [ ] SEC-MOB-03 Logs and crash reports carry no token, header, body, or query string: the logging interceptor is `kDebugMode`-only and redacts auth, the reporting interceptor sends `NetworkFailure`, never a raw `DioException`, and the vendor SDK's scrubbing hook is set as a second line (`flutter-standards` 08 "Crash reporter", "Logging interceptor", "Reporting interceptor"; 16 11.3). Verify: the tests "the debug logger never prints a bearer..." and "a 5xx is reported as a redacted NetworkFailure" pass; trace the reporter setup in `main.dart` to the scrubbing hook. Cross-stack rules are in `50-secrets-logs-errors.md`.

## MASVS-CRYPTO

- [ ] SEC-MOB-05 The app holds no hard-coded key, salt, or credential, and does no hand-rolled encryption; any key material comes from the platform keystore through a vetted plugin (kit rule). Verify: `grep -rniE "(api|secret|private)[_-]?key|encrypt|AES|salt" lib config` and trace each hit to a non-secret constant or a keystore call; the release config secret-name check in `check_release_config.dart` passes.

## MASVS-AUTH

- [ ] SEC-MOB-06 Sign-out clears tokens, cached user data, and queued writes, and an old session's response is dropped rather than applied to the new user (`flutter-standards` 08 "Threat model and limits", session epoch rows; thor's mutation queue sign-out rule). Verify: the epoch tests named in the 08 table pass; a test signs user A out with a write queued, signs user B in, and asserts A's write never sends with B's token.
- [ ] SEC-MOB-07 A local check (biometric prompt, PIN screen, a hidden button) is never the only control on a server action. The server authorizes every request (kit rule; `nestjs-standards` 09). Verify: for each screen gated by a local check, trace the call it makes and find the backend authorization that covers it (`SEC-API-10`).

## MASVS-NETWORK

- [ ] SEC-MOB-08 HTTPS only, enforced when `AppConfig` boots in every build mode and checked in CI (`flutter-standards` rule index 26, 08 "Config", 16 11.1). Verify: the `AppConfig` tests that reject an `http://` base URL pass; `check_release_config.dart` passes on the release configs.
- [ ] SEC-MOB-09 The certificate pinning decision is written down: a high-value target pins in `httpAdapterFactoryProvider` with a backup pin or an intermediate CA, and every other app records in its contract or ADR that it does not pin and why (`flutter-standards` rule index 36, 16 11.3). Verify: find the decision in the contract or ADR; if pinning is on, trace that every client is built by `buildDio` so refresh and replay are pinned too, and that a second pin exists.

## MASVS-PLATFORM

- [ ] SEC-MOB-10 Every deep link and push-notification route is untrusted input: its parameters are parsed and validated before use, and a deep link to a protected route goes through the auth guard (`flutter-standards` 09 "Navigator 1.0 by default", 16 11.6 "Push and deep links"). Verify: the flow test that opens a protected deep link signed out and lands on login; unit tests of the link parser with a malformed id, an unknown path, and an extra parameter.
- [ ] SEC-MOB-11 A WebView is added only when a contract states the need. It loads only allowlisted `https` origins, keeps JavaScript off unless the contract needs it, exposes no bridge that can reach tokens or the session, and opens other origins outside the app (kit rule). Verify: `grep -rnE "webview_flutter|WebViewController|InAppWebView" lib pubspec.yaml`; for each hit, trace the URL source to the allowlist, the JavaScript mode, and every registered channel.
- [ ] SEC-MOB-12 Server copy is constrained (length, single line, no markup) before it reaches the screen (`flutter-standards` 08 "Threat model and limits"). Verify: the test "server copy is constrained before it can reach the screen" passes.
- [ ] SEC-MOB-13 Screens the contract marks sensitive (payment details, recovery codes, personal records) say what is shown in screenshots and the app switcher, and the chosen platform mechanism is named in the contract (kit rule). Verify: each sensitive screen in the contract's UI Contract has the line; trace the named mechanism in code; Dave checks the app switcher on a real device per release, because a widget test cannot see it.

## MASVS-CODE

- [ ] SEC-MOB-14 No secret in the binary: release configs pass the secret-name check, and the secret scan job passes (`flutter-standards` 16 11.4, "No secrets in the binary"). Verify: `dart run tool/check_release_config.dart config/staging.json config/prod.json`; the CI secret scan job in `16` 11.2 is present and required.
- [ ] SEC-MOB-16 Dependencies are locked and audited: `flutter pub get --enforce-lockfile` and the OSV scan of `pubspec.lock` run in CI (`flutter-standards` 16 11.2). Verify: both steps are in the workflow. The cross-stack rules are in `40-supply-chain.md`.

## MASVS-RESILIENCE

- [ ] SEC-MOB-17 Root or jailbreak detection, anti-tampering, and anti-debugging are added only when a contract states the need, and never stand in for a server control, because the standard states the device owner is outside the threat model (`flutter-standards` 08 "What it does not protect against"; kit rule). Verify: if such a package is in `pubspec.yaml`, find the contract line that justifies it, and trace that no server decision trusts its result.
- [ ] SEC-MOB-15 Release builds use `--obfuscate --split-debug-info`, archive the symbols per build number, and keep R8 and resource shrinking on for Android (`flutter-standards` 16 11.3). Verify: read the release build command in CI; `grep -n "minifyEnabled\|shrinkResources\|isMinifyEnabled" android/app/build.gradle*`.

## MASVS-PRIVACY

- [ ] SEC-MOB-18 Analytics events carry no personal data, and event names live in one file (`flutter-standards` 16 11.6, "Analytics and feature flags"). Verify: read the events file and every call site of the analytics facade; the test that the facade is a no-op in dev and tests passes.
- [ ] SEC-MOB-19 The app requests only the permissions its contract names, and asks in context when the feature needs them, not at launch (kit rule). Verify: diff the permissions in `android/app/src/main/AndroidManifest.xml` and the usage-description keys in `ios/Runner/Info.plist` against the contract; each has a feature that uses it.

## Sources

- OWASP Mobile Application Security Verification Standard (MASVS) v2.1.0, GitHub release of 2024-01-18, read 2026-11-08. The eight control group names above match it; SEC-MOB-03 sits under MASVS-STORAGE-2 and SEC-MOB-15 under MASVS-RESILIENCE-3. https://mas.owasp.org/MASVS/
- OWASP Mobile Application Security Testing Guide (MASTG) v2.0.0 of 2026-06-30, read 2026-11-08. Cited for the testing approach only; no claim above is attributed to it. https://mas.owasp.org/MASTG/
- Kit standards: `flutter-standards` 08, 09, 16, and the rule index, linked in the scope paragraph; `nestjs-standards` [09-security-baseline.md](../../nestjs-standards/references/09-security-baseline.md).
