# Copy

Scope: the words a screen shows, and how they are written into a Design block's copy table so they can be built and translated. Where copy lives in code is owned by the stacks: `flutter-standards` [`09-common-layer.md`](../../flutter-standards/references/09-common-layer.md) (Resources, `strings.dart`; and `errorToMessage` under UI utils) and rule 22; `react-standards` 4.6 in [`05-rules.md`](../../react-standards/references/05-rules.md) for what an error may show. Strings in more than one locale belong to the `feature-recipes` [`i18n.md`](../../feature-recipes/references/i18n.md) recipe. This file adds how to write the words.

## Rules for every string

- **Plain words the user already uses.** No internal jargon, codes, or system names (NN/g heuristic 2, Match Between the System and the Real World). Choose simple, plain language, avoid jargon, and write with accessibility and localization in mind (Apple HIG, Writing, "Write for everyone").
- **Fewer words.** Check that each word needs to be there (Apple HIG, Writing, "Be clear").
- **Verbs on actions.** A button or link label is almost always a verb, and clear beats clever (Apple HIG, Writing, "Be action oriented").
- **One term per thing, one style per element.** The same action has the same label everywhere, and capitalization follows one rule per element type (NN/g heuristic 4; Apple HIG, Writing, "Build language patterns").
- **Describe gestures for the device.** No "click" on a touch screen (Apple HIG, Writing, "Write for how people use each device").
- **Copy never states a rule the contract does not.** A limit, deadline, price, or who may do what comes from the contract; otherwise it is an Open decision ([`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) A.1 Rules).

## Error copy

- Say what went wrong and what the user can do next, in plain language, with no error codes (NN/g heuristic 9). Error UI says what failed and what to do next, and offers a retry where retrying could work (`react-standards` 4.6).
- Show it as close to the problem as possible, without blame, and say how to fix it: "Choose a password with at least 8 characters" beats "That password is too short". Interjections like "oops" are unnecessary (Apple HIG, Writing, "Write clear error messages"). The example's limit is Apple's illustration; the real limit comes from the contract.
- Field errors sit next to the field and say how to enter it correctly; avoid robotic messages like "Invalid name" (Apple HIG, Writing, "Show hints in text fields"). On the web the field error is also associated with its input and announced (`react-standards` [`08-accessibility.md`](../../react-standards/references/08-accessibility.md)).
- Never internal detail. An exception's own message never reaches the user; an unexpected failure shows a generic message plus the `requestId` (`react-standards` 4.6). In Flutter only `rejected` may show server-written copy, one line, bounded (`flutter-standards` rule 10), and every other failure type maps to a fixed string in `errorToMessage`.
- The designer writes one message per failure path the contract names. The parent maps the failure to the key; the `ui/` widget receives the text as `message` ([`ui-isolation`](../../ui-isolation/SKILL.md) rules 2 and 4).

Flutter's shared error keys today are `errorGeneric`, `errorTimeout`, `errorOffline`, `errorSessionExpired`, `errorForbidden`, `errorRejected`, `errorTryAgain`, and `errorServer` (`09-common-layer.md`, UI utils). A feature reuses them; a feature-specific message is a new key, mapped in the connected parent.

## Empty states

Explain what would be here and give a next step, with a button or link to take it if possible. Empty states are usually temporary, so put nothing there that the user must not lose (Apple HIG, Writing, "Provide clear next steps on any blank screens").

## Copy keys and length

The Design block's copy table is `| Copy key | Text | Notes |` (`kit-extra-agents` A.1). Kit rules for filling it:

- **Key names say the screen and the purpose**, matching the project's existing key style: `ordersEmptyTitle`, `ordersEmptyAction`, not `text3`.
- **Notes hold the limits the layout needs**: the maximum lines, and what happens past them (wrap, or ellipsis with the full text available elsewhere). A label sized to fit only its first-language text is a layout bug waiting for a translation (kit rule; Apple HIG, Writing, asks for writing "with localization in mind").
- **Whole sentences, named placeholders.** `Deleted {count} orders`, never "Deleted " + count + " orders", because word order and plural forms change between languages. How plurals and placeholders are encoded is the i18n recipe's.
- **Accessibility text is copy too.** Labels for icon-only controls and image descriptions get keys in the same table, and say the action, not the glyph (`flutter-standards` 09, Accessibility, "Names").
- **One string, one key.** Do not reuse a key because the English happens to match; the meanings may translate differently.

## Sources

- Nielsen Norman Group, Jakob Nielsen, "10 Usability Heuristics for User Interface Design", last reviewed January 30, 2024, heuristics 2, 4, 9, read 2026-11-08. https://www.nngroup.com/articles/ten-usability-heuristics/
- Apple, Human Interface Guidelines, "Writing" (page change log, latest entry December 16, 2025), read 2026-11-08 through the page's JSON data. https://developer.apple.com/design/human-interface-guidelines/writing
- Kit: `flutter-standards` 09 (Resources, Accessibility, UI utils), rules 10 and 22; `react-standards` 4.6, `08-accessibility.md`; [`ui-isolation`](../../ui-isolation/SKILL.md); `kit-extra-agents` A.1; `feature-recipes` `i18n.md`.
- Not read:
  - Material Design 3, writing and content design guidance: not read in this session (the pages render client side and returned no readable content). No claim in this file relies on it.
