# Kit changelog

Changes to the kit itself. Each standard records its own rule changes.

## 2026-11-08

- Added the database-drizzle, refactoring-playbook, observability-and-debugging, and git-workflow skills, preloaded them for ant-man and hulk, preloaded testing-strategy for spider-man and quicksilver and security-engineering for black-panther, and added the exploratory testing reference to testing-strategy. Agents never run a database command; an agent may run the NestJS e2e suite only on a database created for that run and thrown away afterwards.
- Added the ui-ux-design skill and preloaded it for shuri, added the Next.js App Router reference to react-standards, and added the CI, Dependabot, Next.js Dockerfile, mobile release, and Fastlane templates to devops-engineering with an assets index. The security template uses npm audit, osv-scanner, and gitleaks, with GitHub secret scanning push protection as a complement.
- Added the feature-recipes skill with eight recipes: push notifications, payments (provider-neutral), file uploads, realtime, background jobs, caching with Redis, internationalization, and offline sync.
- Pinned actions/checkout to v7.0.1 (node24) in all delivery templates, added Gradle wrapper validation to the Flutter CI template, a 7-day Dependabot cooldown on version updates, and Trivy image scans to the NestJS and web CI templates. Dockerfile.nestjs and Dockerfile.nextjs run app code root-owned and read-only.
- Hardened release-mobile.yml and ci-security.yml from the security review, applied the citation convention to api-contract and quicksilver, and pinned the flutter-standards CI examples.

## 2026-11-04

- Removed the Gemini workflow. Thor builds `ui/` widgets from the contract.
- Set Drizzle and Zod as the fixed stack (ADR-012), with strict request schemas on every nested object.
- Set Riverpod as the Flutter default (ADR-011). `ui/` stays pure whichever library is used.
- Added a `migrate` stage to the NestJS Dockerfile.
- Added visual bug routing to Captain America.
- Fixed hook path handling on Windows, and hooks now run through `bash`.
- Added the no agent attribution rule: commits and pull requests carry only Dave's identity.
- Added agents: vision (requirements and analysis), shuri (UI/UX design), ant-man (database), quicksilver (performance), spider-man (exploratory testing), and black-panther (security), with path-fence profiles for the three that write.
- Added the security-engineering, api-contract, and testing-strategy skills.
