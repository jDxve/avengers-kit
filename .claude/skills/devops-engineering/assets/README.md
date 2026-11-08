# devops-engineering assets

Templates for delivery work. Each is a starting point: copy it into the project, replace every `PIN` and `<placeholder>`, then validate it (see Validate). Agents write and validate these files; they never run Fastlane, a release workflow, or a deploy, and never push the tag that starts one (AGENTS.md rule 10; settings deny `fastlane *`, `gh workflow run*`, `docker push*`).

## Index

| File | What it is | Copy to | Replace |
| --- | --- | --- | --- |
| [Dockerfile.nestjs](Dockerfile.nestjs) | NestJS image: `build`, `migrate` (keeps `drizzle-kit`, run once per deploy as a job), and `runtime` stages, non-root | `Dockerfile` | Node major if the project pins another; pin each `FROM` by digest once the image ships |
| [dockerignore](dockerignore) | Keeps the repo's git data, env files, `.npmrc`, private key files, docs, and tests out of the build context | `.dockerignore` | For Next.js add `.next` and `e2e` |
| [Dockerfile.nextjs](Dockerfile.nextjs) | Next.js image from `output: 'standalone'`: `deps`, `build`, `runtime` stages, non-root | `Dockerfile` | As for NestJS; see `react-standards` [17-nextjs-app-router.md](../../react-standards/references/17-nextjs-app-router.md) section 7 |
| [ci-flutter.yml](ci-flutter.yml) | PR checks: lockfile install, format, `dart analyze --fatal-infos`, `check_architecture.dart`, `flutter test`, Gradle wrapper jar validation. Also callable by `release-mobile.yml` | `.github/workflows/` | Flutter version; `PIN` lines; add the other 11.2 steps as the project's tools exist |
| [ci-web.yml](ci-web.yml) | PR checks for React or Next.js in the 11.9 order: `npm ci`, typecheck, lint, boundaries, API types, tests, build, size, env, e2e, optional runtime image build and Trivy scan (self-hosted Next.js) | `.github/workflows/` | `API_SCHEMA`; `PIN` lines; drop steps the adoption profile does not use; delete the image steps if nothing ships as a container |
| [ci-nestjs.yml](ci-nestjs.yml) | PR checks: `npm ci`, typecheck, lint, dependency-cruiser, unit tests, migrations and e2e against a PostgreSQL service container, `openapi:check`, `docker build` of `runtime` and `migrate`, Trivy scan of both images | `.github/workflows/` | PostgreSQL major; test env keys; `PIN` lines |
| [ci-security.yml](ci-security.yml) | Secret scan (gitleaks) and dependency audit (`npm audit`, osv-scanner for `pubspec.lock` and `Gemfile.lock`), on pull requests, pushes to `main`, weekly, and by hand | `.github/workflows/` | Delete the audit job for a stack the repo lacks; `GITLEAKS_LICENSE` for an organization repo; `PIN` lines |
| [dependabot.yml](dependabot.yml) | Weekly updates with a 7-day cooldown for GitHub Actions, npm, pub, Bundler, and Docker | `.github/dependabot.yml` | Delete ecosystems the repo lacks; set directories |
| [release-mobile.yml](release-mobile.yml) | On a `v*` tag: re-run `ci-flutter.yml`, then build and upload to Play internal testing and TestFlight behind the `mobile-release` environment | `.github/workflows/` | Flutter and Java versions; iOS signing steps; symbol upload; `PIN` lines; the environment and secrets listed in its header |
| [fastlane/Fastfile](fastlane/Fastfile) | `android internal` and `ios internal` lanes. Credentials from environment variables only | `fastlane/Fastfile` | Artifact paths |
| [fastlane/Appfile](fastlane/Appfile) | App identifiers, no credentials | `fastlane/Appfile` | Identifiers |
| [runbook-template.md](runbook-template.md) | Runbook for anything Dave runs against a live system | `docs/runbooks/<operation>.md` | Every field |

## Rules every workflow template holds

