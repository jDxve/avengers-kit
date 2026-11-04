## 9. Production readiness

### Reliability
- [ ] `app.enableShutdownHooks()`, graceful shutdown drains in-flight requests and the pool
- [ ] Health endpoint checks real dependencies, not just process liveness
- [ ] Separate readiness and liveness probes if orchestrated
- [ ] Every outbound dependency has a timeout and a documented behavior when it fails
- [ ] Retries have backoff and a ceiling, and only wrap operations that are safe to repeat
      or are protected by an idempotency key
- [ ] Section 7 handled, or single-instance documented

### Data
- [ ] Atomic writes are transactional (4.4)
- [ ] Concurrency controls in place and tested (section 6)
- [ ] Migrations run through a controlled deploy step, with a rollback or forward-fix path
      written down. Not every data migration is safely reversible, so say which it is
- [ ] Indexes validated against real query plans, not added per column
- [ ] Audit trail on privileged mutations: role change, money, permissions, approvals
- [ ] Backup **and restore** tested, not just configured

### Delivery
- [ ] CI runs build, lint, tests, and a dependency audit on every PR
- [ ] Lockfile committed, and `npm ci`, not `npm install`, in CI
- [ ] Secret scanning in CI, so a pushed credential is caught at the PR rather than later
- [ ] Migrations staged ahead of code when a deploy needs both (expand, deploy, contract)
- [ ] Rollback path exists and has been exercised once
- [ ] Container runs as a non-root user

### Quality gate before merge
- [ ] Build clean, no TypeScript errors
- [ ] Lint clean
- [ ] Tests for the touched domain pass
- [ ] New business logic has a unit test
- [ ] No new `forwardRef`, `any`, `console.log`, or secret
- [ ] OpenAPI regenerated if the contract changed

---

