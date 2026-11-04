## 10. Production readiness

### Correctness
- [ ] Every data-dependent view implements loading, error, empty, and loaded
- [ ] Async races handled per section 6, with that section's test table in place
- [ ] Error boundaries per route, global `error` and `unhandledrejection` handlers installed
      at boot, and client errors reaching the tracker with the release version attached
- [ ] Forms guard double submission, and irreversible actions send an idempotency key
- [ ] Nothing depends on a timezone or locale inherited from the browser by accident:
      formatting is explicit, and the zone comes from the data or the user's setting

### Experience
- [ ] Accessibility checklist in section 7 passed, including one keyboard-only run
- [ ] Works at phone width with no horizontal page scroll
- [ ] Bundle budget enforced in CI, with route-level splitting in place
- [ ] Core Web Vitals measured from real users
- [ ] Offline or flaky-network behavior is defined: what the user sees, and what retries

### Operations
- [ ] Env configuration validated at build or boot, failing loudly on a missing value, and
      that failure proven in CI (11.7)
- [ ] Source maps uploaded to the error tracker, and not served publicly unless intended
- [ ] A rollback path for the frontend, exercised once
- [ ] Cache headers and build hashing correct, so a deploy cannot leave a user on a stale
      bundle talking to a new API
- [ ] Feature flags for anything risky, with a documented off switch

### Dependency and release operations

Pinning the toolchain (section 2) decides what you build with. This decides who keeps it
moving, which is the half that rots. Record each of these with a name against it.

| Question | A defensible default |
|---|---|
| Who owns routine dependency updates? | One named person, rotating quarterly. Automated PRs grouped by ecosystem, merged weekly when CI is green |
| How fast must a vulnerability be remediated? | Critical within 48 hours, high within 7 days, moderate at the next scheduled update. A documented exception with an expiry date is the only way past the audit gate |
| When does the lockfile change? | Only through a dependency PR, never as a side effect of a feature branch. `npm ci` in CI, so a drifted lockfile fails rather than resolves |
| What happens on a major upgrade of a tool section 11 depends on? | Re-run section 11 and update 11.9 before merging. ESLint, TypeScript, dependency-cruiser, and React each change behaviour the checks rely on |
| How do concurrent CI runs behave? | Cancel superseded runs on the same branch, never on the default branch. E2E and visual checks run on one concurrency group so they do not race for a shared environment |
| How is a bad release recovered? | Redeploy the previous build hash, which is a deploy and not a revert PR. Exercised on a schedule, not discovered during the incident |
| Who can bypass the gate? | Name them, or nobody. An unlogged bypass is the gate's real policy |

The recovery row is the one to actually rehearse. A rollback path that has never been run is
a plan, and plans fail at three in the morning.

### Quality gate before merge
- [ ] `npm run build` succeeds. The type checker alone does not catch a bundler resolution
      failure, a bad dynamic import, or server-only code pulled into the client graph
- [ ] `tsc --noEmit` clean
- [ ] Lint clean, including `react-hooks` and `jsx-a11y`
- [ ] Boundary rules pass, and the boundary fixtures still fail (11.1)
- [ ] Generated API types are current (11.6)
- [ ] Tests for the touched feature pass, including the four states
- [ ] New business logic has a unit test
- [ ] No new `any`, `console.log`, `eslint-disable`, `dangerouslySetInnerHTML`, or
      cross-feature internal import
- [ ] Bundle size diff reviewed when a dependency was added

---

