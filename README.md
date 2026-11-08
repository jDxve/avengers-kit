# Avengers kit for Claude Code

Thirteen agents, fifteen skills, and a contract gate. Two modes: agentic coding with Claude Code and the thirteen agents, or manual coding by you. Manual edits meet the same rules through CI, lint, and boundary checks once you install them.

## The team

| Agent | Job | Can edit |
| --- | --- | --- |
| `captain-america` | Runs the session, routes work, holds the order | Nothing |
| `vision` | Requirements and analysis: inspects the code, states the facts and constraints, breaks down the ask | Nothing |
| `iron-man` | Architecture and contracts | `docs/contracts`, `docs/adr` |
| `shuri` | UI/UX design only: flows, layouts, states, copy, tokens, accessibility, written into the contract | `docs/contracts` (existing files), `docs/design` |
| `thor` | Domain, data, state, mutation queues, ui/ widgets, wiring | Code |
| `ant-man` | Drizzle schema, migrations, indexes, query and transaction review, data integrity | Schema, migrations, `src/database`, `drizzle.config.*` |
| `hulk` | Behavior-preserving refactors, extracting `ui/` | Code |
| `hawkeye` | Tests and bug reproduction | Test files |
| `quicksilver` | Performance budgets, profiling, load tests, bundle size, startup | Performance and load test files, budget configs |
| `spider-man` | Exploratory testing: edge cases, malformed input, races, undocumented states | Nothing |
| `black-widow` | Independent review with a PASS or BLOCK verdict | Nothing |
| `black-panther` | Threat models, dependency review, vulnerability assessment and security audits, findings labelled verified or theoretical | Nothing |
| `nick-fury` | CI/CD, containers, deployment config, monitoring, runbooks | Delivery files only |

## Skills

Skills live in `.claude/skills/`. A preloaded skill loads with the agent on every task; any agent can load any skill on demand.

| Skill | Purpose | Preloaded by |
| --- | --- | --- |
| `contract-first` | How to write a feature contract before any code | `iron-man`, `shuri` |
| `ui-isolation` | Pure `ui/` widgets, and the lint and boundary checks that enforce them | `thor`, `hulk`, `shuri`, `black-widow` |
| `flutter-standards` | Dave's Flutter standard | none |
| `react-standards` | Dave's React and Next.js standard | none |
| `nestjs-standards` | Dave's NestJS standard | none |
| `devops-engineering` | CI/CD, containers, deployments, monitoring, runbooks | `nick-fury` |
| `security-engineering` | Verifiable security checklists per stack, threat modeling, incident basics | `iron-man`, `thor`, `black-widow`, `nick-fury`, `black-panther` |
| `api-contract` | Publishing the NestJS OpenAPI contract and consuming it from web and Flutter | `iron-man`, `thor` |
| `testing-strategy` | Which test proves what, per stack, and how to see it fail | `hawkeye`, `black-widow`, `spider-man`, `quicksilver` |
| `database-drizzle` | Drizzle schema, migrations and their review, indexes, transactions, tenant scoping | `ant-man` |
| `refactoring-playbook` | Behavior-preserving refactors in small steps, and how to prove nothing changed | `hulk` |
| `observability-and-debugging` | Structured logs, request ids, turning a log into a failing test, profiling | none |
| `git-workflow` | Branches, commit messages, pull request descriptions, no agent attribution | none |
| `ui-ux-design` | User flows, every state, copy, design tokens, accessibility, responsive layout, Figma, and the handoff into the UI Contract section | `shuri` |
| `feature-recipes` | Design recipes for push notifications, payments, file uploads, realtime, background jobs, Redis caching, i18n, and offline sync (push and offline sync: mobile only) | none |

## Install

1. Copy `.claude/`, `.github/`, `scripts/`, `AGENTS.md`, `CLAUDE.md`, and `docs/` to the repo root. If you already have `.claude/settings.json` or `CLAUDE.md`, merge them.
2. Fill in the top section of `AGENTS.md`.
3. Install the checks: see "Install the checks" in `.claude/skills/ui-isolation/SKILL.md`.
4. Restart Claude Code and accept the workspace trust prompt, or the role fences on `iron-man`, `hawkeye`, `nick-fury`, `shuri`, `ant-man`, and `quicksilver` will not run.

Add `.claude/settings.local.json` to `.gitignore`, because it holds your personal paths. Requires bash and jq, which the hooks use (Git Bash on Windows). They block with a clear message if jq is missing.

## Daily flow

```text
"Add order cancellation"
 captain-america -> vision reports the facts and the open questions
 iron-man writes docs/contracts/orders.md (draft)
 shuri writes the design into the contract
 You review it and set status: approved yourself
 thor builds logic, hawkeye writes tests
 thor builds the UI against the contract, black-widow gives the verdict
```

To skip the team for one session, run `claude --agent claude`. To stop defaulting to it, remove `"agent"` from `.claude/settings.json`.

## Production stays with you

Nick Fury prepares delivery changes and runbooks but does not run them. `.claude/settings.json` denies deploy commands such as `terraform apply`, `kubectl apply`, `helm upgrade`, and `docker push` for every agent. Add any others your platform uses. No agent runs a migration: `drizzle-kit push`, `migrate`, `pull`, and `studio` are denied for every agent, and you run migrations yourself. The one exception: an agent may run the NestJS e2e suite, which applies migrations, only when the suite creates its database for that run and throws it away afterwards.

## What enforces what

| Rule | Enforced by | Binds manual edits? |
| --- | --- | --- |
| No code for a new feature before an approved contract | `contract-gate.sh` | No, but `check-contracts.sh` in CI does |
| Only you approve a contract | `contract-gate.sh` | No, it is a hook for Claude only |
| Agents cannot edit the hooks, settings, or gate scripts | `contract-gate.sh` | No, it is a hook for Claude only |
| Architect, designer, database engineer, tester, performance engineer, and DevOps stay in their files | `path-fence.sh` | No, it is a hook for Claude only |
| `ui/` is pure | `ui_purity`, `ui_stateless`, or dependency-cruiser and ESLint | Yes, once installed in your lint and CI jobs (agent-gates.yml does not run them) |
| New feature code has an approved contract | `scripts/check-contracts.sh` in CI | Yes |
| Coordinator, reviewer, analyst, security engineer, and exploratory tester cannot edit | Agent tool lists | No |

Hooks are guardrails, not a security boundary: they cover the Edit and Write tools, not everything Bash could do. CI is the authoritative gate. `.github/workflows/agent-gates.yml` re-checks contracts on every pull request. Keep your stack's lint, boundary, and test jobs alongside it, then make them all required with branch protection on `main`.

Read any pull request that touches `.claude/`, `.github/`, or `scripts/` closely, because Bash can still reach those files. Once a second person joins, add them and `docs/contracts/` to `CODEOWNERS` so changes need review.