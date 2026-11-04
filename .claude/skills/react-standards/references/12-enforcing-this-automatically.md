## 11. Enforcing this automatically

A standard nobody can run is a standard nobody follows. Most of sections 3, 4, 7, and 9 are
mechanically checkable, and this section is the configuration that checks them.

**The rule this section runs on:** a check is not trusted until it has been watched to fail.
Every check below ships with a fixture that must trip it, and CI asserts both directions. A
green check that would stay green with the rule deleted is worse than no check, because it
buys confidence it has not earned.

### 11.1 Feature boundaries and cycles

The highest-value structural check, because a cycle or a deep cross-feature import is what
makes a later refactor expensive.

```bash
npm i -D dependency-cruiser typescript@^6
```

**Pin the TypeScript major deliberately.** dependency-cruiser needs the compiler to resolve
TypeScript imports, and its supported range is currently `>=2.0.0 <7.0.0`. Plain
`npm i -D typescript` installs the latest major, and when that major is outside the range,
depcruise does not error. It cruises **zero modules and exits 0**, so every boundary rule
silently stops running while CI stays green. The script below guards against this, and that
guard is the reason it exists.

```js
// .dependency-cruiser.cjs
module.exports = {
  forbidden: [
    {
      name: 'no-circular',
      severity: 'error',
      comment: 'A cycle between modules means a boundary is wrong.',
      from: {},
      to: { circular: true },
    },
    {
      name: 'shared-not-depend-on-features',
      severity: 'error',
      comment: 'components/, lib/ and hooks/ are shared layers; they never import a feature.',
      from: { path: '^src/(components|lib|hooks)/' },
      to: { path: '^src/features/' },
    },
    {
      name: 'no-cross-feature-internals',
      severity: 'error',
      comment: 'Import another feature from its root (features/x), never features/x/internals.',
      from: { path: '^src/features/([^/]+)/' },
      to: {
        path: '^src/features/([^/]+)/.+',
        pathNot: [
          '^src/features/$1/',                 // own internals: allowed
          '^src/features/[^/]+/index\\.tsx?$', // another feature's public entry: allowed
        ],
      },
    },
    {
      name: 'ui-is-presentational',
      severity: 'error',
      comment: 'features/x/ui takes props and fires callbacks. Wire state in features/x/components.',
      from: { path: '^src/features/([^/]+)/ui/' },
      to: {
        pathNot: [
          '^src/features/$1/ui/',
          '^src/features/$1/types\\.ts$',
          '^src/components/ui/',
          '^src/lib/format/',
          '^src/styles/',
          'node_modules/(react|react-dom|@types/react|clsx|lucide-react)/',
        ],
      },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    tsConfig: { fileName: 'tsconfig.json' },
    tsPreCompilationDeps: true,
  },
};
```

**On `tsPreCompilationDeps: true`.** It makes `import type` count as a dependency, which the
cross-feature rule needs, because a type-only reach into another feature's internals is still
coupling. The side effect is that `no-circular` will also flag type-only cycles, which are
harmless at runtime. Fix them anyway rather than deleting the rule; a type-only cycle is
usually a sign that a shared type belongs in a layer both features can see.

**The third rule is the one to get right, and the obvious way to write it is wrong.**
`to.path` supports backreferences to the capture group in `from.path`, but only through
`pathNot`. Expressing "a different feature" as a negative lookahead,
`to: { path: '^src/features/(?!$1)([^/]+)/.+' }`, does not work. Run against the fixtures
below it rejects a legal `features/orders → features/invoices/index.ts` import, which is
exactly the pattern this document tells you to use. It fails closed on correct code and
teaches people to disable the rule. (Verified; see 11.9.)

**The fixtures.** Note the shape: every rule above is anchored to `^src/`, so a fixture tree
must contain its own `src/` and depcruise must run with that tree as the working directory.
Fixtures placed somewhere the anchors cannot match produce zero modules, zero violations, and
a passing check.

```
fixtures/boundaries/
├── allowed/
│   ├── tsconfig.json
│   └── src/features/
│       ├── invoices/{index.ts, lib/y.ts}
│       └── orders/
│           ├── api/own-internals.ts     imports ../lib/rules      → must be ALLOWED
│           ├── lib/rules.ts
│           ├── public-entry.ts          imports ../invoices       → must be ALLOWED
│           └── index.ts
└── forbidden/
    ├── tsconfig.json
    └── src/
        ├── features/orders/deep-cross-feature.ts  imports ../invoices/lib/y → REJECT
        ├── lib/shared-to-feature.ts               imports ../features/orders → REJECT
        └── cycle/{a.ts, b.ts}                     import each other          → REJECT
```

