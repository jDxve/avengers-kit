# Avengers kit for Claude Code

Seven agents, six skills, and a contract gate. Two modes: agentic coding with Claude Code and the seven agents, or manual coding by you. Manual edits meet the same rules through CI, lint, and boundary checks once you install them.

## The team

| Agent | Job | Can edit |
| --- | --- | --- |
| `captain-america` | Runs the session, routes work, holds the order | Nothing |
| `iron-man` | Architecture and contracts | `docs/contracts`, `docs/adr` |
| `thor` | Domain, data, state, mutation queues, ui/ widgets, wiring | Code |
| `hulk` | Behavior-preserving refactors, extracting `ui/` | Code |
| `hawkeye` | Tests and bug reproduction | Test files |
| `black-widow` | Independent review with a PASS or BLOCK verdict | Nothing |
| `nick-fury` | CI/CD, containers, deployment config, monitoring, runbooks | Delivery files only |

## Install

1. Copy `.claude/`, `.github/`, `scripts/`, `AGENTS.md`, `CLAUDE.md`, and `docs/` to the repo root. If you already have `.claude/settings.json` or `CLAUDE.md`, merge them.
2. Fill in the top section of `AGENTS.md`.
3. Install the checks: see "Install the checks" in `.claude/skills/ui-isolation/SKILL.md`.
4. Restart Claude Code and accept the workspace trust prompt, or the role fences on `iron-man` and `hawkeye` will not run.

Add `.claude/settings.local.json` to `.gitignore`, because it holds your personal paths. Requires bash and jq, which the hooks use (Git Bash on Windows). They block with a clear message if jq is missing.

## Daily flow

```text
"Add order cancellation"
 captain-america -> iron-man writes docs/contracts/orders.md (draft)
 You review it and set status: approved yourself
 thor builds logic, hawkeye writes tests
 thor builds the UI against the contract, black-widow gives the verdict
```

To skip the team for one session, run `claude --agent claude`. To stop defaulting to it, remove `"agent"` from `.claude/settings.json`.

## Production stays with you

Nick Fury prepares delivery changes and runbooks but does not run them. `.claude/settings.json` denies deploy commands such as `terraform apply`, `kubectl apply`, `helm upgrade`, and `docker push` for every agent. Add any others your platform uses.

## What enforces what

| Rule | Enforced by | Binds manual edits? |
| --- | --- | --- |
| No code for a new feature before an approved contract | `contract-gate.sh` | No, but `check-contracts.sh` in CI does |
| Only you approve a contract | `contract-gate.sh` | No, it is a hook for Claude only |
| Agents cannot edit the hooks, settings, or gate scripts | `contract-gate.sh` | No, it is a hook for Claude only |
| Architect, tester, and DevOps stay in their files | `path-fence.sh` | No, it is a hook for Claude only |
| `ui/` is pure | `ui_purity`, `ui_stateless`, or dependency-cruiser and ESLint | Yes, once installed in your lint and CI jobs (agent-gates.yml does not run them) |
| New feature code has an approved contract | `scripts/check-contracts.sh` in CI | Yes |
| Coordinator and reviewer cannot edit | Agent tool lists | No |

Hooks are guardrails, not a security boundary: they cover the Edit and Write tools, not everything Bash could do. CI is the authoritative gate. `.github/workflows/agent-gates.yml` re-checks contracts on every pull request. Keep your stack's lint, boundary, and test jobs alongside it, then make them all required with branch protection on `main`.

Read any pull request that touches `.claude/`, `.github/`, or `scripts/` closely, because Bash can still reach those files. Once a second person joins, add them and `docs/contracts/` to `CODEOWNERS` so changes need review.