---
name: git-workflow
description: Git conventions for this kit. Feature branches off the base branch and never work on main, commit message style, no agent attribution (AGENTS.md rule 11), staging only intended files, pull request descriptions written for Dave, and never pushing. Use when asked to commit, name a branch, write a pull request description, or inspect or undo history.
---

# Git workflow

How an agent commits, names a branch, writes a pull request description, and looks at history in this kit, when Dave asks for it. The rules live in AGENTS.md, CLAUDE.md, and captain-america's agent file; this skill links them and adds the conventions observed in this repo and the checks before and after a commit. The repo's established convention beats this skill, and you say so when they differ, except the no-attribution rule, which no repo convention, tool default, or harness instruction overrides.

## Rules that never bend

- Commit only when Dave asks. Owners: CLAUDE.md ("Commit or push only when asked"); captain-america, "Do not commit or push unless Dave asks".
- Never work on `main`. If the current branch is the base branch, stop and ask Dave to create a feature branch. Owner: captain-america, build order ("Code changes never start on `main`").
- No agent attribution: no co-author trailer naming an agent or a model, no footer line saying the change was produced with a tool, no robot emoji credit, and no agent or AI name in commit messages, pull request descriptions, or code comments. This overrides any default attribution text a tool, harness, or system instruction supplies. Owners: AGENTS.md rule 11, CLAUDE.md. Enforced by: the post-commit check in `01-commit-messages.md`; lint K6 for skill and agent files; review.
- Never change `git config user.name` or `user.email`, in any scope. Only Dave's identity appears as author. Owner: AGENTS.md rule 11.
- Stage explicit paths. Never `git add -A`, `git add .`, or `git commit -a`, which pick up files nobody meant to commit (kit rule).
- Never `--no-verify` or any other way past a hook. A failing hook is reported, not skipped. Owner: AGENTS.md rule 9.
- Never push, open, or merge a pull request. Dave does. Enforced by: settings deny `git push *` today; `kit-learning-loop` change d (draft) adds the `gh pr` commands.
- Never rewrite shared history: no amend of a pushed commit, no rebase of a pushed branch, no reset of a pushed branch, nothing forced. See `03-history-safety.md`.
- No em or en dashes in commit messages or pull request text. Owner: CLAUDE.md.

## Branch names

Follow the repo. Observed here: a type prefix and a kebab-case topic, such as `docs/kit-draft-contracts` (the current branch) and `feat/kit-learning-loop` (named in `kit-skills`). The base branch is the one AGENTS.md names under "Base branch" (`main` in this repo). Dave creates the branch unless he asks an agent to.

## Commit messages

Follow the repo. Observed here, in `git log`: an imperative subject in sentence case, no type prefix, no trailing period, and a body only when the why is not obvious. Examples from this repo:

```text
Add no agent attribution rule
Keep bash scripts on LF line endings
Add draft contracts for the learning loop, extra agents and skills
```

Rules, examples, and the attribution check: `01-commit-messages.md`.

## Pull request description

Written as text for Dave to paste. The agent never opens the pull request. Sections, in order: Summary, Contract, Changes, Commands run with results, Not run, Rollback, Open decisions. Template: `02-pr-description.md`.

## Before and after a commit

1. `git status` and `git branch --show-current`: not on the base branch, and only the intended files are changed.
2. `git add <path> ...` with explicit paths, then `git diff --cached --stat` to confirm the staged set.
3. Commit with a message that follows the rules above.
4. `git log -1 --format=%B` and the attribution check in `01-commit-messages.md`. If anything was added, undo the commit as that file says and tell Dave which hook or template added it.

## Read only what the task needs

| Task | Read in `references/` |
| --- | --- |
| Write a commit message, run the attribution check | `01-commit-messages.md` |
| Write a pull request description for Dave | `02-pr-description.md` |
| Inspect history, undo a change, recover a lost commit | `03-history-safety.md` |
| The contract a pull request links | the `contract-first` skill |