Exclude `fixtures/` from the build, the type check, lint, and the test run. It contains
deliberately invalid code and will otherwise fail all four:

```jsonc
// tsconfig.json
{ "include": ["src"], "exclude": ["fixtures", "node_modules"] }
```

```js
// eslint.config.js
{ ignores: ['fixtures/**', 'dist/**', 'build/**', '.next/**'] }
```

**The script.** It asserts three things, and the third is the one teams skip:

```bash
#!/usr/bin/env bash
# scripts/verify-boundaries.sh
#   1. real src/ passes
#   2. the allowed fixtures pass      (the rules do not reject legal code)
#   3. the forbidden fixtures fail    (the rules actually reject illegal code)
# Every run also asserts depcruise walked a non-zero number of modules.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/.dependency-cruiser.cjs"
FIXTURES="$ROOT/fixtures/boundaries"

# Rules the forbidden fixtures must trip, one fixture file each.
EXPECTED_RULES=(no-circular shared-not-depend-on-features no-cross-feature-internals ui-is-presentational)

cruise() { # cruise <dir>  -> prints report on stdout, never aborts the script
  ( cd "$1" && npx --no-install depcruise src --config "$CONFIG" --output-type err 2>&1 ) || true
}

assert_cruised() { # assert_cruised <report> <label>
  if ! grep -qE '[1-9][0-9]* modules' <<<"$1"; then
    echo "FAIL: $2 cruised 0 modules. The path is wrong, or typescript is a major"
    echo "      dependency-cruiser does not support yet (needs ^5 or ^6)."
    echo "$1"
    exit 1
  fi
}

fail() { echo "FAIL: $1"; [ $# -gt 1 ] && echo "$2"; exit 1; }

# 1. real code
report="$(cruise "$ROOT")"
assert_cruised "$report" "src/"
grep -q 'no dependency violations found' <<<"$report" \
  || fail "src/ violates the boundary rules" "$report"

# 2. legal fixtures must not be rejected
report="$(cruise "$FIXTURES/allowed")"
assert_cruised "$report" "fixtures/boundaries/allowed"
grep -q 'no dependency violations found' <<<"$report" \
  || fail "the rules reject legal code (allowed fixtures)" "$report"

# 3. illegal fixtures must be rejected, and by the rule meant to catch them
report="$(cruise "$FIXTURES/forbidden")"
assert_cruised "$report" "fixtures/boundaries/forbidden"
grep -q 'dependency violations' <<<"$report" \
  || fail "the forbidden fixtures did not trip any rule" "$report"
for rule in "${EXPECTED_RULES[@]}"; do
  grep -q "error $rule:" <<<"$report" \
    || fail "rule '$rule' did not fire on its fixture" "$report"
done

echo "OK: boundaries clean, and the rules accept what they should and reject what they should"
```

Asserting the specific rule names, rather than just a non-zero exit, is what makes this
useful. Downgrading one rule to a warning still produces violations and a non-zero exit, so
an exit-code-only check would pass while the rule it was guarding had been switched off.

### 11.2 Import restrictions in the editor

The same boundary as a lint error, which gives a better message where the developer is
typing. Belt and braces, not a replacement, because it only sees alias and relative
specifiers rather than the resolved graph:

```js
// eslint.config.js
'no-restricted-imports': ['error', { patterns: [
  { group: ['@/features/*/*'], message: 'Import from the feature root, not its internals.' },
  { group: ['../../*'], message: 'Use the @/ alias instead of climbing out of a feature.' },
]}]
```

Within a feature, use relative imports (`./components/x`), so the alias pattern above does
not restrict a feature's own internals.

**Pin the glob behaviour rather than assuming it.** How `no-restricted-imports` matches these
patterns has changed between ESLint majors, and the question that matters is whether a single
`*` crosses a `/`. If it does not, `@/features/*/*` catches `@/features/orders/api` but misses
the import people actually write, `@/features/orders/api/orders.queries`, and the rule looks
installed while catching almost nothing. On ESLint 10 a single `*` does cross path separators,
so the patterns above are correct as written (verified; see 11.9). A four-line fixture keeps
that true across upgrades:

```ts
// fixtures/lint/deep-imports.ts
// Two of these must be flagged and two must not.
import a from '@/features/orders/api/orders.queries'; // FLAG: another feature's internals
import b from '../../lib/format';                     // FLAG: climbing out of a feature
import c from '@/features/orders';                    // OK: the feature's public entry
import d from './sibling';                            // OK: own internals, relative
export const used = [a, b, c, d];
```

