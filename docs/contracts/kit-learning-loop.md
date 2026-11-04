---
feature: kit-learning-loop
status: draft
---

# Kit learning loop contract

## Goal

Lessons learned in a project (new or corrected skill and agent rules) flow back to the kit repo without leaking the project, and reach other projects only after Dave curates them. Four steps: capture (proposal, then project `.claude/` change), sync (project to its own kit branch), curate (chosen changes to kit `main`), spread (kit `main` to another project, file by file).

Out of scope:

- Pushing, opening or merging pull requests, or any GitHub operation. Dave does those.
- Syncing anything outside `.claude/skills/` and `.claude/agents/` back to the kit (hooks, settings, scripts, workflows, `AGENTS.md`, `CLAUDE.md`, `docs/`).
- Automatic conflict resolution. Every conflict stops and waits for Dave (see Open decisions OD-4).
- Replacing copy-per-project with a submodule, subtree, or package. Dave decided copy per project.

This is kit tooling (bash and docs), not an app feature, so the template is adapted. Sections renamed or removed are noted where they would have been.

## Terms and layout

```text
penal-pen-pal/                  project repo (its own git repo), the "project root"
  .claude/                      project copy of the kit: skills, agents, hooks, settings
  .claude/KIT_VERSION           kit commit this copy was last reconciled with
  docs/proposals/<name>.md      lesson proposals (committed in the project)
  scripts/                      project copy of kit scripts, including the two below
  avenger-kit/                  clone of https://github.com/jDxve/avengers-kit, gitignored by the project
                                checked out on branch project/penal-pen-pal
  web/  mobile/  backend/       optional monorepo apps
```

- **Project name**: `^[a-z0-9][a-z0-9-]*$`. Default is the lowercased basename of the project root. Overridable with `--project`.
- **Project branch**: `project/<project-name>` in the kit repo. Long-lived, one per project.
- **Clone**: `<project-root>/avenger-kit/` by default, overridable with `--kit-dir`. The default path is hardcoded in gate change b, so a different path also needs that change edited.
- **Kit main**: the clone's `refs/remotes/origin/main`. The scripts never read a local `main` branch.
- **Managed set (sync)**: files tracked by the project's git under `.claude/skills/` and `.claude/agents/`.
- **Managed set (pull)**: files under `.claude/` in kit main, except `.claude/settings.local.json` and `.claude/KIT_VERSION`. Wider scope is OD-7.

Repo convention noted: the kit has no `scripts/lib/` or `scripts/tests/` today, and `scripts/check-contracts.sh` is the only script (style: `set -euo pipefail`, `FAIL:`/`OK:` lines, exit code as result). The new scripts follow that style.

## Formats

These replace the template's Domain section, since there is no app domain.

### `.claude/KIT_VERSION`

Plain text, LF endings, `key=value` lines, `#` comments, blank lines ignored. Committed in the project repo. Not present in the kit repo itself.

```text
# Kit commit this project's .claude/ copy was last reconciled with.
# Written by scripts/pull-from-kit.sh. Edit by hand only to initialise it.
kit_commit=3f9c1e0a7b5d2c4e6f8a0b1c2d3e4f5a6b7c8d9e
declined=.claude/skills/react-standards/references/03-stack.md
```

| Key | Rule |
| --- | --- |
| `kit_commit` | Exactly once. `^[0-9a-f]{40}$`. Must exist in the clone and be an ancestor of kit main. |
| `declined` | Zero or more. A path under `.claude/`, no `..` or `.` segment, no leading `/`. Means Dave kept the project version of this file when pull-from-kit offered the kit version at `kit_commit`. |
| anything else | Unknown key: both scripts stop with exit 2. |

Initialising an existing project (Dave, once): `printf 'kit_commit=%s\n' "$(git -C avenger-kit rev-parse origin/main)" > .claude/KIT_VERSION`, using the kit commit the copy actually came from if that is known.

### `docs/proposals/<name>.md` and `docs/proposals/_template.md`

`<name>`: `^[a-z0-9][a-z0-9-]*$`. `_template.md` is the only file starting with `_` and is never treated as a proposal.

```markdown
---
proposal: <name>
status: draft
kind: rule | reference | agent
target: .claude/skills/<skill>/SKILL.md
---

# <Short title>

## Problem

What went wrong or was missing, in one paragraph.

## Evidence

What happened in this project that shows it: the failure, the review finding, the command output. Project detail is fine here. This file is never synced to the kit.

## Proposed change

The exact rule or reference text to add or replace, and where in the target file.

## General or project-specific

The author's first guess, with a reason. Curation decides for real.
```

- `target:` may repeat, one path per line. A target ending in `/` covers every file under it (for a new skill folder).
- Targets must start with `.claude/skills/` or `.claude/agents/`.
- `status` values: `draft`, `approved`. Only Dave sets `approved`. Whether a further `applied` state exists is OD-8.

### Curation proposal `docs/proposals/curate-<YYYY-MM-DD>.md` (in the kit repo)

Same frontmatter keys, with `kind: curation`, `source: project/<name>` (repeat for several branches), and one `target:` line per kit file thor may write. Body:

```markdown
## Changes

| # | Source branch | File | Summary | Class | Reason | Apply |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | project/penal-pen-pal | .claude/skills/nestjs-standards/references/05-rules.md | Adds rule on ... | general | Holds for any NestJS app | yes |
| 2 | project/penal-pen-pal | .claude/agents/thor.md | Mentions the project's queue name | project-specific | Names a project service | no |
| 3 | project/penal-pen-pal | .claude/skills/flutter-standards/references/12-testing.md | ... | general-with-edit | Rule is general, example is not | yes |

## Edited text

For each `general-with-edit` row, the exact text thor applies, with project detail removed.
```

