# ADR-011: Flutter state management: Riverpod by default

- Status: accepted
- Date: 2026-11-04
- Revisit when: Riverpod's major version changes its state model

## Context

Dave's decision: Riverpod is the official default for Flutter state management. Another library, such as GetX, may be used when a project genuinely needs it.

The playbook is written for Riverpod: the provider graph, the feature root file wiring (ADR-009), the notifier patterns, `riverpod_lint` and its canary, `pumpApp`, the feature template, and the reference app.

## Decision

1. New Flutter work uses Riverpod (`flutter_riverpod`) unless there is a stated need for something else.
2. Another library, such as GetX, Bloc, or Provider, is allowed when the contract or a project ADR names the need and why Riverpod does not meet it. Dave approves it there. Agents do not add one on their own.
3. Two libraries never hold the same state.
4. A repo already built on another library keeps it. Say so, and do not migrate it unless asked.
5. `ui/` folders stay pure whichever library is used: no Riverpod, GetX, or other state or navigation library. Use another library's UI helpers from `screens/` or `components/`, and pass values and callbacks into `ui/`.
6. `flutter_hooks` and `hooks_riverpod` are allowed when needed. A `ui/` widget may use hooks only for purely visual local state under ADR-010, after `flutter_hooks` is added to the `ui_purity` allowlist. `hooks_riverpod`, `HookConsumerWidget`, and `ref` stay out of `ui/`.

## Enforcement

| Invariant | Enforced by |
| --- | --- |
| `ui/` imports no state library | `ui_purity` (allowlist) |
| Riverpod misuse in notifiers | `riverpod_lint` and its canary |
| Another library has a stated need | Review of the contract and `pubspec.yaml` |

## Consequences

- Easier: one documented default, with the lints, tests, template, and reference app built for it.
- Harder: a project using another library has no playbook templates or lints for it, so that project must write its own.
