# ADR-013: Project lessons reach the kit through per-project branches and curated merges

- Status: proposed
- Date: 2026-11-04
- Revisit when: the number of active projects makes per-branch curation slow, or the kit's visibility (private or public) changes
- Contract: `docs/contracts/kit-learning-loop.md`

## Context

Each project copies the kit's `.claude/`, `scripts/`, `.github/`, `AGENTS.md`, `CLAUDE.md`, and `docs/` and keeps the copy. Skills and agent rules improve inside projects, and those improvements are lost unless they come back. A lesson learned in one project is often partly project-specific, and the kit may be public, so a lesson cannot go straight to `main`. Once a project's history or name lands in the kit's `main`, removing it needs a history rewrite, which is why this is recorded.

## Decision

1. Each project has a long-lived branch `project/<name>` in the kit repo. The project's clone of the kit (`<project>/avenger-kit/`, gitignored) stays on it.
2. A lesson starts as a draft proposal in the project. Dave approves it. The change goes into the project's `.claude/` first, then `scripts/sync-to-kit.sh` (run by Dave) copies changed skill and agent files to the clone, leak-scans the added lines, and commits locally on the project branch with no agent attribution. Dave pushes.
3. A project branch is never merged into `main`. Curation re-applies only the changes Dave chose on a `curate/<date>` branch cut from `main`, with project detail removed where needed, and goes through a PR Dave opens and merges.
4. Other projects take kit `main` through `scripts/pull-from-kit.sh`, file by file, with Dave confirming each and no customised file overwritten silently.
5. `.claude/KIT_VERSION` records the kit commit each copy was last reconciled with, so the scripts can tell a local change from a kit change.

## Alternatives considered

- **Pull requests from each project straight to `main`.** Rejected: a PR carries the project's commits and wording, and a single review is the only thing between project detail and a possibly public `main`.
- **Merging project branches into `main` after review.** Rejected: a merge brings every commit in the branch's history, including project-specific ones, and cannot be partly undone.
- **One shared `lessons` branch for all projects.** Rejected: lessons from different projects interleave, the source of each change is lost, and a leak from one project blocks all of them.
- **Kit as a submodule, subtree, or package in each project.** Rejected by Dave's copy-per-project decision. It would also make every project take every kit change at once.
- **No base record, two-way diff only.** Rejected: without `KIT_VERSION`, sync cannot tell a project edit from a kit update the project has not pulled, and would revert kit changes on the project branch.

## Consequences

- Easier: each project's lessons stay isolated and traceable to their branch. `main` only ever receives reviewed, generalised text.
- Easier: a leak or bad lesson stays on one project branch, which Dave can delete or rewrite without touching `main`.
- Harder: curation is manual work for iron-man, black-widow, and Dave, and grows with the number of projects.
- Harder: after a curated change lands, the project that produced it sees its own version and the generalised one as a conflict on the next pull, until Dave resolves it.
- Harder: if project branches are pushed to a public kit, their names are public. Decided under the contract's open decisions, not here.