- `Class`: `general`, `general-with-edit`, `project-specific`. iron-man fills it with a reason.
- `Apply`: iron-man pre-fills `yes` for general rows and `no` otherwise. Dave edits it, then sets `status: approved`.
- The kit repo's `.gitignore` gains `docs/proposals/curate-*.md`, so the classification of project changes (which describes the project) never enters kit history. Whether to keep it out is tied to OD-1.

## Interfaces

These replace the template's API section. All three are bash, run from the project root (curation runs in a kit checkout and has no script).

### `scripts/sync-to-kit.sh`

```text
bash scripts/sync-to-kit.sh [--dry-run] [--project <name>] [--kit-dir <dir>]
```

Steps, in order. Any failed step stops the run before the next one.

1. Preconditions (exit 2 on failure, nothing written):
   - cwd is the project's git toplevel and `.claude/` exists.
   - `<kit-dir>` is a git repo whose toplevel is `<kit-dir>` itself, and the project's git ignores it (`git check-ignore -q <kit-dir>`).
   - The clone is on branch `project/<name>`, its working tree is clean, and it is not mid-merge, rebase, or cherry-pick.
   - `origin/main` exists in the clone. No fetch.
   - `.claude/KIT_VERSION` parses (see Formats), and `kit_commit` is an ancestor of `origin/main`.
   - The project has no uncommitted or untracked changes under `.claude/skills/` or `.claude/agents/`, so what is synced is already in project history.
   - `git -C <kit-dir> config user.email` is set. The script never sets it.
2. Classify each path in the union of: the managed set, and the files under `.claude/skills/` and `.claude/agents/` at clone `HEAD`. Let `P` be the project file's blob (computed with `git -C <kit-dir> hash-object --path=<rel> <file>`, so the clone's `.gitattributes` normalises line endings), `H` the blob at clone `HEAD`, `B` the blob at `kit_commit`, and `M` the blob at `git merge-base HEAD origin/main`. A missing file is the empty value.

   | Condition | Class | Action |
   | --- | --- | --- |
   | path listed as `declined` in KIT_VERSION | declined | skip, list it |
   | `P == H` | in-sync | none |
   | `P` missing, `H` present | deleted-here | skip, list it. Sync never deletes |
   | `P != H` and `B == M` | changed-here | copy to clone |
   | `P != H`, `B != M`, `P == B` | kit-moved | skip, tell Dave to run pull-from-kit |
   | `P != H`, `B != M`, `P != B` | both-changed | stop, exit 1, list files (OD-4) |

3. For each changed-here file, report the approved proposals in `docs/proposals/` whose `target:` covers it, or `no approved proposal`. Whether that should stop the sync is OD-9.
4. Leak scan (below) on each changed-here file, against its clone `HEAD` version as base, and on the commit message. Any finding: exit 1, nothing written.
5. If no changed-here files: print `OK: nothing to sync`, exit 0.
6. `--dry-run` stops here: print the plan and `git diff --no-index` of each changed-here pair, exit 0.
7. Copy each changed-here file into the clone (`mkdir -p`, then `cp`). `git -C <kit-dir> add -- <paths>`. Verify `git diff --cached --name-only` equals the planned set exactly, else exit 1 and print how to inspect.
8. Commit with `git -C <kit-dir> commit -F <msgfile>`. Message:

   ```text
   Sync from project: <n> file(s)

   <path>
   <path>
   ```

   No `--author`, no `-c`, no trailer, no project name.
9. Re-read `git log -1 --format=%B`. If a commit hook or template added `Co-Authored-By`, `Generated with`, or an AI name, run `git reset --soft HEAD~1` (keeps the files staged), exit 1, and tell Dave which hook did it.
10. Print `git -C <kit-dir> show --stat HEAD` and the full diff. Print the push command for Dave as text. Never run it.

### `scripts/pull-from-kit.sh`

```text
bash scripts/pull-from-kit.sh [--dry-run] [--no-fetch] [--project <name>] [--kit-dir <dir>] [--answers-stdin]
```

1. Preconditions: as sync (toplevel, clone ignored, branch, clean clone, KIT_VERSION parses), plus no uncommitted or untracked changes under the project's `.claude/`, so every applied change can be reverted with git.
2. Unless `--dry-run` or `--no-fetch`: `git -C <kit-dir> fetch origin main`. This reads the network and writes only remote-tracking refs.
3. Unless `--dry-run`: `git -C <kit-dir> merge --no-edit origin/main` into `project/<name>`. On conflict: `git merge --abort`, exit 1, list the conflicting paths (OD-4).
4. Classify each path in the pull managed set. `P` project blob, `B` blob at `kit_commit`, `K` blob at `origin/main`.

   | Condition | Class | Prompt | Default |
   | --- | --- | --- | --- |
   | `P == K` | in-sync | none | |
   | `P == B`, `K != B` | kit-moved | `Apply kit version? [y/N]` | no |
   | `P != B`, `K == B` | customised-here | none, listed | keep |
   | `P != B`, `K != B`, `P != K` | both-changed | `Overwrite your customised file with the kit version? [y/N]`, diff shown first | no |
   | `P` missing, `B` missing, `K` present | new-in-kit | `Add? [y/N]` | no |
   | `P` missing, `B` present | deleted-here | `Restore? [y/N]` | no |
   | `K` missing, `P` present | deleted-in-kit | none, listed. Never deletes | keep |

   Paths under `.claude/hooks/` and `.claude/settings.json` are labelled `GATE FILE` in the prompt.
