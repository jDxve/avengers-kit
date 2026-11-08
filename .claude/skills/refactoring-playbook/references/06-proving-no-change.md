# Proving no change

Scope: the evidence a refactor report carries to show behavior did not change, with the commands per stack. The commands are owned by each stack standard's Commands section or CI gate; this file collects them and says what each one proves. Never claim a check passed unless you ran it, and list what you did not run (AGENTS.md rule 7).

## The proof list

| # | Evidence | Proves | Fails when |
| --- | --- | --- | --- |
| 1 | The same tests pass before and after, with the same command and the same count | Pinned behavior is unchanged | A test fails, or the count drops (a test was deleted or skipped) |
| 2 | Backend: exported OpenAPI identical | No endpoint, DTO, or error shape moved | A renamed property or route leaked into the spec |
| 3 | Web: generated API types identical | The web client's view of the API is unchanged | The schema changed under the refactor |
| 4 | `ui/` lint and boundaries green | The extraction left `ui/` pure and features decoupled | A `ui/` file imports state, data, or navigation; a new cycle |
| 5 | Net lines reported | The refactor did not grow the code for no reason (hulk, Rules) | Not a pass or fail; a large growth needs a sentence of why |

Tests unchanged, apart from import paths, is a precondition of item 1 (hulk, Rules). `git diff --stat -- '<test paths>'` shows any test file touched; read each hunk and confirm it is imports only.

## Commands per stack

Flutter, from [`flutter-standards`](../../flutter-standards/SKILL.md) Commands:

```bash
dart analyze --fatal-infos            # at the package root, with no path
dart run tool/check_architecture.dart # feature cycles, ui_purity, ui_stateless if installed
flutter test
```

React and Next.js, from [`react-standards`](../../react-standards/SKILL.md) Commands and [12, 11.4 and 11.6](../../react-standards/references/12-enforcing-this-automatically.md):

```bash
npm run typecheck && npm run lint && npm run boundaries && npm test && npm run build
npm run api:check                     # generated types match the pinned schema
```

NestJS, from the CI gate in [`nestjs-standards` 11](../../nestjs-standards/references/11-enforcing-this-automatically.md):

```bash
npx tsc --noEmit
npm run lint
npx dependency-cruiser src --validate
npm test
npm run test:e2e                      # against a disposable local database, never a shared one
npm run openapi:check                 # generated spec matches the committed one
```

Net lines, any stack:

```bash
git diff --shortstat <base>...HEAD    # or --shortstat on the working tree before a commit
```

If a project lacks one of these scripts, report "not available in this repo" for that item rather than substituting a different check. Adding the script is not part of a refactor.

## Reading the result honestly

- A green run after a red run with no code change is flaky, not green. Report it per the `testing-strategy` flaky-test policy.
- A pass that ran zero tests or walked zero modules is not a pass. `react-standards` 11.1 explains the dependency-cruiser zero-module case; check the counts.
- `openapi:check` and `api:check` compare against committed files. If the refactor regenerated and committed them, the check proves nothing; the diff of the committed file is the evidence, and it must be empty.

## Sources

- Kit: the Commands sections of [`flutter-standards`](../../flutter-standards/SKILL.md) and [`react-standards`](../../react-standards/SKILL.md); `react-standards` 12 (11.1, 11.4, 11.6); `nestjs-standards` 11 CI gate; hulk agent file ([`hulk.md`](../../../agents/hulk.md)), Rules and Report; AGENTS.md rule 7. No public source beyond the kit.
