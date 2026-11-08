# Supply chain

Scope: verifiable checks for what the project pulls in and how it is built: lockfiles, the dependency audit gate, adding a dependency, GitHub Actions, and container images. The rules are owned by `devops-engineering` ([SKILL.md](../../devops-engineering/SKILL.md), CI and Artifacts) and by `react-standards` [11-production-readiness.md](../../react-standards/references/11-production-readiness.md) "Dependency and release operations". Stack CI detail is in `flutter-standards` [16-production-and-release.md](../../flutter-standards/references/16-production-and-release.md) 11.2, `react-standards` [12-enforcing-this-automatically.md](../../react-standards/references/12-enforcing-this-automatically.md), and `nestjs-standards` [11-enforcing-this-automatically.md](../../nestjs-standards/references/11-enforcing-this-automatically.md). Each item names its rule's home and adds how to verify it. Items with no home in a standard are marked kit rule.

The items are kit checks, not a restatement of the public sources. The mapping below ties them to the OWASP Top 10 CI/CD Security Risks (CICD-SEC-1 to CICD-SEC-10) and the OpenSSF Scorecard check names, so a finding can cite both:

| Kit item | OpenSSF Scorecard check | OWASP CI/CD risk |
| --- | --- | --- |
| SEC-SUP-03 | Vulnerabilities | none |
| SEC-SUP-05, SEC-SUP-06 | none | CICD-SEC-3 |
| SEC-SUP-07 | Dependency-Update-Tool | none |
| SEC-SUP-08 | Pinned-Dependencies | none |
| SEC-SUP-09 | Token-Permissions | CICD-SEC-5 |
| SEC-SUP-11 | Dangerous-Workflow | CICD-SEC-4 |
| SEC-SUP-12, SEC-SUP-13 | none | CICD-SEC-9 |

An agent never adds a dependency without a stated requirement (AGENTS.md rule 6), and never runs an automatic fix: `npm audit fix` and `pnpm audit --fix` are denied in `.claude/settings.json`. An agent reports the finding; Dave or a dependency PR changes the lockfile.

## Lockfiles and installs

