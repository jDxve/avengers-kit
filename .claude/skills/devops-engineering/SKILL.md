---
name: devops-engineering
description: How to build and review CI/CD, containers, deployments, environments, migrations, monitoring, backups, rollback, and runbooks. Use for any delivery or operations work on Flutter, React, or NestJS projects.
paths:
  - ".github/**"
  - "**/Dockerfile*"
  - "**/docker-compose*"
  - "docs/runbooks/**"
---

# DevOps engineering

Start simple. One server with Docker, or an on-premises box, is a legitimate target. Choose tools from the project's real constraints, recorded in `docs/ops.md`.

## Record first

If `docs/ops.md` is missing, propose it with: deployment target, instance count, environments, secret store, who can deploy, who gets alerts, availability target, backup schedule and recovery target. Mark unknowns as unresolved. Never guess a value.

## Rules

**CI**

- Every pull request runs cheap checks first, and required jobs are protected on `main`.
- Default `permissions: contents: read`, and grant more per job.
- Pin every action to a commit SHA with the version in a comment, and let Dependabot or Renovate update them. Never interpolate `github.*` user-controlled values directly into `run:`; pass them through `env:`.
- Locked installs only: `npm ci`, a committed `pubspec.lock`.
- Secret scanning and a dependency audit run on every pull request.

**Artifacts**

- Build once and promote the same artifact through environments. Tag it with the commit SHA, never only `latest`.
- Containers use multi-stage builds, run as non-root, and contain no secrets. The runtime image has no dev dependencies. A NestJS project also builds the `migrate` target, which keeps `drizzle-kit` and is run once per deploy as a job, never as a service.
- Once an image ships, pin its base image by digest and scan it in CI for known vulnerabilities.
- Mobile store uploads run from CI behind a protected environment that requires Dave's approval: internal testing or TestFlight first, production only after he promotes it. Agents write the workflow and Fastlane files and never run them. Add these per app, because they need its signing setup and store accounts.

**Config and secrets**

- Config comes from the environment and is validated at boot. `.env.example` lists every key with no real values.
- Secrets live in the platform's secret store with a written rotation procedure. Production and staging never share them.

**Database**

- Migrations are a separate, controlled step, never run automatically by each app instance. For NestJS, the step is `drizzle-kit migrate` from the `migrate` image target (`docker build --target migrate`), tagged with the same commit SHA as the runtime image, with the database URL passed from the secret store. `drizzle-kit push` is allowed only against a local disposable database, never a shared, CI, staging or production one, and any PR with schema changes includes the generated migration.
- Drizzle migrations are forward-only. Rolling back the app does not undo them, so the rollback is to redeploy the previous image, which the expand step keeps compatible, or to fix forward with a new migration. Restore from backup only for a destructive one, run by Dave.
- A change needing both schema and code uses expand, deploy, contract, so old code keeps working during the rollout.
- Say whether each migration is reversible. Back up before one that is not.

**Release**

- Every deploy has a health check that tests real dependencies, graceful shutdown, and a written rollback.
- Run the rollback at least once before you need it.
- Risky features sit behind a flag with an off switch.

**Observability**

- Use what the project's platform already gives you. Add Prometheus, Grafana, or similar only for a stated need.
- Structured logs with a request ID, error tracking with the release version, and alerts on symptoms users feel: error rate, latency, failed sign-ins, queue depth, and dead letters.
- Every alert names an owner and links a runbook.

**Backups**

- A backup counts only once a restore has been tested. Record the date and how long it took.

## By stack

| Stack | Read |
| --- | --- |
| Flutter | `flutter-standards`: `16-production-and-release.md` for flavors, CI, hardening, staged rollout, kill switches |
| React | `react-standards`: `11-production-readiness.md`, and 11.9 in `12-enforcing-this-automatically.md` |
| NestJS | `nestjs-standards`: `10-production-readiness.md`, `08-multi-instance-gotchas.md`, `11-enforcing-this-automatically.md` |

Mobile signing keys and store credentials never enter the repo. A shipped mobile build cannot be recalled, so its rollback is halt, kill switch, minimum version, and fix forward.

## Validate before reporting

Run what applies, and say plainly when a tool is missing:

```bash
actionlint
hadolint Dockerfile
docker build -t app:test .
docker build --target migrate -t app:migrate-test .
docker compose config --quiet
```

Passing these proves the config is valid, not that a deploy works. Say what can only be proven live.

## Assets

- [assets/Dockerfile.nestjs](assets/Dockerfile.nestjs) and [assets/dockerignore](assets/dockerignore): a starting point. Copy them to the repo root as `Dockerfile` and `.dockerignore`.
- [assets/runbook-template.md](assets/runbook-template.md): for anything Dave runs against a live system.
