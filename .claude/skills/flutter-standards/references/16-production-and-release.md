## 11. Production and Release

Everything above is application architecture. This section is the operational layer: the
difference between clean code and a shippable release. Each subsection ends in something a
machine or a named person checks.

### 11.1 Environments and flavors

Config comes from the build, not from a committed constant. Editing source and recompiling to
switch environments means staging and production are different artifacts.

- **Build flavors**: Android `productFlavors` (`dev`, `staging`, `prod`) give distinct application IDs and names, so all three can sit on one device. Names go through `manifestPlaceholders`, not `resValue`: on the current Android Gradle Plugin, `resValue` in a flavor fails the build unless `buildFeatures.resValues` is turned on, which the prod bundle build caught. iOS schemes per flavor are added when iOS needs them; until then the iOS job builds the single scheme with `--dart-define-from-file`.
- **`--dart-define-from-file`**: per-environment JSON supplies values at build time, read by `AppConfig.fromEnvironment()` (§3).
- **Cleartext only in dev.** The dev base URL is `http://` on a LAN, so `android:usesCleartextTraffic="true"` goes in `android/app/src/dev/AndroidManifest.xml`, never in `src/main`. CI checks it.

```json
// config/prod.json  (git-ignored if it carries anything sensitive)
{
  "APP_ENV": "prod",
  "BASE_URL": "https://api.example.com/v1",
  "PUBLIC_SENTRY_DSN": ""
}
```

```bash
flutter build appbundle --flavor prod --dart-define-from-file=config/prod.json \
  --obfuscate --split-debug-info=build/symbols
```

**A dart-define is not a secret store.** Defines are compiled into the binary and are
recoverable from it. They are correct for base URLs, DSNs, public keys, and feature flags. They
are wrong for anything whose disclosure matters: those belong on your server, behind an
authenticated endpoint. Keys that are public by design are prefixed `PUBLIC_`; the release
check below rejects any other key whose name looks like a secret.

```dart
// tool/check_release_config.dart
// Usage: dart run tool/check_release_config.dart config/staging.json config/prod.json
// Fails on a release config that AppConfig would reject at boot, on a define that looks like
// a secret, and on an Android manifest that would leak the session into backups.
import 'dart:convert';
import 'dart:io';

final _secretish = RegExp(
  r'SECRET|PRIVATE|PASSWORD|API_?KEY|TOKEN|CREDENTIAL',
  caseSensitive: false,
);

/// Every SharedPreferences file flutter_secure_storage 11 writes (§3). Re-check on a major bump.
const _secureStorageFiles = [
  'FlutterSecureStorage.xml',
  'FlutterSecureKeyStorage.xml',
  'FlutterSecureStorageConfiguration.xml',
];

void main(List<String> configFiles) {
  final problems = <String>[];

  for (final path in configFiles) {
    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final env = json['APP_ENV'];
    final url = Uri.tryParse('${json['BASE_URL'] ?? ''}');
    if (env != 'staging' && env != 'prod') {
      problems.add('$path: APP_ENV must be staging or prod, got "$env"');
    }
    if (url == null || url.scheme != 'https' || !url.hasAuthority) {
      problems.add('$path: BASE_URL must be an absolute https URL');
    }
    for (final key in json.keys) {
      if (_secretish.hasMatch(key) && !key.startsWith('PUBLIC_')) {
        problems.add('$path: "$key" looks like a secret; defines are readable from the binary');
      }
    }
  }

  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    final xml = manifest.readAsStringSync();
    if (!xml.contains('android:allowBackup="false"')) {
      problems.add('main AndroidManifest: android:allowBackup="false" is required (§3)');
    }
    if (!xml.contains('android:dataExtractionRules="@xml/data_extraction_rules"')) {
      problems.add('main AndroidManifest: dataExtractionRules is required for Android 12+ (§3)');
    }
    if (xml.contains('android:usesCleartextTraffic="true"')) {
      problems.add('main AndroidManifest: cleartext traffic belongs in the dev flavor only');
    }

    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
    final text = rules.existsSync() ? rules.readAsStringSync() : '';
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>([\\s\\S]*?)</$section>').firstMatch(text)?.group(1) ?? '';
      for (final file in _secureStorageFiles) {
        if (!body.contains('path="$file"')) {
          problems.add('data_extraction_rules.xml: <$section> must exclude $file');
        }
      }
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('release config: ok');
    return;
  }
  problems.forEach(stderr.writeln);
  exitCode = 1;
}
```