- Every third-party `uses:` is pinned to a 40-character commit SHA with the version in a comment (`devops-engineering` CI; `security-engineering` `SEC-SUP-08`; lint K8). The kit has one verified SHA, `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`, reused as is. Every other action uses the placeholder `0000000000000000000000000000000000000000 # PIN <owner>/<action> <version>`, which cannot resolve, so an unreplaced template fails closed instead of running an unpinned action. No agent writes a SHA it has not verified.
- To replace a `PIN`: resolve the tag in the action's own repository, not a fork. `git ls-remote https://github.com/<owner>/<action> refs/tags/<version> 'refs/tags/<version>^{}'` prints the commit; for an annotated tag use the `^{}` line. Paste the 40 characters, keep the version comment, and let Dependabot propose later updates. For an action in a subdirectory, such as `gradle/actions/wrapper-validation`, resolve the tag in its repository (`gradle/actions`).
- Before pasting, check that the tag's commit matches the release notes and the release date, and prefer a release at least a few days old.
- `permissions: contents: read` at the top. A job gets more only where it needs it, with a comment saying why (`SEC-SUP-09`). Today only `ci-security.yml` `secrets` adds `pull-requests: read`.
- No user-controlled `github.*` value inside `run:`; values pass through `env:` (`SEC-SUP-10`).
- `actions/checkout` sets `persist-credentials: false`, so later steps do not hold the token in the git config.
- Locked installs only: `npm ci`, `flutter pub get --enforce-lockfile` (`SEC-SUP-01`).

## Adoption

- The `ci-security.yml` jobs must be required status checks on `main`. Dave sets this in the repository settings. A pin that fails is fixed by resolving the right SHA, never by replacing it with a tag.
- Once `ci-security.yml` is on `main`, run it once by `workflow_dispatch` so gitleaks scans the full history, not only the commit range of new pushes.
- Changes to `.github/workflows/`, `.gitleaks.toml`, `.gitleaksignore`, `osv-scanner.toml`, `.trivyignore`, `trivy.yaml`, `.trivyignore.yaml`, `scripts/`, and inline `gitleaks:allow` comments are security changes. Cover them with CODEOWNERS and required review. Dave sets this.
- Dave enables Dependabot alerts and Dependabot security updates. The 7-day cooldown delays version updates only; GitHub documents that it never applies to security updates.
- Flutter Android: add `distributionSha256Sum=<sha256>` next to `distributionUrl` in `android/gradle/wrapper/gradle-wrapper.properties`. Copy the value from https://gradle.org/release-checksums/ for the exact version and type (`-all` or `-bin`), and change both lines in the same pull request. Gradle fails the build on a mismatch, and checks only when the distribution is not already downloaded. Recheck after a Flutter upgrade.
- The Trivy `version:` input is bumped by hand in its own pull request, to an immutable release at least a few days old. Never use `latest`.

## Validate

Run what applies, and say plainly when a tool is missing (`devops-engineering` SKILL.md, "Validate before reporting"):

```bash
actionlint .github/workflows/*.yml
grep -rn '@0\{40\}' .github/workflows   # must print nothing before merge: no PIN left unreplaced
hadolint Dockerfile
docker build --target runtime -t app:test .
docker build --target migrate -t app:migrate-test .   # NestJS only
trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 app:test   # optional, if Trivy is installed
```

Passing these proves the files are valid, not that a release works. A placeholder `PIN` fails when the workflow runs, by design.

## Known limits

- `actions/checkout` is pinned to v7.0.1 (`node24`). GitHub removed Node 20 from hosted runners on 2026-09-23. v7 refuses fork pull request checkout under `pull_request_target` and `workflow_run`; no template uses those triggers.
- `subosito/flutter-action` is a composite action that itself uses `actions/cache@v5` by tag, so pinning the outer action does not pin that step. GitHub's secure-use reference describes workflow dependency lockfiles as the control for transitive actions.
- `gitleaks-action` needs a `GITLEAKS_LICENSE` secret for repositories owned by an organization, per its README. A personal repository needs none.
- osv-scanner exits 1 when it finds any vulnerability, and the v2.7.0 docs read for this template show no severity threshold like `npm audit --audit-level`. Accepted exceptions go in `osv-scanner.toml` under `[[IgnoredVulns]]` with `id`, `reason`, and `ignoreUntil`; the owner that `SEC-SUP-04` also requires goes in a comment on the entry.
- Wrapper validation checks committed `gradle-wrapper.jar` files only. A default Flutter project commits none: `flutter_tools` injects the wrapper from the Flutter SDK cache during the build, so that jar's trust rests on the pinned Flutter SDK.
- Trivy scans images only when `ci-nestjs.yml` or `ci-web.yml` runs. A CVE published after the last run on `main` is found on the next run, not weekly. A scheduled rescan of the shipped image needs the registry, which is a project decision.
- `trivy-action` had its tags hijacked on 2026-03-19 (GHSA-69fq-xp46-6x23). The SHA pin protects the action and the actions it pins inside. The Trivy binary is fetched by the `version:` input and checked against the checksums file of the same immutable release; there is no signature check. Every Trivy step sets `cache: 'false'`, because a cache hit restores the binary and database without any check.

