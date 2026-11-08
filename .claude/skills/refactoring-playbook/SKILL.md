---
name: refactoring-playbook
description: Behavior-preserving refactoring for Flutter, React, and NestJS. Characterization tests first, one small step at a time, extract a widget, component, or function, extract pure ui/ from a connected widget, split a large service, break a dependency cycle, the strangler pattern for replacing a module, and how to prove nothing changed. Use when refactoring, untangling dependencies, splitting large files, or extracting ui/ widgets.
---

# Refactoring playbook

How to restructure code so that nothing it does changes, and how to show that. The rules live in hulk's agent file and the stack standards; this skill links them and adds the step catalog and the proof. The repo's established structure beats this skill, and you say so when they differ. Except the fixed stack choices (Drizzle and Zod), which repo convention never overrides; a repo that differs is flagged for migration, not refactored toward them as a side effect.

## Baseline first

Run the tests for the target and report the result before the first edit (hulk, Method step 1). If no test pins the behavior you are about to move, stop and ask for hawkeye to add characterization tests. `01-characterization-tests.md` says what to pin; the `testing-strategy` skill says at which level.

## Rules that never bend

- No behavior, public API, or contract change. If the refactor needs one, stop and report it as a design question for iron-man. Owner: hulk, Rules.
- Tests stay as they are, apart from import paths. A test that needs a logic change means behavior changed, so stop. Owners: hulk, Rules; AGENTS.md rule 9.
- No abstraction for a future need. A refactor usually leaves less code, or the same code in clearer places. Owners: hulk, Rules; AGENTS.md rule 5.
- One step, then the check. Never two steps between test runs (hulk, Method step 2).
- The NestJS module graph stays acyclic and `forwardRef` between domain modules stays forbidden. Owner: [`nestjs-standards` 05, 4.5](../nestjs-standards/references/05-rules.md); enforced by `no-circular` in [11](../nestjs-standards/references/11-enforcing-this-automatically.md).
- A cross-feature cycle in Flutter or React is broken through the other feature's public surface, never a deep import. Flutter: its `domain/` and root file `features/<f>/<f>.dart` ([`flutter-standards` 06](../flutter-standards/references/06-architecture-philosophy.md), `no_cross_feature_imports`, `check_architecture.dart`). React: its `index.ts` ([`react-standards` 04](../react-standards/references/04-structure.md), `no-circular` in [11.1](../react-standards/references/12-enforcing-this-automatically.md)).

## Step catalog

Each row is one step. Detail per stack in `02-step-catalog.md`.

| Step | Precondition | The single step | Check after |
| --- | --- | --- | --- |
| Move | Target tests green | Move the file, update imports only | Analyze or typecheck, boundaries, tests |
| Rename | No caller outside the repo depends on the name | Rename with the analyzer or language server, no other edit | Same, plus OpenAPI export identical |
| Extract function | You can name every input and output | New private function, call it from the old site | Tests |
| Inline | One meaning, no caller outside the module | Replace calls with the body, delete the function | Tests |
| Extract widget or component | The subtree reads no state the parent does not pass | New widget or component in the same feature | Widget or component tests |
| Extract `ui/` | Rendering is mixed with state, data, or navigation | `03-extract-ui.md` | `ui/` lint and boundaries, tests |
| Split service | Operations differ in rules, collaborators, or reasons to change | `04-split-services-and-cycles.md` | Tests, OpenAPI export identical |
| Break cycle | The cycle check names it | `04-split-services-and-cycles.md` | Cycle check green |
| Strangler | Approved contract if it adds a module, flag, or route | `05-strangler.md` | Tests on both paths |

## Proof of no change

Detail and commands per stack: `06-proving-no-change.md`.

1. The same tests pass before and after, run with the same command.
2. Backend: the exported OpenAPI document is identical (`npm run openapi:check`).
3. Web: the generated API types are identical (`npm run api:check`).
4. `ui/` lint and boundary checks are green.
5. Net lines changed are reported.

## Read only what the task needs

| Task | Read in `references/` |
| --- | --- |
| Nothing pins the behavior yet | `01-characterization-tests.md` |
| A move, rename, extract, or inline step in a given stack | `02-step-catalog.md` |
| Pull rendering out of a connected widget or component | `03-extract-ui.md` |
| A large NestJS service, a module cycle, a feature cycle | `04-split-services-and-cycles.md` |
| Replace a module behind its interface | `05-strangler.md` |
| Show that nothing changed, with commands | `06-proving-no-change.md` |
| Which characterization tests and at what level | the `testing-strategy` skill |

## Report

hulk's Report section is the format. The proof list above fills its "final result" line:

```text
Baseline: <command>, <n> passed
Steps: <one line per step, with the check run after it>
Final: <same command>, <n> passed; openapi:check | api:check | ui/ lint: <result or n/a>
Net lines: +<a> -<b>
Public API or dependency change: none
```