5. Before each prompt, print `git diff --no-index` of project file and kit file.
6. Answers come from the terminal. If stdin is not a terminal and `--answers-stdin` is absent, apply nothing and exit 1. `--answers-stdin` exists for hawkeye's tests. Any answer other than `y` or `Y` is no.
7. `--dry-run`: no fetch, no merge, no prompts, no writes. Prints the classification against the current `origin/main` and exits 0.
8. Write each confirmed file (copy from `git show origin/main:<path>` through a temp file, then `mv`).
9. Rewrite `.claude/KIT_VERSION` (temp file, then `mv`): `kit_commit` becomes `origin/main`. `declined` lines: add each kit-moved or both-changed path Dave answered no to, remove each path he accepted, keep the rest. Write only if content changes.
10. Print what was applied, declined, and listed, and remind Dave to review and commit in the project.

### `scripts/lib/leak-scan.sh`

Separate file so hawkeye can test it alone and the allowlist has one owner.

```text
bash scripts/lib/leak-scan.sh --project <name> [--allowlist <file>] [--env-file <file>]... \
  [--message-file <file>] [--base <file>] -- <file>...
```

- `--base`: scan only lines added in `<file>` relative to `<base>` (from `git diff --no-index -U0`), reporting line numbers in `<file>`. Lines already in the kit are already public, so they do not stop a sync. `--base` applies to a single file. Without it, every line is scanned.
- `--allowlist` defaults to `scripts/lib/leak-allowlist.txt`.
- `--env-file`: sync passes every `.env` and `.env.*` file (not `.env.example`) found by bash globs at the project root and one level down (`.env*`, `*/.env*`), skipping `<kit-dir>` and `node_modules`.
- Exit 0 clean, 1 findings, 2 usage error, unreadable file, or bad allowlist line.
- Output, one line per finding: `LEAK <rule> <path>:<line> <detail>`. For `secret.*` and `env.value`, `<detail>` is `[masked]` and, for env, the variable name. Values are never printed.

Rules:

| Rule | Stops on |
| --- | --- |
| `secret.private-key` | `-----BEGIN [A-Z ]*PRIVATE KEY-----` |
| `secret.aws` | `AKIA[0-9A-Z]{16}` |
| `secret.github` | `gh[pousr]_[A-Za-z0-9]{36,}`, `github_pat_[A-Za-z0-9_]{20,}` |
| `secret.slack` | `xox[abprs]-[A-Za-z0-9-]{10,}` |
| `secret.stripe` | `[sr]k_(live|test)_[A-Za-z0-9]{16,}` |
| `secret.google` | `AIza[0-9A-Za-z_-]{35}` |
| `secret.sk` | `sk-[A-Za-z0-9_-]{20,}` |
| `secret.jwt` | `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}` |
| `secret.assignment` | `(password|passwd|secret|api[_-]?key|access[_-]?key|token)["']?[[:space:]]*[:=][[:space:]]*["'][^"'[:space:]]{8,}["']`, case-insensitive |
| `path.windows` | `[A-Za-z]:\\` or `[A-Za-z]:/` |
| `path.users` | `/Users/` (also covers `/c/Users/`) |
| `path.home` | `/home/` |
| `email` | `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}` not in the allowlist |
| `url` | `https?://<host>` whose host is not in the allowlist |
| `ipv4` | dotted quad not in the allowlist |
| `project-name` | the project name, case-insensitive, with each `-` matching `-`, `_`, space, `.`, or nothing |
| `env.value` | any value of 8 or more characters from an `--env-file`, matched as a fixed string |
| `env.file` | a scanned path whose basename starts with `.env` |
| `binary` | a file grep treats as binary. It cannot be scanned, so it stops |
| `attribution` | message file only: `Co-Authored-By`, `Generated with`, `Claude`, `Anthropic`, `noreply@anthropic.com`, case-insensitive |

### `scripts/lib/leak-allowlist.txt`

```text
# kind value. Hosts are exact, or *.domain for subdomains.
url example.com
url *.example.com
url test
url localhost
email a@b.com
email @example.com
ip 127.0.0.1
ip 0.0.0.0
```

Seeded from what the kit's skills already contain (`api.example.com`, `http://test`, `a@b.com` in `flutter-standards` 12-testing.md). `192.168.1.100` also appears in a skill and is deliberately not allowlisted: it only matters if a project adds it again. An unknown kind makes the scan exit 2.

## Authorization

| Operation | Who | Enforced by |
| --- | --- | --- |
| Draft a lesson proposal | iron-man by default, any agent may | path-fence change a; contract-gate change b keeps status draft |
| Approve a proposal or curation proposal | Dave only | contract-gate change b |
| Apply an approved proposal to project `.claude/skills|agents` | thor, or Dave | contract-gate change b (approved proposal must target the file) |
| Run `sync-to-kit.sh` or `pull-from-kit.sh` for real | Dave only | settings change d allows only `--dry-run` for agents, so a real run prompts Dave |
| Run either with `--dry-run` | any agent | settings change d |
| Write anything under `avenger-kit/` | Dave and the two scripts | contract-gate change b |
| Write `.claude/KIT_VERSION` | Dave (init) and pull-from-kit | contract-gate change b |
| Write the curation proposal | iron-man | path-fence change a |
| Review the curation proposal | black-widow | agent tool list (read-only) |
| Apply chosen changes on `curate/<date>` | thor | contract-gate change b (curation proposal targets) |
| Push any branch, open or merge a PR | Dave only | settings deny `git push`, `gh pr create`, `gh pr merge` (change d) |

