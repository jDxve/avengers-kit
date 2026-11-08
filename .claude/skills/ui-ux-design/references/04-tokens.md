# Design tokens

Scope: which tokens a design names, how a design reuses the project's tokens, and how a new one is proposed. The token rules in code are owned by the stacks: `flutter-standards` [`09-common-layer.md`](../../flutter-standards/references/09-common-layer.md) (Resources and Design tokens) and rule 22 in [`03-rule-index.md`](../../flutter-standards/references/03-rule-index.md); `react-standards` 4.8 in [`05-rules.md`](../../react-standards/references/05-rules.md). The token sheet's location, `docs/design/tokens.md`, is set by [`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) A.1 and A.2. This file adds the design side.

## What gets a token

The categories are `flutter-standards` 09's table, and `react-standards` 4.8 names the same ones for the web (colors, spacing, radii, typography):

| Category | Flutter home (09) | Name it by |
| --- | --- | --- |
| Color | `AppColors` theme extension, light and dark | role: `surface`, `textPrimary`, `dangerTile` |
| Spacing | `Dimensions.pxNN` | the scale step |
| Radius | `Dimensions.radiusX` | role: `radiusCard`, `radiusSheetTop` |
| Type | `AppFonts` | role, with size and weight; never the family in a widget |
| Motion | `Durations` and `Curves` | one enter and one exit per surface class |
| Elevation | the component that owns the surface | not a free-floating value |

Name a token for what it does, not what it is: `dangerTile`, not `redTint` (`flutter-standards` 09). React keeps tokens in the project's one styling system, and a hex code in a component is a bug or an unapproved exception (`react-standards` 4.8).

## Reuse first

1. Read the project's theme or token files and `docs/design/tokens.md` before naming anything (A.1 Method step 1).
2. Name existing tokens in the Design block's `| Use | Token |` table. A Design block never holds a raw color or size (A.1 Rules).
3. Reuse shared widgets: one component owns each surface (toast, dialog, sheet, card, button), and a feature that styles its own dialog has forked the design system (`flutter-standards` 09). On the web, a new variant goes into the primitive in `components/ui/` (`react-standards` 4.8, DEFAULT).

## Proposing a new token

When nothing existing fits, add a row to `docs/design/tokens.md` marked `new`, with its value (A.1 Method step 4). Kit rule for the row:

| Token | Category | Value | Role | Status | Why no existing token fits |
| --- | --- | --- | --- | --- | --- |
| `warningSurface` | color | light `#FFF4E5`, dark `#3D2A00` | background of a warning banner | `new` | `dangerTile` reads as an error |

- **Color in both themes.** Every semantic pair meets WCAG AA in light and dark (`flutter-standards` 09, Resources): 4.5:1 for text, 3:1 for large text (WCAG 2.2 SC 1.4.3), and 3:1 for component boundaries and states (SC 1.4.11). Name the pair checked in the Why column.
- **Spacing and radius from the scale.** A value between two steps is a question for Dave, not a new step by default (kit rule).
- **Motion has a reduced-motion form.** Say what replaces the animation when reduce motion is on (`05-accessibility.md`).
- **A token is not a value change.** Changing an existing token's value changes every screen that uses it; that is an Open decision with the screens it affects, never a quiet edit (kit rule).

## Token files: the DTCG format

The kit does not require a machine-readable token file; `docs/design/tokens.md` is the sheet. Adopting a token tool or build step is a dependency and needs a stated requirement (AGENTS.md rule 6). If a project does keep tokens in a file, the Design Tokens Community Group format module 2025.10 defines one, and these points are from it:

- It is a Final Community Group Report published by a W3C Community Group. It is not a W3C Standard and is not on the W3C Standards Track.
- Files are JSON, with the extension `.tokens` or `.tokens.json` and the media type `application/design-tokens+json`.
- An object with a `$value` property is a token, and `$value` is the only required property. `$type`, `$description`, `$deprecated`, and `$extensions` are optional. A token with no `$type` of its own inherits its closest parent group's `$type`, and is invalid if neither has one.
- An alias is the curly brace form `"{colors.blue}"`, which resolves to the whole `$value` of the target token.
- A `dimension` value is an object with a number and a unit of `px` or `rem`. A `duration` value is an object with a number and a unit of `ms` or `s`. A `color` value follows the format's Color module (for example an object with `colorSpace`, `components`, and an optional `hex`).

```json
{
  "color": {
    "$type": "color",
    "palette": { "amber100": { "$value": { "colorSpace": "srgb", "components": [1, 0.957, 0.898], "hex": "#fff4e5" } } },
    "warningSurface": { "$value": "{color.palette.amber100}", "$description": "Background of a warning banner." }
  }
}
```

The role name (`warningSurface`) aliases a palette value, which keeps the "name by role" rule from `flutter-standards` 09 in the file as well. Figma variables to tokens: `07-figma-mcp.md`.

## Sources

- Design Tokens Community Group, "Design Tokens Format Module 2025.10", Final Community Group Report, 28 October 2025, read 2026-11-08. https://www.designtokens.org/TR/2025.10/format/ (The editor's draft at https://www.designtokens.org/tr/drafts/format/, dated 08 September 2026 when read, was opened but not used for any claim here.)
- Design Tokens Community Group, "Design Tokens Color Module 2025.10", Final Community Group Report, 28 October 2025 (`hex` is an optional six-digit fallback), read 2026-11-08. https://www.designtokens.org/TR/2025.10/color/
- W3C, "Web Content Accessibility Guidelines (WCAG) 2.2", W3C Recommendation 12 December 2024, SC 1.4.3 and 1.4.11, read 2026-11-08. https://www.w3.org/TR/WCAG22/
- Kit: `flutter-standards` 09 (Resources, Design tokens), rule 22; `react-standards` 4.8; `kit-extra-agents` A.1, A.2; AGENTS.md rule 6.
