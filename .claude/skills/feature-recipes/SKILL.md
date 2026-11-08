---
name: feature-recipes
description: Design recipes for common cross-stack features in Flutter, React or Next.js, and NestJS. Push notifications, payments, file uploads, realtime updates, background jobs and queues, caching with Redis, internationalization, and offline sync. Each recipe gives the requirement that justifies it, the contract sections it fills, invariants with enforcers, failure paths, and tests. Use when a contract or task involves one of these features.
---

# Feature recipes

Design checklists for features that cross all three stacks and that teams most often get wrong the first time. A recipe tells the contract author which sections to fill and which invariants to name; it links the stack standards for every rule and adds only the cross-stack view. A recipe teaches; it installs nothing and picks no vendor. The repo's established convention beats a recipe, and you say so when they differ, except Drizzle and Zod, which repo convention never overrides (ADR-012); a repo that differs is flagged for migration.

## Rules that never bend

- A recipe is not a requirement. Infrastructure (Redis, BullMQ, WebSockets, object storage, a push provider, a payment provider) arrives only when the project's own contract states the need. Owners: AGENTS.md rule 6, and [`nestjs-standards` 03](../nestjs-standards/references/03-stack.md) "Add when a requirement justifies it".
- A vendor is always an Open decision in the contract, for Dave to answer. The recipe never names one as the choice. Owner: kit rule, `docs/contracts/kit-skills.md` section 9.
- Every queued write, on any stack, meets the five mutation queue rules. Owner: [thor "Mutation queues"](../../agents/thor.md#mutation-queues), and the contract template's Mutation queue section.
- Work that leaves the database (a send, a charge, an enqueue) happens after commit, through an outbox. Owner: [`nestjs-standards` 05](../nestjs-standards/references/05-rules.md) 4.4.
- Anything that can arrive twice (a retry, a redelivered webhook, a re-run job) is idempotent. Owner: [`nestjs-standards` 07](../nestjs-standards/references/07-concurrency-and-data-integrity.md) item 4, and `api-contract` `05-idempotency-and-pagination.md`.
- Security controls are cited by their `SEC-*` id from `security-engineering`. A recipe never defines a new id.
- Every claim in a recipe is a link to a kit standard, a dated citation of a source that was read, or marked "kit rule". A source not read is marked "not read" and no claim rests on it.

## Every recipe has the same headings

1. When it is justified: the trigger, and the statement the project's contract must make.
2. Contract sections it fills: which sections of `contract-first`'s template, and what goes in each.
3. Invariants and enforcers: one row per invariant, each with the constraint, check, or test that holds it.
4. Flutter; React or Next.js; NestJS: links into the standards, plus only what the standards do not already say.
5. Security items: the `SEC-*` ids that apply.
6. Failure paths and what the user sees.
7. Tests: which test proves each invariant, at which level.
8. Sources.

## Read only what the task needs

| Feature in the contract or task | Read in `references/` |
| --- | --- |
| Push notifications to a Flutter app (FCM, APNs), device tokens, notification taps. Web push is not covered and needs its own contract | `push-notifications.md` |
| Charging money, checkout, provider webhooks, refunds | `payments.md` |
| Users upload or download files | `file-uploads.md` |
| Live updates, chat, presence, WebSockets | `realtime.md` |
| Slow, retryable, or scheduled work, queues, BullMQ | `background-jobs.md` |
| A cache shared across requests or instances, Redis | `caching-redis.md` |
| A second locale, plurals, date and money formatting, right-to-left | `i18n.md` |
| Flutter offline reads and writes, a client write queue, and write retry on web. Browser offline storage is not covered | `offline-sync.md` |

Load only the recipe the feature needs. A feature that uses two (an upload processed by a job) reads both.

## Output: what the recipe adds to a contract

- An Open decisions entry per vendor or infrastructure choice the recipe raises, with the stated need it answers.
- One Invariants row per recipe invariant that applies, with its enforcer and test.
- The `SEC-*` ids in the Security section, and the recipe's failure paths in the Failure paths section.
- A line in Release for every new secret, by name, and every new piece of infrastructure.
- A line that says which recipe the contract follows, and any invariant it deliberately drops, with the reason.
