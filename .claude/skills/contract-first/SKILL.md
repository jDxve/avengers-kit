---
name: contract-first
description: How to write a feature contract in docs/contracts before any code. Use when designing a new feature or changing an API, domain model, state shape, mutation queue, or migration.
---

# Contract first

A contract is a short file that lets someone build a feature without guessing. Copy [assets/contract-template.md](assets/contract-template.md) to `docs/contracts/<feature>.md`. `<feature>` must match the folder name under `features/` or `modules/`, because the contract gate looks it up by that name.

## How much to write

Match the feature. A simple read-only screen is half a page. Delete a section that does not apply and add one line saying why, so the reader knows it was considered.

## Rules

- Write in the project's real types. Use Dart signatures for Flutter, TypeScript for React, Zod schemas and their `createZodDto` classes, or OpenAPI references, for NestJS.
- Every invariant names its enforcer: a type, a database constraint, a lint, or a test. An invariant with no enforcer is a wish.
- The API shape comes from the backend's OpenAPI where one exists. Link it, do not restate it.
- The UI Contract must stand alone, so the `ui/` widgets can be built from this section alone. Plain values and callbacks only, no state types.
- The parent resolves state. A `ui/` widget gets `String message`, never an exception or a `DataState`.
- Unknowns go in Open Decisions. Do not pick a value quietly.
- Status starts as `draft`. Only Dave sets `approved`, by editing the file himself.

## Before asking for approval

Check each one, and list any gap under Open Decisions:

1. Every business rule is stated, with its invariant and enforcer.
2. Request, response, and error shapes are complete or linked.
3. Every failure path says what the user sees.
4. Database constraints are named.
5. Authorization and ownership are stated for every operation.
6. Each goal has a test that would prove it.
7. Every trust boundary has its threats and abuse cases in Security, each with a control and a test.

## Gate behavior

| Situation | Editing `features/<f>/` |
| --- | --- |
| Contract approved | Allowed |
| Contract in draft | Blocked |
| No contract, feature folder already exists | Allowed, so existing code needs no retrofit |
| No contract, new feature | Blocked |