## Branches and drift states

Replaces the template's State section.

| Branch | Lives in | Written by | Merged into `main` |
| --- | --- | --- | --- |
| `main` | kit repo | Dave merges PRs | |
| `project/<name>` | kit repo (local clone in the project; remote is OD-2) | sync commits, pull merges of `origin/main` | never |
| `curate/<YYYY-MM-DD>` | kit checkout | thor, cut from `main` | by Dave, through a PR |

If `curate/<date>` already exists, thor stops and asks Dave for a name.

Drift states per file are the two classification tables above. `KIT_VERSION` is the base that separates "changed here" from "kit moved on". Without it both scripts stop.

## Workflow

1. **Capture.** An agent notices a lesson. captain-america routes it to iron-man, who writes `docs/proposals/<name>.md` (draft). Dave reviews and sets `status: approved`. thor applies the change to the project's `.claude/skills|agents`. Dave commits in the project.
2. **Sync.** Dave runs `bash scripts/sync-to-kit.sh --dry-run`, then without it. It commits on `project/<name>` in the clone and prints the diff. Dave pushes if OD-2 says so.
3. **Curate.** In a kit checkout with the project branches available locally (fetched from origin, or from a project clone as a local remote if branches are not pushed), Dave asks for a merge. iron-man reads `git diff main..project/<name>` for each source branch and writes `docs/proposals/curate-<date>.md`. black-widow reviews it, PASS or BLOCK. Dave edits `Apply`, approves. thor runs `git switch -c curate/<date> main` and re-applies only `Apply: yes` rows, using the curation proposal's text for `general-with-edit`. thor never runs `git merge`, `git cherry-pick`, or `git checkout project/... -- <path>`. black-widow reviews the branch. Dave opens and merges the PR.
4. **Spread.** In another project, Dave runs `bash scripts/pull-from-kit.sh`. It merges kit `main` into that project's branch and walks the per-file prompts.

## Invariants

| # | Invariant | Enforced by |
| --- | --- | --- |
| I1 | Agents never push | settings deny `Bash(git push*)` and `Bash(git -C * push*)` (change d). Test T-S9: neither script contains `push` outside the printed hint, and the bare origin's refs are unchanged after a run |
| I2 | Scripts commit locally only and never touch a remote except pull's `fetch` | Test T-S9 (bare origin refs unchanged), T-P8 (`--no-fetch` and `--dry-run` make no network call: origin URL set to a nonexistent path still passes) |
| I3 | No agent attribution in sync commits; git identity never changed | Fixed message template; post-commit check (step 9); leak-scan `attribution` rule on the message; settings deny `git config*user.*` (change d); tests T-S6, T-S7 |
| I4 | Every sync commit is preceded by a passing leak scan of added lines and of the message | Step order in sync; tests T-L1 to T-L14, T-S4 |
| I5 | The scan fails closed: unreadable, binary, or bad allowlist means stop | leak-scan exit 2 or `binary` rule; tests T-L10, T-L11, T-L12 |
| I6 | Secret and env values never print | Masked output; test T-L13 |
| I7 | A kit change is never reverted by sync | `kit-moved` and `both-changed` classes; tests T-S2, T-S3 |
| I8 | A customised project file is never overwritten without a `y` | pull classification, default no, non-terminal applies nothing; tests T-P2, T-P3, T-P5 |
| I9 | Scripts never delete a user's file | No `rm` of project or clone files in either script (review, and test T-S10/T-P6 assert deleted-here and deleted-in-kit files survive) |
| I10 | Idempotent: a second run with no new changes writes nothing | Classification `in-sync`; tests T-S5, T-P7 |
| I11 | `--dry-run` writes nothing, anywhere | Tests T-S8, T-P8 (tree hashes, refs, and `KIT_VERSION` identical before and after) |
| I12 | Preconditions fail closed with exit 2 and no writes | Tests T-S1 (each precondition) and T-P1 |
| I13 | A project branch is never merged into `main` wholesale | thor's curation instructions; black-widow check `git log --merges main..curate/<date>` is empty; recommended CI change f; branch protection (Dave) |
| I14 | Proposals and curation proposals are approved only by Dave | contract-gate change b; gate tests T-G1, T-G2 |
| I15 | Project skills and agents change only through an approved proposal | contract-gate change b; test T-G3 |
| I16 | Agents cannot write the clone or KIT_VERSION | contract-gate change b; test T-G4 |
| I17 | The clone is never committed into the project | sync and pull precondition `git check-ignore`; test T-S1 |
| I18 | LF endings for every new script | `.gitattributes` `*.sh text eol=lf` (exists); `leak-allowlist.txt` and `KIT_VERSION` are read with `\r` stripped, test T-L14 |
| I19 | No dependency beyond bash, git, jq, grep, sed, and the coreutils Git Bash ships (`cp`, `mv`, `mkdir`, `mktemp`) | Review; T-S0 checks each script with `bash -n` and that it calls no other tool (`grep` for `find`, `awk`, `python`, `perl`, `curl`) |
| I20 | The leak scanner and its allowlist cannot be loosened by an agent | Recommended contract-gate change e |

## What the leak scan cannot catch

The kit repo may be public, so Dave should read every sync diff himself. The scan does not catch:

