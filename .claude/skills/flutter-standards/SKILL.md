---
name: flutter-standards
description: Dave's Flutter production playbook (My Flutter Way). Use when writing, reviewing, or planning Flutter or Dart code, including features, notifiers, repositories, session and networking code, lints, and tests.
paths:
  - "lib/**/*.dart"
  - "test/**/*.dart"
  - "pubspec.yaml"
---

# Flutter standards

The repo's established convention beats this playbook. When they differ, follow the repo and say so.

## Rules that never bend

- `presentation -> domain <- data`. A feature's `presentation/` and `data/` meet only at `domain/`.
- Another feature is reachable only through its `domain/` and root file. `core/` and `common/` never import a feature.
- State management defaults to Riverpod. Another library such as GetX needs a stated need that Dave approves in the contract or an ADR. Two libraries never hold the same state, and `ui/` stays pure either way.
- Repositories return `Result<T>`. Only notifiers hold `DataState<T>`.
- An `AppException` becomes copy only in `errorToMessage`.
- Only `SessionStore` touches credentials. Only a server verdict ends a session.
- Nothing is replayed unless sending it twice is safe. Non-idempotent writes carry one `Idempotency-Key` per user intent.
- `if (!ref.mounted) return;` after every `await` in a notifier.
- Every data screen renders loading, success, empty, and error with retry.
- All copy in `Strings`. Colors, spacing, radii, type, and motion through tokens.
- Screens orchestrate, components connect state, `ui/` only renders. See `ui-isolation`.
- An architecture suppression cites an ADR on the line above.

## Read only what the task needs

| Task | Read in `references/` |
| --- | --- |
| Every rule and its enforcer, or a PR review | `03-rule-index.md` |
| New feature | `15-new-feature-checklist.md`, `10-feature-anatomy-worked-example-auth.md` |
| Where a file goes | `07-folder-structure.md` |
| Stack, state library, hooks | `04-stack.md` |
| `Result`, `DataState`, session, auth interceptor, refresh | `08-core-layer.md`. It is long, so search it |
| Theme, tokens, accessibility, routing, error copy | `09-common-layer.md` |
| Notifier patterns, `watch` / `read` / `listen` | `11-state-management-with-riverpod.md` |
| Tests | `12-testing.md`. Search for the section you need |
| Lints, fixtures, architecture script | `13-tooling-and-enforcement.md` |
| Naming | `14-naming-and-file-conventions.md` |
| CI, flavors, release gates, offline and pagination triggers | `16-production-and-release.md` |
| ADRs, exceptions, dependency policy, changelog | `17-governance.md` |

## Commands

```bash
dart run tool/new_feature.dart <snake_case_name>
dart analyze --fatal-infos                 # at the package root, with no path, or plugins do not run
dart run tool/check_architecture.dart
flutter test
```
