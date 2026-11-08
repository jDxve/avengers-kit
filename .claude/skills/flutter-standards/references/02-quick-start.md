## Quick start

**A new app (about an hour).** The reference app (§12.4) is the starter repository: it passes
every check in §11.2 as shipped.

1. Copy it, rename the package in `pubspec.yaml`, and replace `dev.jdxve.reference_app` in `android/app/build.gradle.kts`. Keep `features/auth`; delete `profile` and `orders` when you have your own.
2. Point `config/dev.json`, `staging.json` and `prod.json` at your backend. Staging and prod must be `https`; the release check refuses anything else.
3. Confirm the backend contract the client relies on: authentication runs before any handler, `/auth/refresh` returns 400/401/403 only as a verdict, and writes that carry `Idempotency-Key` are deduplicated (§5).
4. Add each capability with `dart run tool/new_feature.dart <snake_case_name>`. It writes the domain, data, root file, notifier, screen and their tests (§10).
5. Run what CI runs before you push:

```bash
flutter pub get && (cd tool/lints && dart pub get) && (cd tool/lints/fixture && dart pub get)
dart analyze --fatal-infos                 # at the root, no path: the only form that runs the plugins
dart run tool/check_lint_fixture.dart      # the plugins fire, and your app loads them
dart run tool/check_architecture.dart
dart run tool/check_release_config.dart config/staging.json config/prod.json
tool/gen_coverage_helper.sh && flutter test --coverage && dart run tool/check_coverage.dart
dart run tool/check_sabotage.dart
```

6. Turn on branch protection for the four CI jobs (§11.2), then work through the device checks in §11.4 before the first release.

**A three-screen app.** Start in the small-app tier (§2): same `core/`, no `features/` folders yet.
The Rule index says which rules wait until the first feature folder exists.

**A new feature in an existing app.** `dart run tool/new_feature.dart <name>`, then §10 from
step 2.

**Reviewing a PR.** Read the Rule index. Rules enforced by a lint, a script or a test have already
been checked by CI; spend review time on the rows marked *review*.

### What you actually need to read

This document is long because it is also the reference for the parts you touch once: the
interceptor, the session, the release pipeline. Day to day, a feature is built from six
sections. Read these first, and reach for the rest when the problem arrives.

| If you are… | Read | ~Length |
| --- | --- | --- |
| Building a feature | §5 Feature anatomy, §10 Checklist | the core loop |
| Deciding where a file goes | §2 Folder structure | one page |
| Handling a failure | §3 `Result`, `AppException`, `DataState`, §4 `errorToMessage` | one page |
| Writing a notifier | §5 patterns 1 to 3, §6 `watch`/`read`/`listen` | one page |
| Building a screen | §4 Accessibility and Design tokens, §5 four states | one page |
| Writing tests | §7.8 widget tests, §7.10 what to test | one page |

Everything else (the session, the interceptor, the refresher, flavors, CI, the lint plugin)
is read when you are working on that thing, or when a review sends you there. If you are
reading this top to bottom before writing code, stop at §7 and start.

> **This document answers "what and why", not "what I pasted last time".** Every rule that
> costs something says what it costs and what it buys. Where a rule is a default rather than
> an invariant, it says so (ScreenUtil in §4, codegen in §3). Treat a rule with no stated
> reason as a bug in the document.

---

