---
name: react-standards
description: Dave's React frontend standard. Use when writing, reviewing, or planning React, Next.js, Vite, or React Native code, including features, data fetching, forms, async races, accessibility, and frontend security.
paths:
  - "src/**/*.tsx"
  - "app/**/*.tsx"
  - "**/middleware.ts"
  - "**/proxy.ts"
  - "**/app/**/route.ts"
  - "**/next.config.*"
---

# React standards

The repo's established convention beats this standard. When they differ, follow the repo and say so. Except the fixed stack choice (Zod for schema validation), which repo convention never overrides; a repo that differs is flagged for migration. Rules marked REQUIRED are firm. DEFAULT rules can be departed from with a stated reason.

## Rules that never bend

- Server state lives in the query layer, URL state in the URL, form state in the form library. Never copy server data into `useState`.
- Features are imported only through their `index.ts`. Shared layers never import a feature. No cycles.
- All network access goes through the one client in `lib/api/`. Wire types are generated, never hand-written.
- Every data view has loading, error, empty, and loaded states.
- Every interactive element is keyboard operable and labelled. A `div` with `onClick` is not a button.
- Token refresh is single-flight. Only an authentication failure expires the session.
- The client enforces nothing. No secrets in the bundle. No exception text in the UI.
- Check `package.json` before reaching for a new library. Adding one needs a stated requirement.
- `features/<f>/ui/` is pure. See `ui-isolation`.

## Read only what the task needs

| Task | Read in `references/` |
| --- | --- |
| New feature | `13-adding-a-feature.md` |
| Where a file goes | `04-structure.md` |
| Components, state, fetching, forms, errors, types, styling, tests | `05-rules.md` |
| Stale responses, double submit, optimistic updates, token refresh | `07-async-correctness.md` |
| Accessibility | `08-accessibility.md` |
| Performance | `09-performance.md` |
| Security | `10-security.md` |
| Review an existing frontend | `14-reviewing-an-existing-frontend.md`, `06-anti-patterns.md` |
| Boundary, lint, and CI configuration | `12-enforcing-this-automatically.md` |
| Which stack and adoption profile | `03-stack.md` |
| Per-project decisions | `16-decisions-this-document-deliberately-doe.md` |
| Next.js App Router: server components, caching, route handlers, server actions, middleware, cookie auth to NestJS | `17-nextjs-app-router.md` |

## Commands

```bash
npm run typecheck && npm run lint && npm run boundaries && npm test && npm run build
```
