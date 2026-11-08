# State matrix

Scope: the seven states a screen can be in, what each one shows on Flutter and on React, and how they map to the contract's State table and Failure paths. The rule that the parent picks the widget, and that a `ui/` widget gets plain values and callbacks, is owned by [`ui-isolation`](../../ui-isolation/SKILL.md) (rules 2 and 5, The wiring pattern). This file adds the design content of each state.

## Which states a screen needs

- **Always, for a data screen:** loading, empty, error with retry, success. Owners: `flutter-standards` rule 19 in [`03-rule-index.md`](../../flutter-standards/references/03-rule-index.md); `react-standards` four states ([`01-rules-for-ai-agents.md`](../../react-standards/references/01-rules-for-ai-agents.md) item 12, tested per 4.9 in [`05-rules.md`](../../react-standards/references/05-rules.md)).
- **When the contract names them:** offline, partial, forbidden, and the action states submitting and disabled. The Design block format adds rows for these "where the contract has them" ([`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) A.1).
- A state the design needs that the contract's State table lacks is a gap for the contract author, reported, not added to the signatures (A.1 Rules).

## The seven states

| State | Comes from | What shows | Primary action | What the user can do next |
| --- | --- | --- | --- | --- |
| loading | First load, or a refresh | First load: the screen's frame with a progress indicator. Refresh: the existing content stays, with a refresh indicator (kit rule) | none; cancel if the wait can be long | wait, or leave |
| empty | Success with no items | What would be here and why it is empty, plus the action that fills it if the user has one | that action | act, or leave |
| error | A failure the user can retry | The `message` parameter, placed where the failure is | retry, when retrying can work (`react-standards` 4.6) | retry, or leave |
| offline | No connection | What still works, and what needs a connection | retry; or the queued indicator if the contract has a Mutation queue | keep working with what is cached, or retry |
| partial | Some sections loaded, some failed | The loaded sections as normal; an inline error with its own retry on each failed section | retry for that section | use what loaded |
| success | Data | The content | the screen's main task | continue the flow |
| forbidden | Signed in, not allowed (403) | That this is not available to the user, with no internal detail | the way out the contract names | go back, or the request-access path the contract names |

Action states, when the contract has them:

| State | What shows | Notes |
| --- | --- | --- |
| submitting | The action control busy and disabled; the form stays visible | Guards against double-fire (`react-standards` 4.5) |
| disabled | The control visibly disabled, with the reason near it when the reason is not obvious | Disabled controls are exempt from contrast minimums (WCAG 2.2 SC 1.4.3 "Incidental"), so the reason cannot rely on the control's text alone (kit rule) |

## Mapping failures to states

The failure classes are owned by the stacks. The designer writes one row and one message per class the contract names; the parent maps failures to those messages.

| Failure | Flutter `ErrorType` ([`08-core-layer.md`](../../flutter-standards/references/08-core-layer.md)) | React class (`react-standards` 4.6) | State |
| --- | --- | --- | --- |
| No route to the server | `connection` | transient infrastructure failure | offline |
| Took too long, 5xx, 429 | `timeout`, `server`, `retryable` | transient infrastructure failure | error with retry |
| Input refused (400, 409, 422) | `rejected` | expected domain failure, shown on the field | stays in the form, message on the field |
| Signed in, not allowed (403) | `forbidden` | expected domain failure: "a 403 renders a permission message" | forbidden |
| Not found (404) | per the contract's Failure paths | expected domain failure: "a 404 renders a not-found view" | its own row, or empty, as the contract says |
| Session over | `unauthorized` | the single-flight refresh, then sign-out (`react-standards` [`07-async-correctness.md`](../../react-standards/references/07-async-correctness.md)) | leaves the screen, not a screen state |
| A part of the page failed | per section | "A failure in a chart should not blank the page" | partial |

In Flutter, `errorToMessage` is the one place a failure becomes copy ([`09-common-layer.md`](../../flutter-standards/references/09-common-layer.md), "UI utils"), and `cancelled` never reaches the UI. Copy for each row: `03-copy.md`.

## Per-platform examples

Flutter, widget per state, chosen by the connected parent:

| State | Widget | Parameters |
| --- | --- | --- |
| loading | `OrdersLoading` | none |
| empty | `OrdersEmpty` | `onCreate` |
| error | `OrdersError` | `message`, `onRetry` |
| offline | `OrdersOffline` | `orders` (cached), `onRetry` |
| success | `OrdersList` | `orders`, `onTapOrder`, `onRefresh` |
| forbidden | `OrdersForbidden` | `onBack` |

React, same split under `features/orders/ui/`: `<OrdersLoading />`, `<OrdersEmpty onCreate />`, `<OrdersError message onRetry />`, `<OrdersList orders onSelect />`. The error widget keeps `role="alert"` so a screen reader hears it (`react-standards` [`08-accessibility.md`](../../react-standards/references/08-accessibility.md), live regions).

## Accessibility per state

- A state that appears without the user moving to it (an error, a result count, "saved") is announced: Flutter `Semantics(liveRegion: true)` (`flutter-standards` 09, Accessibility), React live regions (`react-standards` 08), and on the web WCAG 2.2 SC 4.1.3 Status Messages (Level AA).
- An input error names the field and describes the problem in text (SC 3.3.1, Level A), and suggests a fix when one is known (SC 3.3.3, Level AA).
- Loading and empty states are not conveyed by color or animation alone (SC 1.4.1 Use of Color, Level A). More in `05-accessibility.md`.

## Sources

- W3C, "Web Content Accessibility Guidelines (WCAG) 2.2", W3C Recommendation 12 December 2024, SC 1.4.1, 1.4.3, 3.3.1, 3.3.3, 4.1.3, read 2026-11-08. https://www.w3.org/TR/WCAG22/
- Kit: [`ui-isolation`](../../ui-isolation/SKILL.md); `flutter-standards` rule 19, `08-core-layer.md` (`ErrorType`), `09-common-layer.md` (`errorToMessage`, Accessibility); `react-standards` `01-rules-for-ai-agents.md` item 12, 4.5, 4.6, 4.9, `08-accessibility.md`; `kit-extra-agents` A.1.