- [ ] SEC-SUP-01 Every lockfile is committed (`package-lock.json` or the project's equivalent, `pubspec.lock`) and CI installs from it without resolving: `npm ci`, `flutter pub get --enforce-lockfile` (`devops-engineering` CI, `flutter-standards` 16 11.2). Verify: `git ls-files | grep -E "(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|pubspec\.lock)$"`; `grep -rnE "npm install|pub get" .github/workflows` and confirm every install in CI is the locked form.
- [ ] SEC-SUP-02 The lockfile changes only in a dependency pull request, never as a side effect of a feature branch (`react-standards` 11, "When does the lockfile change?"). Verify: on a feature diff, `git diff --stat <base>...HEAD -- '*lock*'` is empty, or the diff is a dependency PR.

## Audit gate

- [ ] SEC-SUP-03 A dependency audit runs on every pull request and blocks on high and critical findings: `npm audit --audit-level=high` for Node (`react-standards` 12, `nestjs-standards` 11), the OSV scan of `pubspec.lock` for Flutter (`flutter-standards` 16 11.2). Verify: the step is in the workflow and the job is required on `main`; run the same command locally and report its output.
- [ ] SEC-SUP-04 The only way past the audit gate is a documented exception with the advisory id, the reason, an owner, and an expiry date, and remediation follows the project's deadlines (defaults in `react-standards` section 10 (`11-production-readiness.md`): critical within 48 hours, high within 7 days; `nestjs-standards` section 8 (`09-security-baseline.md`) last item). Verify: read the exceptions file each gate uses (such as `osv-scanner.toml` or `.trivyignore`); every entry has all four fields and no expiry date is in the past.

## Adding a dependency

- [ ] SEC-SUP-05 Every new direct dependency is justified in its pull request against this checklist (kit rule): the stated requirement it meets; that no existing dependency or platform API meets it; maintenance (recent releases, open security advisories); install scripts; a name close to a popular package (typosquatting); licence compatible with the project; and the transitive packages it adds. Verify: the PR description answers each line; `git diff <base>...HEAD -- package-lock.json | grep -c '"resolved"'` gives the number of packages added; `git diff <base>...HEAD -- package-lock.json | grep -n '"hasInstallScript": true'` lists new install scripts, each named in the PR.
- [ ] SEC-SUP-06 The dependency's exact name is checked against the package the requirement names, character by character, before it is added (kit rule). Verify: compare the name in the manifest diff with the name in the package's own documentation link given in the PR; a mismatch is a BLOCK.
- [ ] SEC-SUP-07 Automated update PRs (Dependabot or Renovate) cover GitHub Actions and every package ecosystem in the repo (`devops-engineering` CI, `flutter-standards` 16 11.2 `dependabot.yml`). Verify: `.github/dependabot.yml` or the Renovate config lists `github-actions` and each ecosystem with a manifest in the repo.

## GitHub Actions

- [ ] SEC-SUP-08 Every third-party `uses:` is pinned to a 40-character commit SHA with the version in a trailing comment (`devops-engineering` CI). Verify: `grep -rnE "uses:[[:space:]]*[^.][^@]*@" .github/workflows | grep -vE "@[0-9a-f]{40}([[:space:]]|$)"` returns nothing, and `grep -rn '@0\{40\}' .github/workflows` prints nothing before merge (no unreplaced zero-SHA `PIN` placeholder).
- [ ] SEC-SUP-09 Every workflow sets `permissions: contents: read` at the top and grants more per job only where that job needs it (`devops-engineering` CI). Verify: each file in `.github/workflows/` has a top-level `permissions:` block; each wider grant sits on one job and the job's steps use it.
- [ ] SEC-SUP-10 No user-controlled `github.*` value (titles, bodies, branch names, commit messages) is interpolated into `run:`; it passes through `env:` (`devops-engineering` CI). Verify: `grep -rnE '\$\{\{[[:space:]]*github\.(event|head_ref)' .github/workflows` and confirm no hit sits inside a `run:` block.
- [ ] SEC-SUP-11 A workflow triggered by `pull_request_target` or `workflow_run` never checks out or runs code from the pull request's head with the workflow's secrets or write token (kit rule). Verify: `grep -rlnE "pull_request_target|workflow_run" .github/workflows`; for each hit, trace every `actions/checkout` `ref:` and every later `run:` step.

## Images and artifacts

- [ ] SEC-SUP-12 Once an image ships, its base image is pinned by digest and the image is scanned in CI for known vulnerabilities (`devops-engineering` Artifacts). Verify: `grep -nE "^FROM" Dockerfile*` and confirm each shipped stage uses `@sha256:`; the Trivy image gate (`devops-engineering` `assets/ci-nestjs.yml`, `assets/ci-web.yml`) is in the workflow and required.
- [ ] SEC-SUP-13 The artifact is built once, tagged with the commit SHA, never only `latest`, and the same artifact is promoted through environments (`devops-engineering` Artifacts). Verify: read the build and deploy workflows; the tag comes from the commit SHA and no deploy step rebuilds.
- [ ] SEC-SUP-14 Images run as non-root, contain no secrets, and the runtime image has no dev dependencies (`devops-engineering` Artifacts, `assets/Dockerfile.nestjs`). Verify: `hadolint Dockerfile`; `docker build -t app:test .` then `docker run --rm --entrypoint id app:test` prints a non-zero uid; `docker history --no-trunc app:test` shows no secret build argument.

## Sources

- OWASP Top 10 CI/CD Security Risks, CICD-SEC-1 to CICD-SEC-10, read 2026-11-08. https://owasp.org/www-project-top-10-ci-cd-security-risks/
- OpenSSF Scorecard v5.6.0 of 2026-10-12, checks documentation, read 2026-11-08. https://github.com/ossf/scorecard/blob/main/docs/checks.md
- SLSA (Supply-chain Levels for Software Artifacts) v1.2, read 2026-11-08. https://slsa.dev/
- GitHub Docs, "Secure use reference" (formerly "Security hardening for GitHub Actions"), living document, read 2026-11-08. https://docs.github.com/en/actions/reference/security/secure-use
- Kit standards: `devops-engineering` CI and Artifacts, `react-standards` 11 and 12, `nestjs-standards` 09 and 11, `flutter-standards` 16 11.2, linked in the scope paragraph.
