# React Frontend Standards

A reusable engineering standard for building, reviewing, and operating production React
applications. Project-agnostic. Drop it into any React or Next.js repo.

**Scope:** this defines *how* to build a frontend. It does not define your design system,
brand, browser support matrix, or performance budget numbers. Those are per-project and
belong in section 15.

**How to adopt it:** pick a profile in section 2 first. The profile decides which automated
checks you run on day one, and it is the difference between a standard a two-person team
actually adopts and one they declare aspirational and ignore. The rules themselves do not
change between profiles.

**Target architecture:** a feature-organized application with enforced boundaries, server
state owned by a query layer, and URL state in the URL. Start here. Add libraries when a
requirement demands one, not to look sophisticated.

**Companion document:** this is the frontend half of a pair. Where a rule depends on the API
(error codes, generated types, token refresh, idempotency), it names the backend rule it
pairs with.

**Executable claims:** section 11 ships configuration and scripts rather than descriptions of
configuration. Everything in it that can be run has been run against a purpose-built fixture
repo, and section 11.9 records the exact commands, versions, and results. That is evidence
the configuration is correct, not evidence it drops cleanly into your repo. Anything not
executed is labelled as such. Apply the same rule to your own additions: a check nobody has
seen fail is not a check.

**Keeping it current.** This document pins tool behaviour that changes between major
versions. On any major upgrade of ESLint, TypeScript, dependency-cruiser, or React, re-run
section 11 and update 11.9 with the new results. Record project-specific exceptions in the
repo next to the copy of this file, not by editing the rule they depart from, so the
exception stays visible and reversible.

---

