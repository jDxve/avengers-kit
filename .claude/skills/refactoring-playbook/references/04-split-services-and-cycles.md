# Split services and break cycles

Scope: splitting a large NestJS service, breaking a NestJS module cycle, and breaking a cross-feature cycle in Flutter or React, each without a behavior change. When to split and which ways out of a cycle are allowed are owned by [`nestjs-standards` 05, 4.2 and 4.5](../../nestjs-standards/references/05-rules.md), [`flutter-standards` 06](../../flutter-standards/references/06-architecture-philosophy.md) and [07](../../flutter-standards/references/07-folder-structure.md), and [`react-standards` 04](../../react-standards/references/04-structure.md) and [11.1](../../react-standards/references/12-enforcing-this-automatically.md). This file adds the order of steps.

## Should this service split at all

`nestjs-standards` 4.2 makes size a review trigger, not a rule: a service past about 300 lines or about 8 public methods gets a cohesion check, and it splits only when its operations differ in business rules, collaborators, testing needs, or reasons to change. If none of those holds, report "cohesive, no split" and stop. Splitting by entity name alone is not a reason.

## Split a NestJS service

1. **Pin.** Every endpoint the service backs has an e2e test on a real database (`01-characterization-tests.md`). Record the baseline and `npm run openapi:check`.
2. **Group.** List the public methods and, for each, its collaborators and the rule it applies. Write the proposed groups in the report before moving code. A group that needs a transaction across two groups is a sign they belong together.
3. **Create the new service** in the same module, empty, registered as a provider. Run the tests.
4. **Move one method** and its private helpers. The old service injects the new one and delegates that method, so controllers do not change yet. Run the tests.
5. **Repeat step 4** per method in the group.
6. **Point callers at the new service** one controller or caller at a time, then delete the delegating method. A facade that only forwards is deleted (4.2). Run the tests after each caller.
7. **Check.** Tests green with the same command, `openapi:check` identical, dependency check green.

Constraints that make a split a design question for iron-man, not a refactor:

- The new service belongs in a different module. That changes module `exports`, which is a public surface.
- A transaction that spanned both groups would have to span two services. Keeping it correct may need a facade that owns the transaction (4.2 allows that one); if the shape is unclear, stop and ask.

## Break a NestJS module cycle

`forwardRef` between domain modules is forbidden (4.5), so the cycle is fixed, not hidden. 4.5 names three ways out:

| Way out | Use when | Refactor or design change |
| --- | --- | --- |
| Move the shared concept into the module that owns it | One side reaches across only for something that is really the other side's | Refactor, if no endpoint or `exports` entry changes |
| Extract a third module both depend on | Both sides use a concept neither owns | Design change: a new module is a new public surface. Contract first |
| Invert one direction into a domain event | The caller does not need to wait for the result | Design change: timing and failure handling differ. Contract first |

Steps for the first way: find the cycle with the check in [`nestjs-standards` 11](../../nestjs-standards/references/11-enforcing-this-automatically.md) (`npx dependency-cruiser src --validate` or `npx madge --circular --extensions ts src`), move the one provider or function, update imports, re-run the check and the tests.

## Break a Flutter feature cycle

A feature may import another feature's `domain/` and root file only (`no_cross_feature_imports`), and `dart run tool/check_architecture.dart` reports feature cycles ([`flutter-standards` 13](../../flutter-standards/references/13-tooling-and-enforcement.md), rule index 2 and 5).

1. Read the cycle the check prints (`feature cycle: a -> b -> a`).
2. For each edge, find what is imported. A type that both sides need usually belongs in one side's `domain/`, or in `common/models/` if it is a tiny cross-feature value type ([07](../../flutter-standards/references/07-folder-structure.md)).
3. Move it, so one edge disappears. Re-export it from the owner's root file if other features use it.
4. Run `dart analyze --fatal-infos`, `dart run tool/check_architecture.dart`, and `flutter test`.

## Break a React feature cycle

`no-circular` in [11.1](../../react-standards/references/12-enforcing-this-automatically.md) names the cycle. Imports between features go through `features/x` and its `index.ts`, never a deep path ([04](../../react-standards/references/04-structure.md)).

1. Read the cycle from `npm run boundaries`.
2. Move the shared piece to the feature that owns it, or to a shared folder the standard allows, and export it through that feature's `index.ts`.
3. Replace deep imports with the public import in the same step.
4. Run `npm run typecheck && npm run lint && npm run boundaries && npm test`.

Exporting a symbol from `index.ts` that was private before widens the public surface. That is allowed in a refactor only when it is the smallest way to break the cycle, and the report names it.

## Sources

- Martin Fowler, *Refactoring: Improving the Design of Existing Code*, 2nd edition, edition not verified: not read in this session (no network access). Cited as background for moving behavior in small steps; the steps above are kit rules built on the standards linked in the scope.
- Kit: `nestjs-standards` 05 (4.2, 4.5) and 11; `flutter-standards` 03, 06, 07, 13; `react-standards` 04 and 12 (11.1).