- Secrets with no known prefix that are not in a `.env` file, such as a password typed in prose or a key from a vault.
- Project vocabulary: client names, product names, domain terms, internal service or queue names, people's names, internal hostnames written without `http://`. Only the project name itself is checked. An optional per-project terms file is OD-10.
- Encoded or split values (base64, a key broken across lines, a path built from pieces).
- Meaning: a rule that reveals how the project works (its domain, its stack quirks) without naming it.
- The branch name `project/<name>`, which carries the project name into the kit repo if pushed (OD-1, OD-2).
- Commit metadata: every commit carries Dave's git name and email, as the kit's existing commits already do.
- Anything already pushed. Removing it needs a history rewrite and a secret rotation.
- Lines that were already in the kit, by design (`--base`).
- Short project names (under four characters) will stop the scan on ordinary words. Expect false stops, not leaks.

## Failure paths

What Dave sees for each. Every message names the next step.

| Situation | Script | Exit | Message |
| --- | --- | --- | --- |
| Not at project toplevel | both | 2 | `FAIL: run from the project root (<path>)` |
| Clone missing or not a repo | both | 2 | `FAIL: <kit-dir> is not a kit clone. See README "Kit learning loop"` |
| Clone not ignored by the project | both | 2 | `FAIL: add /<kit-dir>/ to .gitignore first` |
| Clone on wrong branch | both | 2 | `FAIL: <kit-dir> is on <b>, expected project/<name>` |
| Clone dirty or mid-merge | both | 2 | `FAIL: <kit-dir> has uncommitted changes. Inspect with git -C <kit-dir> status` |
| Project `.claude/` paths dirty | both | 2 | `FAIL: commit or revert changes under <paths> first` |
| KIT_VERSION missing or invalid | both | 2 | `FAIL: .claude/KIT_VERSION <problem>. See README for how to initialise it` |
| `kit_commit` not in clone or not an ancestor | both | 2 | `FAIL: kit_commit <sha> is not on origin/main. Run git -C <kit-dir> fetch` |
| No git identity in clone | sync | 2 | `FAIL: set your git identity yourself. This script never changes it` |
| Leak found | sync | 1 | `LEAK ...` lines, then `STOPPED: nothing was copied or committed` |
| Both-changed files | sync | 1 | list, then `STOPPED: the kit also changed these. Run pull-from-kit first` |
| Staged set differs from plan | sync | 1 | `STOPPED: unexpected staged files. Inspect with git -C <kit-dir> status` |
| Hook added attribution | sync | 1 | `STOPPED: commit message gained <line>. Commit undone with reset --soft, files still staged` |
| Copy fails midway | sync | 1 | `STOPPED: clone left with uncommitted changes. Inspect, then git -C <kit-dir> restore --staged --worktree -- .claude` |
| Merge conflict | pull | 1 | conflicting paths, then `STOPPED: merge aborted, nothing changed` |
| Fetch fails | pull | 1 | `STOPPED: fetch failed. Re-run with --no-fetch to use the current origin/main` |
| No terminal | pull | 1 | `STOPPED: needs a terminal to confirm each file. Nothing applied` |
| Nothing to do | both | 0 | `OK: nothing to sync` or `OK: project matches kit main` |

## Changes Dave must apply

These edit gate files, so iron-man does not make them. Each is a before and after snippet. Apply a, d first, then thor builds, then b and e (see Release for why).

### a. `path-fence.sh`: architecture profile writes proposals

Before (line 9):

```bash
  architecture) allowed='^docs/(contracts|adr)/' ;;
```

After:

```bash
  architecture) allowed='^docs/(contracts|adr|proposals)/' ;;
```

Also update iron-man's body text ("You only write under `docs/contracts/` and `docs/adr/`") in the same change set. That is an agent file, so thor does it before change b lands.

### b. `contract-gate.sh`: protect the clone and KIT_VERSION, gate skills and agents on approved proposals, keep proposals human-approved

b1. Gate list (line 26). Before:

```bash
if [[ "$rel" =~ ^(\.claude/(hooks/|settings\.json$)|scripts/check-contracts\.sh$|\.github/workflows/agent-gates\.yml$) ]]; then
  block "$rel is a gate, so only Dave edits it. Report the change you think it needs."
fi
```

After:

```bash
if [[ "$rel" =~ ^(\.claude/(hooks/|settings\.json$|KIT_VERSION$)|scripts/check-contracts\.sh$|\.github/workflows/agent-gates\.yml$) ]]; then
  block "$rel is a gate, so only Dave edits it. Report the change you think it needs."
fi

# The kit clone inside a project: only Dave and the sync and pull scripts change it.
if [[ "$rel" =~ ^avenger-kit(/|$) ]]; then
  block "$rel is in the kit clone. Only Dave, sync-to-kit.sh, and pull-from-kit.sh change it."
fi
```

b2. Contracts and proposals (lines 30 to 45). This also closes a gap in the current check (see Problems walked past, item 1): it checks the file as it would be after the edit, not just `new_string`. Before:

```bash
# Contracts: only a person approves one, and an approved one reopens before it changes.
if [[ "$rel" =~ ^docs/contracts/[^/]+\.md$ ]]; then
  if [ "$tool" = "Write" ]; then
    new="$(jq -r '.tool_input.content // empty' <<<"$input")"
  else
    new="$(jq -r '.tool_input.new_string // empty' <<<"$input")"
  fi
  if grep -Eq '^status:[[:space:]]*approved' <<<"$new"; then
    block "Only Dave approves a contract. Leave it as status: draft and ask him to review it."
  fi
  if [ -f "$root/$rel" ] && [ "$(status_of "$root/$rel")" = "approved" ] \
    && ! grep -Eq '^status:[[:space:]]*draft' <<<"$new"; then
    block "$rel is approved. Set status: draft in this same edit, then report what changed."
  fi
  exit 0
fi
```

After:

