# Strangler

Scope: replacing a module, service, or feature with a new one behind the existing interface, routing callers from old to new in steps, and removing the old one at the end. The idea is Fowler's "StranglerFigApplication" (see Sources); the steps and gates below are kit rules.

## A strangler that adds anything needs a contract first

A strangler that adds a module, a feature flag, or a route is a design change, not a refactor. It needs an approved `docs/contracts/<feature>.md` before any code (AGENTS.md rule 1; the [`contract-first`](../../contract-first/SKILL.md) skill). hulk stops and reports it to iron-man, naming what would be added.

The contract states at least:

- The interface both implementations satisfy, and the tests that pin it.
- How traffic is routed old to new: a provider swap, a flag, or a route. A flag names its owner, its default, and the date or condition for removing it.
- Whether old and new run side by side, and if they share data, who writes it. Two writers to one table is a data invariant for ant-man.
- The removal step and what proves it is safe.

Only a strangler that swaps one implementation for another behind an interface that already exists, with no new module, flag, or route, is a plain refactor.

## Steps

1. **Pin the interface.** Characterization tests call the module only through its public interface (`01-characterization-tests.md`). They must pass against the old implementation.
2. **Build the new implementation** behind the same interface. Run the same tests against it, unchanged.
3. **Route one caller or one slice** to the new implementation, by the mechanism the contract names. Run the tests on both paths.
4. **Repeat** until no caller uses the old implementation. Each step is reversible by routing back.
5. **Remove the old implementation**, the routing mechanism, and the flag, in one change. Run the full checks (`06-proving-no-change.md`).

## Per stack

| Stack | Interface | Routing mechanism | Swap point |
| --- | --- | --- | --- |
| NestJS | The provider's injection token, or a module's `exports` ([`nestjs-standards` 05, 4.5](../../nestjs-standards/references/05-rules.md)) | Provider registration in the module, or a flag read from validated config | `providers: [{ provide: X, useClass: ... }]` |
| Flutter | The abstract repository in `domain/repository/` ([`flutter-standards` 07](../../flutter-standards/references/07-folder-structure.md)) | The repository provider in the feature's root file, typed by the interface | `<feature>RepositoryProvider` |
| React | The feature's `index.ts` exports ([`react-standards` 04](../../react-standards/references/04-structure.md)) | Which module `index.ts` re-exports, or a flag | `features/<f>/index.ts` |

The swap point is one line in each stack. If routing needs edits at many call sites, the interface is not where callers meet the module; stop and report.

## When it goes wrong

- **Tests need changes to pass against the new implementation.** Behavior differs. Stop; the difference is a finding for iron-man.
- **The old and new paths disagree on data.** Stop routing more slices; report to iron-man and ant-man.
- **The flag outlives its removal date.** Report it; removing it is the contract's last step, not a later cleanup.

## Sources

- Martin Fowler, "StranglerFigApplication", martinfowler.com, version not verified: not read in this session (no network access). Cited for the name and the idea of replacing a system gradually around the old one; the steps above are kit rules. https://martinfowler.com/bliki/StranglerFigApplication.html
- Kit: AGENTS.md rule 1; [`contract-first`](../../contract-first/SKILL.md); `nestjs-standards` 05 (4.5); `flutter-standards` 07; `react-standards` 04.
