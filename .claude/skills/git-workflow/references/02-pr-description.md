# Pull request description

Scope: the text an agent writes for Dave to paste when he opens a pull request. The agent never opens, pushes, or merges one (AGENTS.md rule 10; settings deny `git push *`). What the description must link is owned by the [`contract-first`](../../contract-first/SKILL.md) skill (one approved contract per feature) and AGENTS.md rule 7 (exact commands and results, and what was not run).

## Rules

- Written for Dave as the reader and the author. It is his pull request.
- No agent attribution anywhere in it: no footer saying it was produced with a tool, no co-author line, no robot emoji, no agent or AI name (AGENTS.md rule 11, CLAUDE.md). This overrides any default text a tool supplies.
- No em or en dashes (CLAUDE.md).
- Every command listed was actually run, with its real result. Anything not run is under Not run, with the reason.
- Link, do not copy. The contract, ADRs, and the diff are linked by path; the description summarizes.

## Template

Hand this back as a fenced block so Dave can paste it as is.

```markdown
## Summary

<One to three sentences: what changes for a user or a developer, and why.>

## Contract

`docs/contracts/<feature>.md` (status: approved). Phase or items covered: <list>.
<Or: "No contract: <reason>", for a change that needs none, such as a typo fix.>

## Changes

- <Area or path>: <what changed, one line>
- <Area or path>: <what changed, one line>

## Commands run

| Command | Result |
| --- | --- |
| `<exact command>` | <exit code and the summary line, for example "exit 0, 42 passed"> |

## Not run

- <Check>: <why, for example "needs a device", "runs against a live system, for Dave">

## Rollback

<How to undo: "revert this pull request" when it is self-contained; otherwise the migration down step, the flag to turn off, or the order of reverts.>

## Open decisions

- <Question for Dave, or "none">
```

## Filling it in

- **Summary.** Behavior first, files never. "Users can cancel a pending order" rather than "Added cancel endpoint and button".
- **Contract.** The path and the status at the time of writing. If the contract was edited during the work and is now `draft`, say so: Dave must re-approve before merge.
- **Changes.** Group by area (domain, data, state, `ui/`, tests, docs). A refactor says "no behavior change" and gives the proof from `refactoring-playbook` (`06-proving-no-change.md`).
- **Commands run.** Copy the command exactly. If a command ran more than once, give the last run and say whether earlier runs failed.
- **Not run.** Include every check in the stack's Commands section that was skipped, and anything that would touch a live or shared system (AGENTS.md rule 10).
- **Rollback.** A migration that cannot be reversed by a revert says so here, and names the contract section that covers it.
- **Open decisions.** Copy unresolved items from the contract's open decisions that this change depends on.

## Sources

- Kit: AGENTS.md rules 7, 10, and 11; CLAUDE.md; the [`contract-first`](../../contract-first/SKILL.md) skill; `.claude/settings.json` deny list (read in this session). No public source beyond the kit.