```bash
# Contracts and proposals: only a person approves one, and an approved one reopens before it changes.
if [[ "$rel" =~ ^docs/(contracts|proposals)/[^/]+\.md$ ]]; then
  kind="${BASH_REMATCH[1]%s}"
  status_in() { sed -n 's/^status:[[:space:]]*\([a-z]*\).*/\1/p' <<<"$1" | head -n 1; }
  cur=""; [ -f "$root/$rel" ] && cur="$(cat "$root/$rel")"
  if [ "$tool" = "Write" ]; then
    new="$(jq -r '.tool_input.content // empty' <<<"$input")"
  else
    old="$(jq -r '.tool_input.old_string // empty' <<<"$input")"
    rep="$(jq -r '.tool_input.new_string // empty' <<<"$input")"
    if [ "$(jq -r '.tool_input.replace_all // false' <<<"$input")" = "true" ]; then
      new="${cur//"$old"/"$rep"}"
    else
      new="${cur/"$old"/"$rep"}"
    fi
  fi
  if [ "$(status_in "$new")" = "approved" ]; then
    [ "$(status_in "$cur")" = "approved" ] \
      && block "$rel is approved. Set status: draft in this same edit, then report what changed."
    block "Only Dave approves a $kind. Leave it as status: draft and ask him to review it."
  fi
  exit 0
fi
```

b3. New block, inserted before the `# Feature code:` block:

```bash
# Skills and agents change only through an approved proposal whose target: names the file.
if [[ "$rel" =~ ^\.claude/(skills|agents)/ ]]; then
  for p in "$root"/docs/proposals/*.md; do
    [ -f "$p" ] || continue
    [ "$(basename "$p")" = "_template.md" ] && continue
    [ "$(status_of "$p")" = "approved" ] || continue
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      [ "$rel" = "$t" ] && exit 0
      [[ "$t" == */ && "$rel" == "$t"* ]] && exit 0
    done < <(sed -n 's/^target:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$p" | tr -d '\r')
  done
  block "$rel is a skill or agent file. It changes only through an approved docs/proposals/<name>.md whose target: names it. Have iron-man draft one."
fi
```

b4. Path hardening, strongly recommended with b, because b1 and b3 match on `rel` (see Problems walked past, item 2). Insert after `rel="${file#"$root"/}"`, in both `contract-gate.sh` and `path-fence.sh`:

```bash
# Windows paths are case-insensitive, and . or .. segments would dodge every prefix match below.
if [[ "${file,,}" == "${root,,}/"* ]]; then rel="${file:${#root}+1}"; fi
rel="$(sed -E 's#/+#/#g' <<<"$rel")"
[[ "/$rel/" == */../* || "/$rel/" == */./* ]] && block "Use a path without . or .. segments: $rel"
```

and in `contract-gate.sh` match the gate, clone, and skills regexes against `"${rel,,}"` (or add `shopt -s nocasematch` after `set -uo pipefail`). Keep `"$root/$rel"` for file reads.

### c. Optional, separate: monorepo prefix `(web|mobile|backend)/`

Build only if OD-5 says so. One contract per feature name stays: `web/src/features/orders` and `backend/src/modules/orders` both map to `docs/contracts/orders.md`.

`contract-gate.sh` (lines 47 to 50). Before:

```bash
# Feature code: lib/features/<f>, src/features/<f>, or src/modules/<f>.
if [[ "$rel" =~ ^(lib/features|src/features|src/modules)/([^/]+)/ ]]; then
  area="${BASH_REMATCH[1]}"
  feature="${BASH_REMATCH[2]}"
```

After:

```bash
# Feature code: lib/features/<f>, src/features/<f>, or src/modules/<f>, optionally under web/, mobile/, or backend/.
if [[ "$rel" =~ ^((web|mobile|backend)/)?(lib/features|src/features|src/modules)/([^/]+)/ ]]; then
  area="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
  feature="${BASH_REMATCH[4]}"
```

`scripts/check-contracts.sh` (line 24). Before:

```bash
    | sed -nE 's#^(lib/features|src/features|src/modules)/([^/]+)/.*#\1\t\2#p' \
```

After:

```bash
    | sed -nE 's#^((web|mobile|backend)/)?(lib/features|src/features|src/modules)/([^/]+)/.*#\1\3\t\4#p' \
```

The `git cat-file -e "$merge_base:$area/$feature"` check then works unchanged with `area` such as `web/src/features`.

### d. `.claude/settings.json`

Add to `permissions.allow`:

```json
      "Bash(git show*)",
      "Bash(git rev-parse*)",
      "Bash(git merge-base*)",
      "Bash(git ls-files*)",
      "Bash(git branch --show-current*)",
      "Bash(git -C avenger-kit status*)",
      "Bash(git -C avenger-kit diff*)",
      "Bash(git -C avenger-kit log*)",
      "Bash(git -C avenger-kit show*)",
      "Bash(bash scripts/sync-to-kit.sh --dry-run*)",
      "Bash(bash scripts/pull-from-kit.sh --dry-run*)",
      "Bash(bash scripts/tests/run.sh*)"
```

Add to `permissions.deny`, keeping `"Bash(git push *)"`:

```json
      "Bash(git push)",
      "Bash(git push*)",
      "Bash(git -C * push*)",
      "Bash(git config*user.name*)",
      "Bash(git config*user.email*)",
      "Bash(git -C * config*)",
      "Bash(gh pr create*)",
      "Bash(gh pr merge*)"
```

Why: `git push *` may not match a bare `git push`, and does not match `git -C avenger-kit push`. Real runs of the two scripts are deliberately not allowed, so they prompt and Dave runs them.

