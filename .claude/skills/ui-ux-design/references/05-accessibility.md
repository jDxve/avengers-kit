# Accessibility

Scope: what a design must say so the built screen is accessible, written into the Design block's `Accessibility:` line ([`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) A.1). The build rules and their tests are owned by the stacks: `flutter-standards` [`09-common-layer.md`](../../flutter-standards/references/09-common-layer.md) (Accessibility) with rules 20 and 21 in [`03-rule-index.md`](../../flutter-standards/references/03-rule-index.md) and the 7.8 widget tests in [`12-testing.md`](../../flutter-standards/references/12-testing.md); `react-standards` [`08-accessibility.md`](../../react-standards/references/08-accessibility.md) and 4.8; and [`ui-isolation`](../../ui-isolation/SKILL.md) rule 6. This file turns them into design decisions. WCAG 2.2 is written for web content; for native apps it is used here as the reference the platform guidance itself points to (Apple's contrast table is "from WCAG Level AA"; the Flutter accessibility page lists WCAG 2 under "Accessibility regulations").

## Design checklist

Each item is something a reviewer can check against the Design block and the built screen. Ids are stable and never reused.

- [ ] UX-A11Y-01 Every icon-only control and meaningful image has a label in the copy table that says the action or meaning, not the glyph; decorative images are marked decorative. Verify: each icon-only control in the layout has a copy key (WCAG 2.2 SC 1.1.1 and 4.1.2, Level A; `flutter-standards` 09 "Names"; `react-standards` 08 `alt`).
- [ ] UX-A11Y-02 Text and its background meet 4.5:1, large text 3:1, in light and dark. Verify: each text token pair in the `| Use | Token |` table, checked with a contrast tool (SC 1.4.3, Level AA; `flutter-standards` 09 Contrast; `react-standards` 08).
- [ ] UX-A11Y-03 What identifies a component and its state (borders, selected and checked marks) and meaningful icons meet 3:1 against what is next to them. Verify: the token pairs for borders, state marks, and icons (SC 1.4.11, Level AA; `react-standards` 08).
- [ ] UX-A11Y-04 Nothing is conveyed by color alone: errors, status, selection, and required fields also have text, an icon, or a pattern. Verify: read each state row with the colors removed (SC 1.4.1, Level A; `react-standards` 4.8).
- [ ] UX-A11Y-05 Touch targets: Flutter hit areas are at least 48 by 48, with the visual kept at the designed size if it is drawn smaller; web targets are at least 24 by 24 CSS pixels or spaced as SC 2.5.8 allows. Verify: the layout names the hit size per control (`flutter-standards` 09 "Tap targets"; Flutter accessibility checklist, 48x48; SC 2.5.8, Level AA).
- [ ] UX-A11Y-06 Reading order and focus order follow the layout's regions in the order the Design block lists them. Verify: the `Layout:` line lists regions in reading order, and nothing is placed visually out of that order (SC 1.3.2 and 2.4.3, Level A).
- [ ] UX-A11Y-07 Keyboard, on the web: every action works from the keyboard, focus is always visible and not hidden by sticky content, and a dialog takes focus, traps it, closes on Escape, and returns focus to its opener. Verify: the Design block names the dialog's opener and the keys (SC 2.1.1 Level A, 2.4.7 and 2.4.11 Level AA; `react-standards` 08).
- [ ] UX-A11Y-08 Text scaling: Flutter screens work at 2.0x text with no overflow and scaling is clamped, never disabled; web pages work at 200% and 400% zoom without loss of content. Verify: the layout says what wraps, what scrolls, and where `maxLines` and ellipsis apply (`flutter-standards` rules 20 and 21; `react-standards` 08; SC 1.4.4 and 1.4.10, Level AA).
- [ ] UX-A11Y-09 Motion: each animation names its reduced-motion form, which keeps the feedback (for example a cross-fade) rather than removing it. Verify: every motion token in the Design block has a reduced-motion line (`flutter-standards` 09 "Motion"; `react-standards` 4.8; SC 2.3.3, Level AAA; Apple HIG, Reduce Motion).
- [ ] UX-A11Y-10 Changes that appear without the user moving to them (field errors, toasts, result counts, "saved") are announced. Verify: each such element is marked as a live region in the Accessibility line (SC 4.1.3, Level AA; `flutter-standards` 09 "Announcing what changed"; `react-standards` 08).
- [ ] UX-A11Y-11 Every input has a visible label (placeholder text is not a label), and its error names the field and suggests the fix when one is known. Verify: the copy table has a label key per input and an error key per validation the contract names (SC 3.3.1 and 3.3.2 Level A, 3.3.3 Level AA; `react-standards` 08).
- [ ] UX-A11Y-12 Anything done by dragging has a single-pointer alternative. Verify: the flow names it (SC 2.5.7, Level AA).

## Platform numbers that differ

Targets are the common collision. Apple's default control size on iOS and iPadOS is 44x44 pt with a 28x28 pt minimum (Apple HIG, Accessibility). Flutter's accessibility checklist says at least 48x48 pixels, and Flutter's `androidTapTargetGuideline` enforces 48. `flutter-standards` 09 resolves it: keep the visual at the designed size and grow the hit area to 48. WCAG 2.2's 24 by 24 CSS pixels (SC 2.5.8) is the floor for the web, not a target for mobile.

Text size: Apple asks apps to let people enlarge text by at least 200 percent where possible (140 percent on watchOS). The kit's Flutter test is 2.0x with no overflow, and its web check is 200% and 400% zoom.

## Writing the Accessibility line

```text
Accessibility: Refresh icon button labelled by key ordersRefreshLabel; 48 hit area around the 24 icon token.
Reading order: header, filter chips, list, floating create button. Error banner is a live region.
Contrast: textPrimary on surface and onPrimary on primary, both themes. Status chips carry text, not color only.
2.0x text: order title wraps to 2 lines, then ellipsis; amounts never truncate. Web: keyboard order matches reading order.
Reduced motion: list insert animation becomes a cross-fade.
```

## Sources

- W3C, "Web Content Accessibility Guidelines (WCAG) 2.2", W3C Recommendation 12 December 2024, SC 1.1.1, 1.3.2, 1.4.1, 1.4.3, 1.4.4, 1.4.10, 1.4.11, 2.1.1, 2.3.3, 2.4.3, 2.4.7, 2.4.11, 2.5.7, 2.5.8, 3.3.1, 3.3.2, 3.3.3, 4.1.2, 4.1.3, read 2026-11-08. https://www.w3.org/TR/WCAG22/
- Apple, Human Interface Guidelines, "Accessibility" (page change log, latest entry June 9, 2025), read 2026-11-08 through the page's JSON data. https://developer.apple.com/design/human-interface-guidelines/accessibility
- Flutter documentation, "Accessibility" (accessibility release checklist), reflects Flutter 3.47, page last updated 2026-07-31, read 2026-11-08. https://docs.flutter.dev/ui/accessibility
- Kit: `flutter-standards` 09 (Accessibility, Resources), rules 20 and 21, 12 section 7.8; `react-standards` `08-accessibility.md`, 4.8; [`ui-isolation`](../../ui-isolation/SKILL.md) rule 6; `kit-extra-agents` A.1.
- Not read:
  - Material Design 3, accessibility guidance: not read in this session (the pages render client side and returned no readable content). No claim in this file relies on it.
