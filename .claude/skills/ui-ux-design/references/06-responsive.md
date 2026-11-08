# Responsive and adaptive layout

Scope: how a design says what changes with the space available, written into the `Layout:` line of a Design block ("breakpoints in React, width classes in Flutter", [`kit-extra-agents`](../../../../docs/contracts/kit-extra-agents.md) A.1). Which rules apply on which platform is owned by `react-standards` [`03-stack.md`](../../react-standards/references/03-stack.md) (Platform applicability), the web layout rules by `react-standards` 4.8 in [`05-rules.md`](../../react-standards/references/05-rules.md), and Flutter sizing by `flutter-standards` [`09-common-layer.md`](../../flutter-standards/references/09-common-layer.md) (Resources, `dimensions.dart`). This file adds the design method.

## Rules

- **Decide by the space the app has, not the device.** Window size classes are not for "is tablet" logic; they come from the window the app has, which changes with split screen, resizable windows, folding, and rotation (Android, "Use window size classes"). The Flutter guide says the same: the choice "shouldn't depend on the type of device, but on the device's available window size" (Flutter, "General approach to adaptive apps").
- **Nothing the user needs disappears.** Content reflows without loss of information or functionality, and without scrolling in two directions, down to 320 CSS pixels wide (WCAG 2.2 SC 1.4.10 Reflow, Level AA). An action can move (into a menu, a sheet, an overflow) but not vanish (kit rule, from SC 1.4.10).
- **Both orientations,** unless one is essential (SC 1.3.4 Orientation, Level AA). The Flutter guide notes the Material guidelines encourage never portrait locking an app.
- **Mobile first on the web.** A fixed pixel width that overflows a phone is not finished work (`react-standards` 4.8).
- **Scaling is not adapting.** `flutter-standards` 09 notes that linear scaling by screen width makes a tablet look like a magnified phone, and that breakpoint-based layout beats uniform scaling for tablets, foldables, and web.

## Flutter: width classes

The Android window size classes, by available width in dp:

| Class | Width |
| --- | --- |
| Compact | below 600 |
| Medium | 600 to below 840 |
| Expanded | 840 to below 1200 |
| Large | 1200 to below 1600 |
| Extra-large | 1600 and above |

Height has its own classes (compact below 480, medium 480 to below 900, expanded 900 and above). Most apps decide on width alone; a phone in landscape has medium width but compact height, so two panes are not practical there. Android states that compact, medium, and expanded map to the Material Design layout breakpoints, and that large and extra-large were added for desktop and connected displays (Android, "Use window size classes").

How a Flutter build measures it (from the Flutter guide): `MediaQuery.sizeOf(context)` for the app window, or `LayoutBuilder` for the space a widget's parent gives it. The design only names the class and what changes; the measuring belongs to the connected parent or a shared layout widget, so the `ui/` widget receives the layout choice as a parameter (kit rule, from [`ui-isolation`](../../ui-isolation/SKILL.md) rule 1). Whether the project adopts these exact thresholds is the project's choice; if it has none, propose them as `new` tokens (`04-tokens.md`).

## Web: breakpoints

The kit sets no breakpoint values. Use the project's styling system's breakpoints by name. If the project has none, propose them in `docs/design/tokens.md` as `new` (kit rule). Using the same widths as the Flutter classes keeps one vocabulary across a project with both stacks; that is a suggestion for Dave, not a kit rule.

Check each layout at 320 CSS pixels wide (SC 1.4.10) and at 200% and 400% zoom (`react-standards` [`08-accessibility.md`](../../react-standards/references/08-accessibility.md)). The same rules hold for client-only web and Next.js; on React Native or Expo, Platform applicability in `react-standards` 03 turns "zoom to 400%" into dynamic type support.

## What to write per class

For each class or breakpoint the screen supports, one line: the regions and how they sit, what moves, and what changes component. Common changes, from the Flutter guide's list of widgets that usually need to adapt: dialogs (full screen or modal), navigation (bottom bar or rail), and custom layouts that depend on whether the area is taller or wider. The same guide cites the Material layout guidance: a bottom navigation bar below 600 logical pixels wide, and a navigation rail at 600 or more.

```text
Layout:
Compact: header, filter chips (scroll horizontally), list. Create is a floating button. Detail opens as a new screen.
Medium: same as compact, list in a two-column grid. Create moves to the header.
Expanded and up: list and detail side by side; detail shows the selected order; nothing selected shows the empty detail row.
Spacing: px16 page margin on compact, px24 from medium. Radius: radiusCard.
```

The empty detail pane in the last line is a state of its own; give it a row in the state table (`02-state-matrix.md`).

## Sources

- Android Developers, "Use window size classes", last updated 2026-10-23 UTC, read 2026-11-08. https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes
- Flutter documentation, "General approach to adaptive apps", reflects Flutter 3.47, page last updated 2026-05-05, read 2026-11-08. https://docs.flutter.dev/ui/adaptive-responsive/general
- W3C, "Web Content Accessibility Guidelines (WCAG) 2.2", W3C Recommendation 12 December 2024, SC 1.3.4 and 1.4.10, read 2026-11-08. https://www.w3.org/TR/WCAG22/
- Kit: `react-standards` 03 (Platform applicability), 4.8, `08-accessibility.md`; `flutter-standards` 09 (Resources); [`ui-isolation`](../../ui-isolation/SKILL.md); `kit-extra-agents` A.1.
- Not read:
  - Material Design 3, window size classes: not read in this session (the pages render client side and returned no readable content). The class widths above are from the Android page, which states its relation to Material's breakpoints.