### e. Recommended, after thor builds: protect the scanner

Extend the b1 gate regex with `|scripts/lib/leak-scan\.sh$|scripts/lib/leak-allowlist\.txt$`, so nick-fury (who can write `scripts/`) cannot loosen the scan. Applying it before thor builds would block the build.

### f. Recommended: CI refuses project branches into `main`

Add to `.github/workflows/agent-gates.yml` after the Contracts step:

```yaml
      - name: No project branch into main
        env:
          HEAD_REF: ${{ github.head_ref }}
        run: |
          case "$HEAD_REF" in project/*) echo "FAIL: project branches never merge into main"; exit 1;; esac
          git fetch --no-tags origin '+refs/heads/project/*:refs/remotes/origin/project/*' || true
          for c in $(git rev-list "origin/$GITHUB_BASE_REF..HEAD"); do
            for b in $(git for-each-ref --format='%(refname)' refs/remotes/origin/project/); do
              if git merge-base --is-ancestor "$c" "$b"; then echo "FAIL: $c comes from $b"; exit 1; fi
            done
          done
          echo "OK: no project branch commits"
```

This only sees project branches that were pushed (OD-2). Branch protection on `main` is Dave's setting.

## Build list for thor

After a and d are applied, and before b and e:

1. `scripts/lib/leak-scan.sh` and `scripts/lib/leak-allowlist.txt` as specified.
2. `scripts/sync-to-kit.sh` and `scripts/pull-from-kit.sh` as specified. `set -euo pipefail`, `FAIL:`/`STOPPED:`/`OK:` prefixes, exit codes as specified, `--help` prints usage.
3. `docs/proposals/_template.md` from Formats.
4. Agent and doc text (before change b lands, since b gates `.claude/agents/`):
   - `iron-man.md`: may write `docs/proposals/`; writes lesson and curation proposals.
   - `captain-america.md` and `docs/team.md` routing rows: "Capture a lesson: iron-man drafts a proposal, stop for approval, thor applies it to `.claude/`", and "Prepare a kit merge: iron-man writes the curation proposal, black-widow reviews, stop for approval, thor applies on `curate/<date>` from `main`, black-widow reviews".
   - `thor.md`: on curation, never merge, cherry-pick, or check out files from a project branch; apply only `Apply: yes` rows.
5. Kit `.gitignore`: add `docs/proposals/curate-*.md`.
6. README section "Kit learning loop": layout, one-time setup per project (clone into `avenger-kit/`, `git -C avenger-kit switch -c project/<name> origin/main`, add `/avenger-kit/` to the project `.gitignore`, initialise `KIT_VERSION`), the four steps, the scan's limits from this contract, and a row per new rule in "What enforces what".
7. Project `.gitignore` guidance in that README section: add `/avenger-kit/`. Keep `.claude/KIT_VERSION` and `docs/proposals/` committed.
8. `CHANGELOG.md` line under the release date: `- Added the kit learning loop: lesson proposals, sync-to-kit.sh, pull-from-kit.sh, and a leak scan (ADR-013).`

## Release

No app schema or infrastructure. The rollout is gate changes and files.

- Order: Dave applies a and d. thor builds. hawkeye writes tests. black-widow reviews. Dave applies b (with b4) and e, then c and f if chosen.
- Rollback: revert the commit, or delete the two scripts and `scripts/lib/`. Projects keep working with no loop. A pushed project branch with a leak cannot be rolled back by a revert: rewrite history and rotate the secret.

## Removed sections

- **Mutation queue**: none. The scripts are synchronous and local.
- **UI contract**: no UI. The scripts' terminal output is specified under Interfaces and Failure paths.

## Tests

hawkeye writes these under `scripts/tests/` (inside the tests fence), run by `bash scripts/tests/run.sh`. Every test runs in `mktemp -d`: a bare repo as fake `origin`, a kit clone, and a project repo. The runner refuses to run if any remote URL is not a local path under the temp dir. Isolation: `HOME` and `GIT_CONFIG_GLOBAL` point into the temp dir, `GIT_CONFIG_NOSYSTEM=1`, identity through `GIT_AUTHOR_*` and `GIT_COMMITTER_*` env vars (never `git config`). Secret-shaped fixtures are assembled at runtime from pieces, so the kit repo never holds a string that trips a secret scanner.

Leak scan:

- T-L1 to T-L9: one dirty fixture per rule family (each `secret.*`, `path.*`, `email`, `url`, `ipv4`, `project-name` with `-`, `_`, space, and joined variants, `env.value`, `env.file`), each exits 1 with the right rule id.
- T-L10: binary file exits 1 with `binary`.
- T-L11: unreadable or missing file exits 2.
- T-L12: allowlist with an unknown kind exits 2.
- T-L13: output for secret and env findings contains `[masked]` and never the value.
- T-L14: CRLF allowlist and KIT_VERSION parse the same as LF.
- T-L15: `--base` ignores a URL already in the base and stops on a newly added one.
- T-L16: allowlisted URL, email, and IP pass. Clean fixture exits 0.
- T-L17: `--message-file` with `Co-Authored-By` exits 1 with `attribution`.

Sync:

