# Characterization tests

Scope: what to pin before a refactor when no test covers the code, at which level, and how hulk asks hawkeye for it. hulk cannot write tests for code it is about to move without mixing two jobs, and hawkeye owns every test, so the request is a handoff. Which level proves which claim is owned by the `testing-strategy` skill ([`01-levels-by-stack.md`](../../testing-strategy/references/01-levels-by-stack.md)); this file adds only what a refactor needs from it.

## What a characterization test is

A test that asserts what the code does today, not what it should do. If today's output looks wrong, the test still asserts it, and the oddity goes into the report as a finding for iron-man. Fixing it during a refactor is a behavior change (hulk, Rules). The term comes from Feathers (see Sources); the rules below are kit rules.

## When hulk stops and asks

hulk runs the target's tests first (Method step 1). It stops and asks for characterization tests when any of these holds:

- No test exercises the code that will move.
- Tests exist but mock the exact unit being restructured, so they would pass whatever the unit does.
- Tests assert only that something was called, not what came out.
- A public surface (an endpoint, a feature's `index.ts` or root file, a widget's parameters) has no test at all.

## What to pin

Pin the outputs a caller can observe, at the boundary the refactor must not move:

| Refactor | Pin | Level (`testing-strategy`) |
| --- | --- | --- |
| Split a NestJS service | Each endpoint the service backs: status, body shape, error `code`, and the rows written | NestJS e2e on a real database ([`04-nestjs-e2e-and-db.md`](../../testing-strategy/references/04-nestjs-e2e-and-db.md)) |
| Break a module or feature cycle | The public functions or providers on both sides of the cycle | Unit, one layer down mocked |
| Extract a widget, component, or `ui/` | Every state the screen shows (loading, error, empty, loaded) and each callback that fires | Widget or component test through the connected parent |
| Extract or inline a function | Its return value for the inputs callers actually pass, including the edge values | Unit |
| Strangler | The old module's public interface, so the same tests can later run against the new one | The level of the interface |

Also pin:

- Error paths, not only the happy path. A refactor that changes which exception escapes is a behavior change.
- Ordering where callers depend on it (list order, event order).
- Side effects a caller sees: rows, emitted events, navigation, toasts.

Do not pin private helpers, call counts, or log text. Those are exactly what a refactor is allowed to change, and pinning them turns a safe step into a failing test.

## The request to hawkeye

```text
CHARACTERIZE <target path or symbol>
Refactor planned: <one line, from the step catalog>
Baseline: <command>, <result>; uncovered: <what no test exercises>
Pin: <observable outputs from the table above>
Level: <unit | widget | component | e2e>, per testing-strategy
Known oddities to pin as-is: <list or none>
```

After hawkeye's tests land and pass, they become the baseline. hulk re-runs them and reports that result before the first step.

## Seeing them fail

A characterization test counts only once it has been seen to fail (`testing-strategy`, Rules that never bend). hawkeye breaks the pinned behavior on purpose (change one returned value, drop one field), confirms the test fails, and reverts.

## Sources

- Michael Feathers, *Working Effectively with Legacy Code*, edition not verified: not read in this session (no network access). Cited for the term "characterization test" only.
- Kit: hulk agent file ([`hulk.md`](../../../agents/hulk.md)), Method and Rules; `testing-strategy` skill, `01-levels-by-stack.md`, `04-nestjs-e2e-and-db.md`, and `08-bug-to-failing-test.md` ("When nothing pins the behavior").