### 11.2 CI pipeline

The lints and tests only mean something if a machine runs them on every PR, and if the PR
cannot merge when they fail. Configure branch protection on `main` to require the `verify`,
`security`, `android`, and `ios` jobs. A PR must not pass merely because the code compiles.
The maintained templates are `devops-engineering/assets/ci-flutter.yml` and `devops-engineering/assets/release-mobile.yml`; copy from those, and treat this example as an illustration.

```yaml
# .github/workflows/ci.yaml
name: ci
on:
  pull_request:
  push: { branches: [main] }

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  FLUTTER_VERSION: '3.47.8' # §12.3; bumped deliberately, in its own PR

# Supply chain: in the committed file every third-party action is pinned to a full commit
# SHA with the tag in a trailing comment (uses: owner/action@<40-char sha> # v4).
# Actions without a verified SHA use the zero PIN placeholder; replace each before use
# (`devops-engineering` `assets/README.md`). Dependabot proposes SHA updates.
jobs:
  verify:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # Fails on any committed gradle-wrapper.jar, or a homoglyph-named copy, that is not an official
      # Gradle release. min-wrapper-count 0: Flutter's android/.gitignore excludes the jar and
      # flutter_tools injects it from the SDK cache, so a default project has none to check.
      - name: Gradle wrapper jars are official
        uses: gradle/actions/wrapper-validation@0000000000000000000000000000000000000000 # PIN gradle/actions v6.4.1
        with:
          min-wrapper-count: 0
      - uses: subosito/flutter-action@0000000000000000000000000000000000000000 # PIN subosito/flutter-action v2.23.0
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - run: flutter --version # recorded in the log, so a build is reproducible
      - name: Dependencies (app, lint plugin, lint fixture)
        run: |
          flutter pub get --enforce-lockfile
          (cd tool/lints && dart pub get --enforce-lockfile)
          (cd tool/lints/fixture && dart pub get --enforce-lockfile)
      - run: dart format --output=none --set-exit-if-changed lib test tool integration_test

      - name: Generated code is committed and current
        run: |
          dart run build_runner build --delete-conflicting-outputs
          if [ -n "$(git status --porcelain)" ]; then
            git status --porcelain
            echo "::error::Generated output differs from the commit (changed, missing, or hand-edited). Run build_runner and commit the result."
            exit 1
          fi

      # `dart analyze`, at the package root, with no path argument. On Flutter 3.47.8,
      # `flutter analyze` and `dart analyze <subdir>` both skip analyzer plugins silently.
      - name: Analyzer, boundary lints, riverpod_lint
        run: dart analyze --fatal-infos
      - name: Lint plugin package
        working-directory: tool/lints
        run: dart analyze --fatal-infos

      - name: Plugins are alive (fixture + root canary)
        run: dart run tool/check_lint_fixture.dart
      - name: Feature cycles and justified suppressions
        run: dart run tool/check_architecture.dart
      - name: Release configuration
        run: dart run tool/check_release_config.dart config/staging.json config/prod.json

      - name: Tests with coverage
        run: |
          tool/gen_coverage_helper.sh
          flutter test --coverage
      - name: Coverage floors
        run: dart run tool/check_coverage.dart
      - name: Every invariant test fails under its named sabotage
        run: dart run tool/check_sabotage.dart
      - name: Feature template renders, analyzes, and passes its tests
        run: dart run tool/new_feature.dart --check

  security:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    permissions:
      contents: read
      pull-requests: read # gitleaks-action lists the pull request's commits to choose the range
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0, persist-credentials: false } # full history: a secret removed in a later commit is still leaked
      - name: Secrets in history
        uses: gitleaks/gitleaks-action@0000000000000000000000000000000000000000 # PIN gitleaks/gitleaks-action v3.0.0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Comments would need pull-requests: write, and the report artifact would outlive the job.
          GITLEAKS_ENABLE_COMMENTS: 'false'
          GITLEAKS_ENABLE_UPLOAD_ARTIFACT: 'false'
      - name: Known-vulnerable dependencies (OSV, reads pubspec.lock)
        run: |
          go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.7.0
          "$(go env GOPATH)/bin/osv-scanner" scan --lockfile=pubspec.lock

  android:
    runs-on: ubuntu-24.04
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-java@0000000000000000000000000000000000000000 # PIN actions/setup-java v6.2.0
        with: { distribution: temurin, java-version: '21' }
      - uses: subosito/flutter-action@0000000000000000000000000000000000000000 # PIN subosito/flutter-action v2.23.0
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get --enforce-lockfile
      - name: Prod release bundle (obfuscated, symbols split)
        run: |
          flutter build appbundle --flavor prod --release \
            --dart-define-from-file=config/prod.json \
            --obfuscate --split-debug-info=build/symbols
      - name: Enable KVM for the emulator
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm
      - name: Critical flow on an emulator
        uses: reactivecircus/android-emulator-runner@0000000000000000000000000000000000000000 # PIN reactivecircus/android-emulator-runner <version>
        with:
          api-level: 34
          arch: x86_64
          script: flutter test integration_test --flavor dev --dart-define-from-file=config/dev.json

  ios:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: subosito/flutter-action@0000000000000000000000000000000000000000 # PIN subosito/flutter-action v2.23.0
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get --enforce-lockfile
      - name: Release build compiles for device (unsigned)
        run: flutter build ios --release --no-codesign --dart-define-from-file=config/prod.json
      - name: Critical flow on a simulator
        run: |
          UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; print(next(d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name'].startswith('iPhone')))")
          xcrun simctl boot "$UDID"
          flutter test integration_test -d "$UDID" --dart-define-from-file=config/dev.json
```

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: pub
    directory: /
    schedule: { interval: weekly }
    groups:
      minor-and-patch:
        update-types: [minor, patch]