- T-S0: `bash -n` on each script; no `find`, `awk`, `python`, `perl`, `curl`.
- T-S1: each precondition in Interfaces fails with exit 2 and changes nothing (clone not ignored, wrong branch, dirty clone, mid-merge, dirty project paths, missing and malformed KIT_VERSION, unknown key, `kit_commit` not an ancestor, no identity).
- T-S2: a file the kit changed and the project did not is skipped as kit-moved, not reverted.
- T-S3: a file both changed stops with exit 1, nothing committed.
- T-S4: a leak in a changed file stops with exit 1, clone tree and refs unchanged.
- T-S5: run twice. Second run prints `OK: nothing to sync`, no new commit.
- T-S6: commit author is the env identity, message matches the template, no trailer.
- T-S7: a `commit-msg` hook in the clone that appends `Co-Authored-By` leads to exit 1, `HEAD` back where it was, files still staged.
- T-S8: `--dry-run` leaves clone and project trees, index, and refs identical.
- T-S9: bare origin refs identical after a full run.
- T-S10: a file deleted in the project still exists in the clone after sync.
- T-S11: a second lesson to a file already synced once is classified changed-here, not both-changed.
- T-S12: a `declined` path is skipped.
- T-S13: CRLF working copy of an unchanged file is in-sync.

Pull:

- T-P1: preconditions as T-S1, plus dirty project `.claude/`.
- T-P2: kit-moved file, answer `n`: file unchanged, path added to `declined`.
- T-P3: both-changed file, answer `y`: overwritten; answer anything else: unchanged.
- T-P4: new-in-kit, answer `y`: added.
- T-P5: no terminal and no `--answers-stdin`: exit 1, nothing applied.
- T-P6: deleted-in-kit file survives in the project.
- T-P7: second run after a full apply writes nothing, KIT_VERSION identical.
- T-P8: `--dry-run` and `--no-fetch` work with origin pointed at a nonexistent path, and `--dry-run` changes nothing.
- T-P9: merge conflict aborts the merge and leaves the clone at its prior `HEAD`.
- T-P10: `KIT_VERSION` ends with `kit_commit` equal to `origin/main`.

Gate (hook fixtures, JSON on stdin):

- T-G1: Write and Edit that make a proposal `approved` are blocked, including an Edit whose `new_string` is just `approved`.
- T-G2: Edit to an approved proposal that does not reset to draft is blocked.
- T-G3: write to `.claude/skills/x/SKILL.md` blocked with no approved proposal, allowed with one targeting it, allowed by a `target:` ending in `/`, blocked by a draft one.
- T-G4: writes under `avenger-kit/` and to `.claude/KIT_VERSION` blocked.
- T-G5: with b4, `.Claude/Hooks/x`, `.claude//hooks/x`, and `docs/contracts/../../.claude/hooks/x` are blocked; path-fence architecture rejects `docs/contracts/../../lib/x.dart`.

Whether these run in CI is OD-6. Until then hawkeye runs them locally and reports the command and result.

## Problems walked past

Found by reading the code. My fixture probe of the hooks was denied, so these are theoretical, not reproduced.

1. `contract-gate.sh` checks only `new_string` for `status: approved`. An Edit with `old_string: "draft"` and `new_string: "approved"` on the status line has no `status:` prefix in `new_string`, so it passes. b2 fixes this for contracts and proposals.
2. Both hooks strip the root with a case-sensitive prefix and match `rel` with case-sensitive regexes, and neither removes `.` or `..` segments or doubled slashes. On Windows, `.Claude/Hooks/contract-gate.sh`, `c:/lcc mobile projects/...` with a differently cased root, `.claude//hooks/...`, or `docs/contracts/../../.claude/hooks/...` would not match the gate. The same applies to path-fence, where `docs/contracts/../../lib/x.dart` matches the architecture allow pattern. This depends on whether Claude Code normalises `file_path` before the hook sees it, which I could not check. b4 fixes it.
3. The clone at `avenger-kit/` holds its own `CLAUDE.md` and `.claude/skills/`. Claude Code may load nested `CLAUDE.md` files and skills when an agent reads files there, which would give duplicate skills or rules. Not fixed here. Listed so Dave can watch for it.

## Open decisions

All unresolved. Do not build the affected part until Dave answers.

- **OD-1 (unresolved)**: Is the kit repo private or public? Affects how strict the scan must be, whether curation proposals stay out of kit history, and whether branch names may carry project names.
- **OD-2 (unresolved)**: Are project branches pushed at all? If not, curation needs each project clone added as a local remote, and CI change f cannot see them. If yes and the kit is public, `project/<name>` publishes the project name.
- **OD-3 (unresolved)**: Does sync commit, as Dave's goal states, or only stage for Dave to commit? The contract specifies commit. Staging only would drop steps 8 and 9.
- **OD-4 (unresolved)**: Conflicts, when a project edited a file the kit also changed. Today both scripts stop (sync on both-changed, pull on merge conflict and per-file default no). Options include a three-way merge with markers, keeping the project version and recording `declined`, or a manual-merge runbook.
- **OD-5 (unresolved)**: Build the optional monorepo prefix (change c) now, or later?
- **OD-6 (unresolved)**: Do hawkeye's tests run in CI (a step in `agent-gates.yml`, a gate file), or only locally?
- **OD-7 (unresolved)**: Should pull-from-kit also cover `scripts/`, `.github/`, `AGENTS.md`, `CLAUDE.md`, and `docs/` (skill templates, ADRs)? Without it, fixes to the sync scripts themselves do not reach projects.
- **OD-8 (unresolved)**: Does an approved proposal authorise edits to its target forever, or should it move to a third status such as `applied`, after which the gate stops honouring it?
- **OD-9 (unresolved)**: Should sync refuse a changed file that no approved proposal targets (for example, a manual edit by Dave), or only warn as specified?
- **OD-10 (unresolved)**: Add an optional per-project terms file (client names, internal hosts) to the scan? Not built without a stated need.