```bash
#!/usr/bin/env bash
# scripts/verify-lint-rules.sh
set -euo pipefail
out="$(npx eslint --no-ignore fixtures/lint/deep-imports.ts 2>&1 || true)"
count="$(grep -c 'no-restricted-imports' <<<"$out" || true)"
if [ "$count" -ne 2 ]; then
  echo "FAIL: expected exactly 2 restricted-import errors, got $count"
  echo "$out"
  exit 1
fi
echo "OK: import restrictions flag internals and allow the public entry"
```

Asserting the exact count catches both failure directions: a pattern that has gone too narrow
to catch deep imports, and one that has gone too broad and now rejects the public entry the
architecture depends on.

### 11.3 Lint rules that carry real weight

Not style, correctness. Each line names the plugin that provides it, because a rule from a
plugin you have not installed is silently absent:

```
react-hooks/rules-of-hooks              error   eslint-plugin-react-hooks
react-hooks/exhaustive-deps             error   eslint-plugin-react-hooks
@typescript-eslint/no-explicit-any      error   typescript-eslint
@typescript-eslint/no-floating-promises error   typescript-eslint (needs type-aware config)
@typescript-eslint/no-misused-promises  error   typescript-eslint (needs type-aware config)
react/jsx-key                           error   eslint-plugin-react
react/no-danger                         error   eslint-plugin-react
jsx-a11y/*  (recommended, as errors)    error   eslint-plugin-jsx-a11y
no-console                              error   built in
```

The two promise rules need a type-aware ESLint setup (`projectService` or `project` in the
parser options). Without it they do not run, and nothing warns you. `no-floating-promises` is
the one that pairs with 4.6: an un-awaited promise in a handler is exactly the failure that
reaches no error boundary.

`exhaustive-deps` as a warning is the same as off. Make it an error and fix the code.

### 11.4 Scripts the CI gate depends on

The commands below only work if the repo defines them, so add them before referencing them
in CI:

```json
{
  "scripts": {
    "build":      "<your framework's build>",
    "typecheck":  "tsc --noEmit",
    "lint":       "eslint . --max-warnings 0",
    "lint:rules": "bash scripts/verify-lint-rules.sh",
    "boundaries": "bash scripts/verify-boundaries.sh",
    "test":       "vitest run --exclude '**/*.a11y.test.*'",
    "test:a11y":  "vitest run .a11y.test",
    "test:e2e":   "playwright test",
    "size":       "size-limit",
    "api:types":  "openapi-typescript \"$API_SCHEMA\" -o src/lib/api/types.gen.ts",
    "api:check":  "bash scripts/verify-api-types.sh",
    "env:check":  "bash scripts/verify-env.sh VITE_API_URL"
  }
}
```

The a11y split is by **filename**, not by test name. Selecting with `--testNamePattern a11y`
silently matches nothing the first time somebody writes `describe('accessibility', ...)`, and
a suite that selects zero tests exits 0. A filename convention cannot drift that way, and it
also keeps the a11y suite from running twice as part of `npm test`.

### 11.5 Accessibility

Lint catches static problems; the rest needs a render:

```bash
npm run lint         # jsx-a11y
npm run test:a11y    # jest-axe or axe-core/playwright on key screens
npx lhci autorun     # Lighthouse CI: budgets plus the accessibility score
```

### 11.6 API types

Generate from a pinned schema source, then check the committed output is current without
clobbering it, so a contract change cannot land silently:

```bash
#!/usr/bin/env bash
# scripts/verify-api-types.sh
# $API_SCHEMA is a pinned, versioned URL or a committed openapi.json, never a live dev server.
set -euo pipefail
: "${API_SCHEMA:?set API_SCHEMA to a pinned schema URL or a committed openapi.json}"

tmp="$(mktemp -t types.gen.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

npx openapi-typescript "$API_SCHEMA" -o "$tmp"
if ! diff -u src/lib/api/types.gen.ts "$tmp"; then
  echo "FAIL: src/lib/api/types.gen.ts is stale."
  echo "      Run: npm run api:types && git add src/lib/api/types.gen.ts"
  exit 1
fi
echo "OK: generated API types are current"
```

Pointing `$API_SCHEMA` at a running dev server makes this check depend on whose branch is
deployed, which is how it starts failing for reasons nobody can reproduce.

### 11.7 Env validation

