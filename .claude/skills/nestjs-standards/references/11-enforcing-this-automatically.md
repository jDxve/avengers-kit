## 10. Enforcing this automatically

A standard nobody can run is a standard nobody follows. Most of sections 4, 8, and 9 are
mechanically checkable. Wire these up once and the review checklists shrink to the
judgment calls.

**Dependency cycles.** The single highest-value check, because cycles are what `forwardRef`
hides.

```bash
npx dependency-cruiser src --validate   # with a .dependency-cruiser.js ruleset
npx madge --circular --extensions ts src
```

A minimal ruleset that encodes section 3 and 4.5:

```js
// .dependency-cruiser.js
module.exports = {
  forbidden: [
    { name: 'no-circular', severity: 'error', from: {}, to: { circular: true } },
    { name: 'common-is-infra', severity: 'error',
      comment: 'common/ must not import domain code',
      from: { path: '^src/common' }, to: { path: '^src/modules' } },
    { name: 'no-deep-module-reach', severity: 'error',
      comment: 'cross-module imports go through the module root, not its internals',
      from: { path: '^src/modules/([^/]+)/' },
      to:   { path: '^src/modules/(?!$1)([^/]+)/(services|dto|schema)/' } },
  ],
};
```

**Lint rules that carry real weight.** Not style, correctness:

```
@typescript-eslint/no-explicit-any            : error
@typescript-eslint/no-floating-promises       : error   // the N+1 and lost-await class
@typescript-eslint/await-thenable             : error
no-console                                    : error
no-empty  (allowEmptyCatch: false)            : error
```

**Config validation.** The boot-time schema from 4.3 is itself the test. Add one CI step
that starts the app with a required variable removed and asserts a non-zero exit.

**Route protection.** A short script that walks the compiled route table and asserts every
route is either covered by the global auth guard or carries `@Public()`, printing the public
list so review is reading a diff rather than grepping. The same pass asserts non-public
routes declare authorization.

**Concurrency guards.** Section 6 says every guard has a test that runs two operations at
the same row. Make those tests the gate: a migration that adds a status or balance column
without a matching constraint, index, or concurrency test is a PR comment, not a merge.

**CI gate.** The minimum that makes the quality gate in section 9 real:

```yaml
- run: npm ci
- run: npx tsc --noEmit
- run: npm run lint
- run: npx dependency-cruiser src --validate
- run: npm audit --audit-level=high
- run: npm test                     # unit
- run: npm run test:e2e             # against a disposable database
- run: npm run openapi:check        # generated spec matches the committed one
```

**What to leave to judgment.** Cohesion, naming, whether a facade earns its place, whether a
service should split. Those are DEFAULT rules for a reason: a linter that enforces them
produces worse code, not better. Automate the rules with a single correct answer and leave
the rest to review.

---

