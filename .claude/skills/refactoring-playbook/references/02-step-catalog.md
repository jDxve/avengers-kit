# Step catalog

Scope: each refactoring step in full, per stack, with the precondition that makes it safe, the single edit, and the check to run before the next step. The SKILL.md table is the short form. Larger moves (`ui/` extraction, service splits, cycles, strangler) have their own files and are only indexed here.

The step names are the common names for these moves. Fowler's *Refactoring* catalog is the usual reference for them; it was not read in this session, so nothing below is attributed to it.

## How a step runs

1. State the step in one line before editing ("Extract `calculateTotal` from `OrdersService.place`").
2. Check the precondition. If it fails, the step is not safe yet: pin more behavior first (`01-characterization-tests.md`) or pick a smaller step.
3. Make the one edit. Prefer the analyzer's or language server's automated refactor over a hand edit, because it updates every reference.
4. Run the check in the row. Green means the next step; red means revert the step, not patch forward (kit rule).

The checks per stack are the stack's own commands: [`flutter-standards`](../../flutter-standards/SKILL.md) Commands, [`react-standards`](../../react-standards/SKILL.md) Commands, and the CI gate in [`nestjs-standards` 11](../../nestjs-standards/references/11-enforcing-this-automatically.md). `06-proving-no-change.md` lists them in one place.

## Move

| Stack | Precondition | Step | Watch for |
| --- | --- | --- | --- |
| Flutter | Destination folder is legal for the file's layer ([`flutter-standards` 07](../../flutter-standards/references/07-folder-structure.md)) | Move the file, fix imports | A move into another feature's `data/` or `presentation/` breaks `no_cross_feature_imports` |
| React | Destination is inside the same feature, or the export goes through the feature's `index.ts` ([`react-standards` 04](../../react-standards/references/04-structure.md)) | Move the file, fix imports | Deep imports into another feature fail the boundary check |
| NestJS | Destination module already imports what the file needs, through `exports` ([`nestjs-standards` 05, 4.5](../../nestjs-standards/references/05-rules.md)) | Move the file and its provider registration | `no-deep-module-reach` in 11; a provider registered in two modules |

## Rename

- Precondition: no caller outside the repo depends on the name. A route path, a DTO field, an error `code`, a public package export, a stored key, or a persisted enum value is a contract, not a name. Renaming one is a contract change for iron-man.
- Step: one rename through the analyzer (Dart) or the TypeScript language server, nothing else in the same step.
- Check: analyze or typecheck, tests; for NestJS also `npm run openapi:check`, which fails if a renamed DTO property leaked into the spec.

## Extract function

- Precondition: you can name every input and output of the block. A block that reads `this` state, a Riverpod `ref`, or a React hook result passes those in as parameters, or it is not ready to extract.
- Step: a new private function in the same file, called from the original site. Making it public or moving it is a later, separate step.
- Check: tests. The extracted function needs no new test if the existing ones cover the call site; a new test for it is hawkeye's call.
- NestJS: extract inside the service, never into a controller, guard, or interceptor ([05, 4.2](../../nestjs-standards/references/05-rules.md): business logic lives in services).

## Inline

- Precondition: the function has one meaning, every caller is inside the module or feature, and it is not part of a public surface.
- Step: replace each call with the body, then delete the function.
- Check: tests. A facade method that only forwards one call is a candidate ([05, 4.2](../../nestjs-standards/references/05-rules.md): such a facade is deleted).

## Extract widget or component

- Precondition: the subtree reads only values the parent can pass. If it reads state, data, or navigation, this is a `ui/` extraction instead (`03-extract-ui.md`).
- Flutter: a new `StatelessWidget` class in the same feature's `presentation/` folder for its role ([`ui-isolation`](../../ui-isolation/SKILL.md), Three roles). Whether the repo prefers classes over private builder methods is the repo's convention; follow it.
- React: a new component in the same feature, props typed, no new hook calls.
- Check: the widget or component tests for the screen still pass; analyze or typecheck.

## Larger moves

| Move | File |
| --- | --- |
| Pure `ui/` out of a connected widget or component | `03-extract-ui.md` |
| Split a NestJS service, break a module or feature cycle | `04-split-services-and-cycles.md` |
| Replace a module behind its interface | `05-strangler.md` |

## What is not a refactoring step

Each of these changes behavior or a contract, so hulk stops and reports it (hulk, Rules):

- Changing a default value, a sort order, an error code, or a message a user sees.
- Adding or removing a dependency or a package.
- Changing a public signature that callers outside the module use.
- "Fixing" an oddity a characterization test pinned.

## Sources

- Martin Fowler, *Refactoring: Improving the Design of Existing Code*, 2nd edition, edition not verified: not read in this session (no network access). Cited only as the usual reference for these step names; no content is attributed to it.
- Kit: hulk agent file ([`hulk.md`](../../../agents/hulk.md)); `nestjs-standards` 05 (4.2, 4.5) and 11; `react-standards` 04; `flutter-standards` 07; `ui-isolation`.
