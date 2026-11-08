# User flows

Scope: how to map a feature's path from entry to exit, name the callback each step fires, and find every unhappy branch before a screen is drawn. The result is the `Flow:` line of a Design block, whose format is owned by [`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) A.1 ("Design block format"). This file adds the method. It does not restate the `ui/` rules, which belong to [`ui-isolation`](../../ui-isolation/SKILL.md).

## Map the flow in four passes

1. **Entries.** Every way a user arrives: a tab, a list item, a deep link, a notification, a redirect after sign-in, a back navigation into the middle of the flow. Each entry says what the screen already knows (an id only, or the whole object) and so whether the first state is loading (kit rule).
2. **Steps.** One numbered line per user action, naming the callback it fires, in the words of the contract's UI Contract signatures: `2. Taps an order: onTapOrder(id)`. A step with no callback in the signature is a signature gap, reported for the contract author, never added by the designer (`kit-extra-agents` A.1 Rules).
3. **Exits.** Every way out: done, cancel, back, sign-out, session expiry. Each exit says where the user lands and whether unsaved input is kept or lost.
4. **Unhappy branches.** For each step, walk the contract's Failure paths (the template lists offline, timeout, rejected input, conflict, forbidden; [`contract-template.md`](../../contract-first/assets/contract-template.md)) and write what the user sees and what they can do next. A branch the contract does not cover goes under Open decisions as `Design: <question> (unresolved)`.

## Checks for each step

These come from the Nielsen Norman Group heuristics, applied to a flow.

- **Status is visible.** Every step that waits on the system shows that it is working, and every action with consequences says what will happen before it happens (heuristic 1, Visibility of System Status).
- **There is an exit.** Every step has a clearly labeled way back or out, and an action that can be undone offers undo (heuristic 3, User Control and Freedom).
- **High-cost errors are prevented first.** Good defaults and constraints prevent slips; an action that cannot be undone asks for confirmation before it commits (heuristic 5, Error Prevention). Which actions are irreversible is a domain fact: it comes from the contract, never from the design.
- **Nothing must be remembered across steps.** What the user entered or chose earlier stays visible or is offered again, not retyped (heuristic 6, Recognition Rather than Recall; WCAG 2.2 SC 3.3.7 Redundant Entry, Level A).
- **Same words, same actions.** One verb per action across the flow, matching the platform's conventions (heuristic 4, Consistency and Standards). Copy detail: `03-copy.md`.
- **Errors say how to recover.** In plain language, naming the problem and a way forward (heuristic 9). Copy detail: `03-copy.md`.

## Branches people forget

Each is a question to answer in the flow or to raise as an Open decision (kit rule).

- **Double submit.** The submitting state disables the action while the request is in flight (`react-standards` 4.5 in [`05-rules.md`](../../react-standards/references/05-rules.md)). Whether the write also carries an idempotency key is the contract's API and Mutation queue sections, not the design.
- **Leaving mid-flow.** Back, a system back gesture, or closing the tab with unsaved input: keep it, warn, or drop it. Pick one per flow and write it down.
- **Session ends mid-flow.** Where the user lands after signing in again, and whether their input survives.
- **Arriving by deep link** to something that no longer exists, or that the user may not see: the not-found and forbidden rows of the state matrix (`02-state-matrix.md`).
- **Offline at each step.** Blocked, or queued if the contract has a Mutation queue, and what the user sees for a queued write that finally fails (the template's "Dead-letter behavior the user sees").
- **Dragging.** Anything done by dragging also has a single-pointer way that does not drag (WCAG 2.2 SC 2.5.7 Dragging Movements, Level AA).

## Example

```text
Flow:
1. Opens Orders from the tab bar. The list loads.
2. Pulls to refresh: onRefresh(). The list stays visible while it refreshes.
3. Taps an order: onTapOrder(id). Exit to the order screen.
Unhappy: offline at 1 shows the offline row with retry: onRetry().
         forbidden at 3 shows the forbidden row; back returns to the list.
Exit: back from the tab returns to the previous tab with the list's scroll kept (Open decision if the contract is silent).
```

## Sources

- Nielsen Norman Group, Jakob Nielsen, "10 Usability Heuristics for User Interface Design", first published April 24, 1994, last reviewed January 30, 2024, read 2026-11-08. https://www.nngroup.com/articles/ten-usability-heuristics/
- W3C, "Web Content Accessibility Guidelines (WCAG) 2.2", W3C Recommendation 12 December 2024, SC 2.5.7 and 3.3.7, read 2026-11-08. https://www.w3.org/TR/WCAG22/
- Kit: `kit-extra-agents` A.1 (Design block format, Rules); `contract-first` [`contract-template.md`](../../contract-first/assets/contract-template.md) (Failure paths, Mutation queue); `react-standards` 4.5; [`ui-isolation`](../../ui-isolation/SKILL.md).