```

**What each step closes.**

- **`dart analyze`, at the root, not `flutter analyze`.** The only command that reported plugin diagnostics in testing (§8). Without it the boundary lints and `riverpod_lint` do not run in CI at all.
- **`check_lint_fixture.dart`.** Proves the rules still fire after an SDK or analyzer move, and that the app's own config loads both plugins. A misspelled plugin path is otherwise silent.
- **`git status --porcelain`, not `git diff --exit-code`.** `git diff` ignores untracked files, so a new `.g.dart` that was never committed would pass. `status` sees changed, deleted, and untracked files.
- **The coverage helper and `check_coverage.dart`.** Without the helper, untested files are absent from `lcov.info` and the overall figure is inflated.
- **`check_sabotage.dart`.** Proves every invariant test can fail. About ninety seconds on the reference app.
- **`new_feature.dart --check`.** Renders the feature template, generates its code, analyzes it with both plugins, and runs its tests. A template that no longer passes the rules would teach every new feature to break them.
- **OSV pinned to `v2.7.0`.** rc.1 shipped a placeholder version (`v2.x.y`), which fails the job as written. A placeholder in a config this document calls "given in full" is a bug.
- **Three pins for reproducibility.** The SDK version, `pubspec.lock` enforced with `--enforce-lockfile` (for the app, the plugin, and the fixture), and `app_lints` by path inside the repo. Miss one and "CI passed" stops being a statement about this commit.

Release builds run on tags in a separate workflow: `flutter build appbundle --flavor prod` and
`flutter build ipa`, both with obfuscation and split debug info; symbol upload to
the crash reporter; signing from the CI secret store; upload to the internal testing track.
The release workflow re-runs `verify` on the tagged commit rather than trusting the PR run.

### 11.3 Release hardening

- **Obfuscation and symbolication**: build with `--obfuscate --split-debug-info=build/symbols`, archive the symbol files per build number, and upload them to the crash reporter so stack traces stay readable. A release whose symbols were not uploaded is a release you cannot debug.
- **Transport security**: HTTPS is enforced at boot (§3) and in CI (§11.1). For a high-value target, add certificate pinning in `httpAdapterFactoryProvider`; because every client is built by `buildDio`, the refresh and replay requests are pinned too. Pin to an intermediate CA or include a backup key alongside the leaf, or a certificate rotation bricks every installed app.
- **Store shrinking**: keep R8 and resource shrinking on for Android release. JSON is code-generated, so there is usually no reflection path to keep.
- **No secrets in logs or reports**: the logging interceptor is `kDebugMode`-only and redacts auth; the reporting interceptor sends `NetworkFailure`, never a raw `DioException`; the vendor SDK's scrubbing hook is configured as a second line.
- **Backup exclusion**: `allowBackup="false"` and `dataExtractionRules` (§3), checked in CI.

### 11.4 Production readiness gates

A release candidate ships when every row has its evidence. "Evidence" means something a person
other than the author can look at: a CI job, a test, a dashboard, a signed-off checklist in the
release ticket.

**Security and privacy**

| Requirement | Acceptance | Evidence |
| --- | --- | --- |
| No secrets in the binary | Release configs pass the secret-name check; no credential in source | `check_release_config`, gitleaks job |
| Sensitive data out of logs and reports | Logging is debug-only and redacted; reports are `NetworkFailure`; SDK scrubbing on | code review of §3 interceptors, one forced error inspected in the dashboard per release |
| Dependency and secret scanning | OSV and gitleaks pass; findings triaged within a week | `security` job |
| Session expiry and sign-out | All six interceptor invariants and the `SessionStore` contract hold | §7.5 and §7.7 suites, integration auth flow |

**Reliability**

| Requirement | Acceptance | Evidence |
| --- | --- | --- |
| Offline and poor network defined | Every data screen shows the offline message with retry; no infinite spinner; nothing logs the user out | widget error-state tests; manual run with network link conditioner on a real device |
| Timeout, retry, cancellation documented | Timeouts as in §3 `AppConfig`; replay policy per ADR-005; cancelled requests never toast | interceptor and notifier tests |
| Crash reporting with alerts | Symbols uploaded; alert on any new fatal issue and on crash-free sessions below the threshold in §11.5 | crash dashboard, alert rule screenshot in the release ticket |
| Critical flows on real devices | Sign-in, the critical business flow, and sign-out on the oldest supported Android and iOS devices you target | release ticket checklist |

**UX and accessibility**

| Requirement | Acceptance | Evidence |
| --- | --- | --- |
| Screen readers and semantics | Every interactive element labeled; logical focus order | accessibility guideline tests; one TalkBack and one VoiceOver pass per release on changed screens |
| Text scaling and contrast | No overflow at 2.0x; AA contrast in both themes | §7.8 tests |
| Loading, empty, error, retry consistent | Four states on every data screen, shared components | widget tests |
| Localization readiness | All copy in `Strings`; dates and numbers through `intl` formatters, never string interpolation | code review; ARB migration plan exists if a second locale is on the roadmap |

**Performance and release**

| Requirement | Acceptance | Evidence |
| --- | --- | --- |
| Startup and scrolling measured | Budgets below, measured in profile mode on the low-end reference device | `integration_test` with `traceAction` timeline summaries, compared release over release |
| Large lists and images | `ListView.builder` for anything unbounded; images decoded at display size (`cacheWidth`/`cacheHeight`) | code review; DevTools memory snapshot on the longest list |
| Android and iOS release builds validated | Prod-flavor builds install and pass the real-device checklist from the internal track | release workflow, store internal track |
| Rollback and incidents documented | §11.5 followed; owner named in the release ticket | release ticket |

**Default budgets** (set your own in ADR form if these do not fit): cold start to first frame
under 2 s at p90 on the low-end reference device; no more than 1% of frames over 16 ms during
the scroll test of the longest list; release APK download size tracked per build, with any
increase over 10% explained in the PR.

**Platform coverage: what each check proves, and where it runs.**

| Check | Android | iOS | Where |
| --- | --- | --- | --- |
| Dart logic, interceptor, session contract, widgets, the critical flow headless | covered | covered | `verify` (Linux; platform-independent Dart) |
| Prod release bundle compiles, obfuscates, splits symbols | automated | n/a | `android` job |
| Release build compiles for device, unsigned | n/a | automated | `ios` job |
| Critical flow through real platform channels | emulator, API 34 | simulator | `android` / `ios` jobs |
| Backup exclusion of the secure store | file check in CI | n/a (`this_device` accessibility, pinned by a test) | `verify` |
| Keystore and Keychain behavior: first unlock after reboot, reinstall wipe, upgrade from a 1.x install | real device | real device | release checklist |
| Signing, store upload, crash symbol upload | release workflow | release workflow | tags only |

The emulator and simulator prove the app talks to the platform; they cannot prove Keystore or
Keychain edge cases, which differ by device and OS version. Those rows stay manual, on the
oldest supported device of each platform, and are ticked in the release ticket.

**The physical-device session script.** Run on one Android and one iOS device per release, each
the oldest supported model, against staging. Shorten the staging access-token lifetime to a
minute for the run. Every step has an expected result; anything else is a release blocker.

| # | Do | Expect |
| --- | --- | --- |
| 1 | Fresh install, sign in with "remember me", kill the app, relaunch | Signed in, no login screen |
| 2 | Wait past the access-token lifetime, open a data screen | Data loads; staging logs show one `/auth/refresh` |
| 3 | Same, with three screens' requests firing at once | Still exactly one refresh |
| 4 | Turn on airplane mode, wait past expiry, open a screen | "You appear to be offline." Still signed in when the network returns |
| 5 | Revoke the refresh token on the server, open a screen | Signed out once, one "session expired" message, login screen once |
| 6 | Throttle the network (Network Link Conditioner, or an emulator's slow profile), start a load as user A, sign out and sign in as user B before it returns | B never sees A's data; staging logs show no request from A's session carrying B's token |
| 7 | Throttle, let a refresh start, swipe the app away mid-request, relaunch | Signed in or cleanly signed out; never stuck on a blank screen |
| 8 | Sign in, reboot, let a background launch happen before unlocking (iOS: a push), then unlock | Still signed in |
| 9 | iOS: sign in, uninstall, reinstall | Signed out |
| 10 | Install the previous release, sign in, upgrade to this build | Still signed in (the 1.x key migration on the first upgrade) |
| 11 | Android: transfer to a second device with the platform's device-to-device tool | Opens signed out, no crash, no "failed to unwrap key" in logcat |
| 12 | Place an order on a throttled network and tap twice | One order on the server |

### 11.5 Rollout, rollback, and incidents

**Staged rollout.** Android: staged rollout on Play at 5%, then 20%, 50%, 100%, with at least
24 hours and a dashboard check between steps. iOS: phased release on the App Store.

**Halt criteria.** Pause the rollout when any of these holds for the new version compared with
the previous one: crash-free sessions below 99.5%; a new fatal issue affecting more than a
handful of users; sign-in success rate drops; a spike in `unauthorized` errors (the signature of
a broken refresh). The thresholds are defaults; record yours.

**Rollback.** A mobile release cannot be un-installed, so "rollback" means three things, decided
in advance:

- **Halt** the staged rollout (Play) or pause phased release (App Store). This limits blast radius; it does not fix installed devices.
- **Remote kill switches** for risky features, read from a remote-config provider injected like any other `Provider`, so a feature can be turned off without a release.
- **Minimum supported version.** The app checks a server-provided minimum version at launch and shows a blocking update screen below it. This is the only way to retire a build with a security bug. It ships *before* you need it.

Then ship a fix forward as a new build number. Never re-upload the old artifact as a "rollback".

**Incident procedure.** One named owner per release. When a halt criterion fires: halt the
rollout, open an incident note with the timeline, decide between kill switch, fix-forward, or
forced update, and communicate in the channel the team agreed. Within a week, write a
blameless postmortem; any rule change it produces goes into this playbook through §12.

### 11.6 When the requirement arrives

None of these are mandatory until their trigger is true. When it is, the minimum below becomes a
rule for that app, with the evidence in the last column. Each one bolts onto an existing seam (a
provider, a source behind a repository, a component), never a rewrite.

| Concern | Trigger | Minimum rules | Verified by |
| --- | --- | --- | --- |
| **Pagination** | a list the server pages, or one that can exceed about 100 items | Cursor-based where the API allows it. The notifier state holds items, cursor, `hasMore`, and a separate `DataState` for the next page, so a failed page keeps the items already shown. `ListView.builder`; the next page loads near the end, not at it; one request in flight per list | notifier tests: first page, next page, next-page failure keeps items, refresh resets the cursor |
| **Offline and sync** | users must read or write without a network | `drift` or `isar` behind the repository, which stays the single source of truth and returns local data first. Writes go to an outbox with idempotency keys (§5). A schema migration test per version | repository tests offline and online; migration tests; device script step 4 extended to writes |
| **Caching and invalidation** | data reused across screens or sessions | Every cache has a TTL and an owner (one repository). Cache keys include the user id, or the cache is rebuilt per session (as `profileRepositoryProvider` is). Mutations invalidate what they change; pull-to-refresh passes `forceRefresh`. Stale-while-revalidate only where showing stale data is acceptable | repository tests for hit, bypass, expiry, and invalidation after a mutation |
| **Localization** | a second locale | ARB or `slang`; `Strings` retired. Dates, numbers and currency through `intl`, never interpolation. Plurals through ICU. Right-to-left checked if any locale needs it | a widget test per screen in the longest locale at 2.0x text; a pseudo-locale run |
| **Accessibility audit** | before the first public release, then yearly | Beyond the widget-test guidelines: a full TalkBack and VoiceOver pass of every flow, focus order, announcements for async results, no information carried by color alone | the audit checklist in the release ticket, with issues tracked like bugs |
| **Performance** | before the first release; again when a screen feels slow | Profile mode on the low-end reference device. Budgets from §11.4. Images decoded at display size; no work in `build` that belongs in a notifier; `const` widgets; `RepaintBoundary` only where DevTools shows it helps | `integration_test` timeline summaries compared release over release; a DevTools memory snapshot of the longest list |
| **Crash-free monitoring** | the first production release | Crash reporter with symbols uploaded per build (§11.3). Alerts on any new fatal issue and on crash-free sessions below 99.5% for the current version. Rollout halts on those signals (§11.5) | the alert rules, linked in the release ticket |
| **Analytics and feature flags** | product measurement or gradual rollout | An analytics facade and a remote-config provider, injected like any other `Provider`. No personal data in events; event names in one file | a test that the facade is a no-op in dev and tests |
| **Push and deep links** | re-engagement or URL entry points | FCM/APNs; `go_router` (§4 trigger). A deep link to a protected route goes through the guard | a flow test that opens a deep link signed out and lands on login |
| **State restoration** | users lose work to process death mid-flow | `RestorationMixin` on the few flows that warrant it | an Android "don't keep activities" run of that flow |
| **Background work** | work that continues past app exit | `workmanager` behind a domain-level scheduler contract; tasks idempotent and resumable | unit tests of the task body; a device run with the app killed |