## Sources

- GitHub Docs, read 2026-11-08 (living documents): "Workflow syntax for GitHub Actions" (`permissions`, `concurrency`), https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax; "Secure use reference", https://docs.github.com/en/actions/reference/security/secure-use; "Deployments and environments", https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments; "Creating PostgreSQL service containers", https://docs.github.com/en/actions/how-tos/use-cases-and-examples/using-containerized-services/creating-postgresql-service-containers; "Dependabot options reference", https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference; "Push protection", https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection; "Reuse workflows", https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows; "About Dependabot security updates", https://docs.github.com/en/code-security/concepts/supply-chain-security/about-dependabot-security-updates
- GitHub Changelog, "Deprecation of Node 20 on GitHub Actions runners", 2025-09-19 with editor's notes to 2026-08-25, read 2026-11-08: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/
- Action repositories, `action.yml` and README at the tags named in each `PIN`, read 2026-11-08: actions/checkout v7.0.1, actions/setup-node v7.1.0, actions/setup-java v6.2.0, subosito/flutter-action v2.23.0, ruby/setup-ruby v1.338.0, gitleaks/gitleaks-action v3.0.0 (README and `src/gitleaks.js`), gradle/actions v6.4.1, aquasecurity/trivy-action v0.36.0
- gradle/actions v6.4.1, `wrapper-validation/action.yml` and `docs/wrapper-validation.md`, read 2026-11-08: https://github.com/gradle/actions/tree/v6.4.1
- Gradle User Manual, "Gradle Wrapper", read 2026-11-08: https://docs.gradle.org/current/userguide/gradle_wrapper.html
- flutter/flutter stable, `templates/app/android.tmpl/.gitignore` and `lib/src/android/gradle_utils.dart` in `flutter_tools`, read 2026-11-08: https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/templates/app/android.tmpl/.gitignore; https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/android/gradle_utils.dart
- aquasecurity/trivy-action v0.36.0, `action.yaml` and README, read 2026-11-08: https://github.com/aquasecurity/trivy-action/tree/v0.36.0
- Trivy v0.76.2 docs (filtering, others "Exit Code", `trivy image` CLI reference), read 2026-11-08: https://github.com/aquasecurity/trivy/tree/v0.76.2/docs
- Advisories, read 2026-11-08: GHSA-69fq-xp46-6x23, https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23; GHSA-9p44-j4g5-cfx5, https://github.com/aquasecurity/trivy-action/security/advisories/GHSA-9p44-j4g5-cfx5
- osv-scanner v2.7.0 docs (installation, usage, scan source, supported lockfiles, configuration), read 2026-11-08: https://github.com/google/osv-scanner/tree/v2.7.0/docs
- Go documentation, "Go Toolchains" (`GOTOOLCHAIN=auto`), read 2026-11-08: https://go.dev/doc/toolchain
- npm CLI documentation, `npm audit`, latest branch, read 2026-11-08: https://github.com/npm/cli/blob/latest/docs/lib/content/commands/npm-audit.md
- fastlane docs (fastlane 2.241.2 on RubyGems), `upload_to_play_store`, `upload_to_testflight`, `app_store_connect_api_key`, Appfile, Android setup, read 2026-11-08: https://docs.fastlane.tools/actions/upload_to_play_store/ and the sibling pages
- Next.js documentation 16.4.5, `output` and Self-Hosting, and the official `examples/with-docker/Dockerfile` at commit 62e0b0a of 2026-10-02, read 2026-11-08: https://nextjs.org/docs/app/api-reference/config/next-config-js/output, https://github.com/vercel/next.js/tree/canary/examples/with-docker
- Flutter documentation, "Build and release an iOS app" (`flutter build ipa`, `--export-options-plist`), reflects Flutter 3.47, page last updated 2026-07-31, read 2026-11-08. https://docs.flutter.dev/deployment/ios
- Kit standards: `devops-engineering` SKILL.md, `security-engineering` 40-supply-chain.md, `flutter-standards` 16 11.2, `react-standards` 03, 11, 12 (11.4, 11.9), `nestjs-standards` 11, `api-contract` 01.
- Not read:
  - actionlint and hadolint documentation.
  - The Docker Official Image docs for `node` and `postgres`.