Parse the environment with a Zod schema at module load, so a missing value fails the build rather
than becoming `undefined` three screens in. Then prove the failure fires:

```bash
#!/usr/bin/env bash
# scripts/verify-env.sh <NAME_OF_A_REQUIRED_VAR>
set -euo pipefail
var="${1:?usage: verify-env.sh <NAME_OF_A_REQUIRED_VAR>}"

if env -u "$var" npm run build >/dev/null 2>&1; then
  echo "FAIL: the build succeeded without $var. The env schema is not enforced at load."
  exit 1
fi
echo "OK: the build fails without $var"
```

This asserts that the gate fires, not why it fired. If your values come from a committed
`.env` file rather than the environment, unset it there in the CI step instead, or the check
passes for the wrong reason.

### 11.8 Bundle budget

A gate, not a dashboard. Budgets live in `.size-limit.json` per entry point, and the numbers
are a project decision (section 15). It runs after `build`, because it measures build output:

```bash
npm run build && npm run size
```

### 11.9 The CI gate

The minimum that makes section 10 real. Order matters: cheap checks first, `build` before the
two steps that need its output.

```yaml
- uses: actions/setup-node@v4
  with:
    node-version-file: '.nvmrc'   # pinned, so the same commit checks the same way
    cache: 'npm'
- run: npm ci                     # never `npm install` in CI

- run: npm run typecheck
- run: npm run lint
- run: npm run lint:rules         # the lint rules themselves (11.2)
- run: npm run boundaries         # the boundary rules themselves (11.1)
- run: npm run api:check          # generated types are current (11.6)
- run: npm audit --audit-level=high
- run: npm test
- run: npm run test:a11y

- run: npm run build              # catches what tsc cannot (4.2)
- run: npm run size
- run: npm run env:check          # asserts the build fails without a required var (11.7)

- run: npx playwright install --with-deps chromium
- run: npm run test:e2e
```

**What in this section has been executed.** Run on Linux, Node 22.23.4, npm 10.9.9, on
2026-10-27. Reproduce before trusting it, and re-run after any major upgrade.

| Claim | How it was checked | Result |
|---|---|---|
| The config accepts a feature's own internals, and another feature's `index.ts` | `depcruise src` on `fixtures/boundaries/allowed`, dependency-cruiser 18.7.0 + typescript 6.0.3 | Pass, 6 modules, 0 violations |
| It rejects deep cross-feature imports, shared-to-feature imports, and cycles | same, on `fixtures/boundaries/forbidden` | Exit 3, exactly the 3 expected rules fired |
| The `$1` backreference in `pathNot` works | the allowed run above | Confirmed |
| The negative-lookahead variant is broken | `to: { path: '^src/features/(?!$1)([^/]+)/.+' }` on the allowed fixtures | Wrongly rejected the legal `orders → invoices/index.ts` import |
| TypeScript 7 silently disables the check | installed `typescript@7.0.2`, reran | `0 modules cruised`, **exit 0**, with only a warning in the output |
| `verify-boundaries.sh` catches that | same run, with the script | Failed loudly as intended |
| It catches a real violation in `src/` | added `src/lib/bad.ts` importing `features/orders` | Failed with the rule name and the offending edge |
| It catches a weakened rule | downgraded `no-circular` to `severity: 'info'` | Failed: "rule 'no-circular' did not fire on its fixture" |
| `@/features/*/*` catches deep imports and allows the public entry | ESLint 10.13.0 against `fixtures/lint/deep-imports.ts` | Exactly 2 errors, public entry not flagged |
| `verify-lint-rules.sh` catches an over-broad pattern | widened to `@/features/*` | Failed: 3 errors, expected 2 |
| `ui-is-presentational` accepts pure imports and rejects query hooks, HTTP, and feature hooks | dependency-cruiser 18.7.2 + typescript 6.0.3, on its own allowed and forbidden fixtures, 2026-11-04 | 0 violations on allowed, exactly 4 on forbidden |
| The `ui/` ESLint block flags state hooks and I/O, and allows `useId` and `useRef` | ESLint 10.14.0 on its fixture | Exactly 6 errors, as marked |

Not executed, and labelled as such: the `vitest`, `playwright`, `size-limit`,
`openapi-typescript`, and `lhci` invocations, and the env-validation script, all of which
depend on a project's own build and config. Run each once on first adoption and record the
result here the same way.

### 11.10 What to leave to judgment

Component size, naming, whether a component should split, whether a hook is worth extracting,
when memoization is warranted. Those are DEFAULT rules because a linter enforcing them
produces worse code, not better.

---

