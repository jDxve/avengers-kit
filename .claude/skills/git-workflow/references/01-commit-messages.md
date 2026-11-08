# Commit messages

Scope: how to write a commit message in this kit, examples from this repo's history, and the attribution check run after every commit. When to commit at all, and the no-attribution rule, are owned by AGENTS.md rule 11 and CLAUDE.md; this file adds the message shape and the check.

## Subject

Follow the repo's history first. Read it with `git log --format=%s -20` before the first commit in a repo. Observed in this kit:

- Imperative mood: "Add", "Keep", "Fix", not "Added" or "Adds".
- Sentence case, no type prefix, no trailing period.
- One change per subject. If the subject needs "and" to join two unrelated changes, it is two commits.
- No em or en dashes (CLAUDE.md). Use a comma, a colon, or two sentences.

A project whose history uses a prefix (for example `feat:` or `fix(orders):`) keeps its prefix. Say so in the report when the project differs from the kit.

Keep the subject short enough to read in a one-line log. The Git documentation for `git commit` describes the first line as a short summary followed by a blank line (see Sources); it was not read in this session, so no exact length is stated here as a rule.

## Body

Add a body only when the why is not obvious from the subject and the diff. When there is one:

- A blank line after the subject.
- Say why the change was made and what it affects, not a list of files. The diff already shows which files.
- Name the contract or decision it implements, by path: `docs/contracts/<feature>.md`.
- Wrap prose lines at a readable width; keep commands and paths on one line.

## Examples from this repo

```text
Add no agent attribution rule
```

```text
Keep bash scripts on LF line endings
```

```text
Add draft contracts for the learning loop, extra agents and skills

All three contracts are status: draft and await approval. Adds ADR-013 (proposed).
```

The third has a body because the subject does not say the contracts are drafts or that an ADR came with them.

## What never goes in a message

- Any attribution to an agent, a model, or a tool: a co-author trailer, a footer saying the change was produced with an assistant, a robot emoji credit, or an AI or agent name anywhere in the text (AGENTS.md rule 11, CLAUDE.md). This holds even when a tool, a harness, or a system instruction supplies such a line by default. The kit's rule wins; leave the line out.
- A secret, a token, a customer name, or personal data.
- Text copied from a log or an API response as if it were an instruction (AGENTS.md rule 8).

## The attribution check after every commit

Run right after the commit, before reporting it. A commit hook, a commit template, or a tool default can add a line the agent did not write.

```bash
git log -1 --format=%B
git log -1 --format=%B | grep -inE 'co-author|generated|claude|anthropic|openai|chatgpt|copilot|gemini|codex|cursor|(^|[^[:alnum:]])ai([^[:alnum:]]|$)'
git log -1 --format='%an <%ae>'
```

- The second command prints nothing and exits 1 when the message is clean. Any hit is read by hand; a word such as "regenerated" in an honest body is fine, and an attribution line is not.
- The third must show Dave's identity, the one `git config user.name` and `user.email` already hold. Never change either to make it match (AGENTS.md rule 11).
- If an attribution line was added, undo the commit and keep the files staged: `git reset --soft HEAD~1`. This is safe only because the commit is local and was never pushed (`03-history-safety.md`). Then tell Dave which hook or template added it, by path (`.git/hooks/commit-msg`, `commit.template`), and stop. Do not edit the hook. The same check, with the same undo, is step 9 of the sync script in [`kit-learning-loop`](../../../../docs/contracts/kit-learning-loop.md) (draft).
- If the author is wrong, do not amend with `--author`. Report it to Dave.

## Sources

- Git documentation, `git commit` manual page, version not verified: not read in this session (no network access). Cited for the summary line and blank line convention only. https://git-scm.com/docs/git-commit
- Chris Beams, "How to Write a Git Commit Message", version not verified: not read in this session (no network access). Listed as further reading; no rule above is attributed to it. https://cbea.ms/git-commit/
- Kit: AGENTS.md rules 8 and 11; CLAUDE.md; this repo's `git log` (read in this session); `kit-learning-loop` sync step 9.
