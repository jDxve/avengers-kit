# Handoff

Scope: putting the design into the contract and checking it before the contract goes back to its author and then to the builder. The Design block format is owned by [`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) section A.1, "Design block format", and this file does not redefine it: read it there. If that contract changes the format, this file follows. Where the design may be written (the UI Contract and Open decisions sections of an existing contract, and `docs/design/`) is set by A.1 and the `design` fence in A.2; the contract's own rules are owned by the [`contract-first`](../../contract-first/SKILL.md) skill.

## Where each part goes

| Part | Goes in | Owner of the rule |
| --- | --- | --- |
| One `### Design: <WidgetName>` block per widget signature | The contract's UI Contract section | A.1 Method step 3 |
| A question the contract does not answer | Open decisions, as `Design: <question> (unresolved)` | A.1 Rules |
| A new token | `docs/design/tokens.md`, marked `new`, with its value | A.1 Method step 4; `04-tokens.md` |
| Figma references that span features | `docs/design/` | `kit-extra-agents` Decision 2 and OD-7 |
| A missing parameter, callback, or widget | The report, for the contract author; never the signature | A.1 Rules |

## Checklist before handing off

Run each item. A gap is fixed, or listed in the report and under Open decisions. Ids are stable and never reused.

- [ ] UX-HAND-01 Every widget signature in the UI Contract has a Design block. Verify: count `### Design:` headings against the signatures.
- [ ] UX-HAND-02 Every state in the contract's State table has a row in its widget's state table, and each row names the widget, what shows, and the primary action. Verify: read the State table row by row against the Design blocks (A.3 J7).
- [ ] UX-HAND-03 Every failure path in the contract's Failure paths has copy and a state row. Verify: one copy key per failure path the contract names (`02-state-matrix.md`, `03-copy.md`).
- [ ] UX-HAND-04 The Flow line names the callback each step fires, using the signatures' names, and covers the unhappy branches. Verify: every callback in the Flow exists in the signature (`01-user-flows.md`).
- [ ] UX-HAND-05 No copy states a rule the contract does not. Verify: each limit, deadline, price, or permission in the copy table traces to a contract line or an Open decision.
- [ ] UX-HAND-06 No raw color or size appears in any Design block. Verify: search the blocks for `#` color values and bare numbers with units outside token names.
- [ ] UX-HAND-07 Every new token is in `docs/design/tokens.md` with its value, marked `new`, and the colors are checked in both themes. Verify: each token named in a block exists in the project's theme files or the sheet (`04-tokens.md`).
- [ ] UX-HAND-08 The Accessibility line covers labels, reading order, targets, contrast, text scaling, keyboard on the web, reduced motion, and announcements. Verify: the `05-accessibility.md` checklist, item by item.
- [ ] UX-HAND-09 The Layout line says what changes per width class or breakpoint the screen supports. Verify: `06-responsive.md`.
- [ ] UX-HAND-10 Every Design block has a Source line, and each Figma node read is listed in the report. Verify: compare the report's sources with the Source lines (`07-figma-mcp.md`).
- [ ] UX-HAND-11 Only the UI Contract and Open decisions sections changed. Verify: `git diff` of the contract touches no other section (A.3 J4, held by review).
- [ ] UX-HAND-12 If the contract was `approved`, the edit set it to `draft`, and the report says Dave must re-approve before the build. Verify: the frontmatter, and A.3 J5.

## What the build is checked against

After the build, review compares the built `ui/` with the Design blocks: every state row exists as a widget or parameter, copy keys and text match, colors and sizes come from the named tokens, and each accessibility note is met. A mismatch is a finding with the Design block as the reference (`kit-extra-agents` A.6). That is why a vague Design block costs more than a missing one: it cannot be checked.

## Report

The report format is A.1's "Report" and A.7: contract path, the surfaces designed with the states covered for each, new tokens, signature changes needed from the contract author, open design questions, and the sources read (files and Figma nodes).

## Sources

- Kit: `kit-extra-agents` A.1 (Method, Design block format, Rules, Report), A.2, A.3 (J4, J5, J7), A.6, A.7, Decision 2, OD-7; the [`contract-first`](../../contract-first/SKILL.md) skill and its [`contract-template.md`](../../contract-first/assets/contract-template.md). No public source beyond the kit.
