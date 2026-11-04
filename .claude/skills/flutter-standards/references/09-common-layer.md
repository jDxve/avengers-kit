## 4. Common Layer

### Resources

**`app_theme.dart`**: raw `Color` primitives at the top, an `AppColors extends
ThemeExtension<AppColors>` holding semantic roles (surface, textPrimary, error), light and dark
instances, `AppTheme.light` / `AppTheme.dark`, and a `BuildContext` extension for ergonomic
access. Widgets read colors via `context.primaryColor`, never raw constants.

```dart
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.surface, required this.primary /* ... */});
  final Color surface;
  final Color primary;
  // copyWith + lerp over every field
}

extension ThemeColors on BuildContext {
  AppColors get _c => Theme.of(this).extension<AppColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get primaryColor => _c.primary;
  Color get surfaceColor => _c.surface;
  Color get textPrimaryColor => _c.textPrimary;
  Color get errorColor => _c.error;
}
```

Every semantic pair (text on surface, text on primary, error on surface) meets WCAG AA contrast
(4.5:1 for body text) in both themes. The widget tests in §7 check it with Flutter's
`textContrastGuideline`, so a palette change that breaks contrast fails a test.

**`strings.dart`**: all user-facing copy as `static const String` on a `Strings` class. No
hardcoded strings in widgets, including error copy. Retire this for ARB or `slang` the moment a
second locale appears.

**`assets.dart`**: asset path constants.

**`dimensions.dart`**: the sizing facade.

```dart
abstract final class Dimensions {
  static double get px4 => 4.w;
  static double get px8 => 8.w;
  static double get px16 => 16.w;
  static double get sp14 => 14.sp;
  // ...
}
```

> **`flutter_screenutil` is a default, not an invariant.** The facade is the convention; the
> package behind it is a choice. Widgets call `Dimensions.px16` and never `.w` or `.sp`
> directly, which means swapping to plain constants is a one-file change:
>
> ```dart
> static double get px16 => 16; // no scaling, same call sites
> ```
>
> For many apps `const EdgeInsets.all(16)` is simply correct, and linear scaling by screen
> width makes a tablet look like a magnified phone. Use ScreenUtil when your designs are
> pixel-specified against one reference device and visual fidelity across phone sizes matters.
> Drop it when you are targeting tablets, foldables, or web, where breakpoint-based layout beats
> uniform scaling. The facade exists so that decision stays reversible.
>
> **Never scale fonts by disabling text scaling.** Pinning `MediaQuery` text scaling to 1.0 in
> `main.dart` overrides the user's accessibility setting and is the single most common
> accessibility failure in Flutter apps. If large text breaks a layout, fix the layout:
> `FittedBox`, `Flexible`, scrollable content. If you must bound it, clamp rather than disable:
>
> ```dart
> MediaQuery.withClampedTextScaling(
>   minScaleFactor: 1.0,
>   maxScaleFactor: 1.4,
>   child: child!,
> )
> ```
>
> Every screen has a widget test at 2.0x text scale that asserts no overflow (§7.8).

### Accessibility

**REQUIRED.** Every rule below is checkable, and §7.8 checks them. An app people use to write
letters to someone in prison will be used by people with low vision, large system text, and
reduce-motion switched on.

**Names.** An icon-only control has no text, so it has no name. `Semantics(button: true,
label: Strings.x)` or a `tooltip`, and the label says the action, not the glyph: "Save Marcus
to Favorites", never "heart". Images carry `semanticLabel`, or `ExcludeSemantics` when they
are decoration. Decorative chrome is excluded rather than left to be read aloud: a state stamp
that repeats the state line is noise to a screen reader.

**Tap targets, and the 44/48 collision.** Apple specifies 44x44, Android 48x48, and designs
are usually drawn to one of them. Flutter's `androidTapTargetGuideline` enforces 48, so a
44-pixel button drawn to an iOS spec fails it. Do not shrink the guideline and do not redraw
the design: keep the **visual** at the designed size and grow the **hit area** to 48, centring
one inside the other.

```dart
SizedBox(
  width: 48, height: 48,                     // what the finger and the guideline see
  child: Center(
    child: SizedBox(width: 44, height: 44, child: visual),   // what the eye sees
  ),
)
```

Where the control sits at a fixed inset, offset its position by the difference so the visual
still lands where the design puts it.

**Announcing what changed.** Anything that appears without the user navigating to it needs
`Semantics(liveRegion: true)`: a toast, an inline field error, a result count. Give the live
region the complete sentence and `ExcludeSemantics` the text inside it, or the node's label
becomes the announcement concatenated with its own children.

**Dialogs.** `Semantics(scopesRoute: true, namesRoute: true, label: title)` so focus moves
into the dialog and is announced, and so it returns to the opener on close.

**Motion.** Read `MediaQuery.disableAnimationsOf(context)` and degrade to a cross-fade. Never
remove the feedback entirely; a state change that only animation communicated becomes
invisible.

**Text scale.** Never pin `textScaler` to 1.0; it overrides an accessibility setting and is
the most common accessibility failure in Flutter apps. Fix the layout instead: `Flexible`,
`maxLines` with `ellipsis`, scrollable content, intrinsic heights over fixed ones. Clamp only
where a layout genuinely cannot stretch:

```dart
MediaQuery.withClampedTextScaling(minScaleFactor: 1.0, maxScaleFactor: 1.4, child: child!)
```

**Contrast.** Every semantic pair meets WCAG AA (4.5:1 for body text) in both themes, checked
with `textContrastGuideline`, so a palette change that breaks contrast fails a test.

**What the tests assert** (§7.8): `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
`labeledTapTargetGuideline`, `textContrastGuideline`, and every screen rendered at 2.0x text
with no overflow.

### Design tokens

**REQUIRED.** Colors are not the only thing a widget should not invent. A playbook that tokenizes
color and leaves `const EdgeInsets.all(18)` scattered through the tree has moved the problem,
not solved it.

| Token | Where | Rule |
| --- | --- | --- |
| Color | `AppColors` (ThemeExtension) | `context.colors.x`, never a `Color(0x...)` in a widget |
| Spacing | `Dimensions.pxNN` | the scale, not arbitrary numbers |
| Radius | `Dimensions.radiusX` | named by role (`radiusCard`, `radiusSheetTop`), not by value |
| Type | `AppFonts.heading` / `.sans` | size and weight passed, family never |
| Motion | `Durations` + `Curves` | one enter and one exit duration per surface class |
| Elevation | the component that owns it | a shadow is part of a surface, not a free-floating value |

**Name a token for what it does, not what it is.** `redTint` tells a reader nothing about when
to reach for it; `dangerTile` does. Role names survive a rebrand, and they make a wrong usage
visible in review.

**One component owns each surface.** Toasts, dialogs, sheets, cards and buttons each have
exactly one implementation that features call. A feature that styles its own dialog has
forked the design system, and the fork is found months later when the brand changes.
Composite widgets take tokens by role (`tone`, `variant`), never raw colors.

### UI utils (`common/utils/ui_utils.dart`)

Pure functions. `errorToMessage` is the single place an `AppException` becomes copy, plus
validators and formatters. No Dio types reach this layer.

```dart
String errorToMessage(Object? error) {
  if (error is! AppException) return Strings.errorGeneric;

  return switch (error.type) {
    ErrorType.timeout => Strings.errorTimeout,
    ErrorType.connection => Strings.errorOffline,
    ErrorType.unauthorized => Strings.errorSessionExpired,
    ErrorType.forbidden => Strings.errorForbidden,
    // The one case where the server wrote the sentence for the user.
    ErrorType.rejected => error.message ?? Strings.errorRejected,
    ErrorType.retryable => Strings.errorTryAgain,
    ErrorType.server => Strings.errorServer,
    // cancelled never reaches the UI (DataState.from maps it to idle); unknown carries
    // its real cause in `cause`, already reported.
    ErrorType.cancelled || ErrorType.unknown => Strings.errorGeneric,
  };
}
```

There is no `_` branch. A new `ErrorType` is a compile error here, which is the point: the
decision about what a user reads is made explicitly, in one place, for every case.

**The catch-all that used to leak.** 1.x ended with `_ => error.message ?? fallback`.
`AppException.unexpected` has no status code, so a mapping failure landed in exactly that
branch, and if anything had put `error.toString()` into `message` the user read a Dart type
error. Two fixes hold the line together: the mapper writes `message` only for `rejected`, and
this switch renders it only for `rejected`. Either alone leaves the hole open the next time
someone edits the other.

### Global error hooks (`main.dart`)

The reporting interceptor covers network errors. Everything else, a bad `build`, a failed
layout, an un-awaited future that throws off the widget tree, needs two catch-alls installed
once before `runApp`:

- **`FlutterError.onError`**: framework, build, and render errors. In debug keep the red screen
  via `FlutterError.presentError`; in release forward to the crash reporter.
- **`PlatformDispatcher.instance.onError`**: the top-level catch for async errors that escape
  the framework, such as platform-channel failures or errors from futures outside a widget.
  Return `true` to mark them handled.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Order matters. A bad config must crash loudly, so it runs BEFORE the hooks that would
  // otherwise swallow the StateError and leave the app hanging on the splash screen.
  final config = AppConfig.fromEnvironment();
  reporter = await createReporter(config);

  FlutterError.onError = (details) {
    if (kReleaseMode) {
      reporter.recordFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.recordError(error, stack, fatal: true);
    return true;
  };

  final container = ProviderContainer(overrides: [appConfigProvider.overrideWithValue(config)]);
  await initializeLaunch(container.read(secureStorageProvider)); // first-install wipe (§3)
  await container.read(themeProvider.notifier).load();

  runApp(UncontrolledProviderScope(container: container, child: const App()));
}

/// Vendor SDK initialization (Sentry, Crashlytics) goes here. The reference app ships none.
Future<Reporter> createReporter(AppConfig config) async => const NoopReporter();
```

These two hooks cover overlapping but not identical surfaces to `runZonedGuarded`. They are the
current recommendation for most apps and are what this playbook uses; `runZonedGuarded` is
still the answer when you need zone-scoped context such as per-request tracing, and some crash
reporters install their own zone. Do not run both mechanisms for the same errors and then
wonder about duplicate reports.

**What this does and does not give you.** Together with the reporting interceptor, the three
main application error surfaces (sync framework, async platform, network) route into one
dashboard. It does **not** capture native crashes (enable the vendor's native SDK for those),
OS process kills, or errors in code paths that deliberately swallow them. The honest claim is
that no *application-level* Dart error is invisible by default.

### Route guard (lives in `features/auth/presentation/auth_guard.dart`)

The guard reads `authStateProvider`, which belongs to the auth feature. In 1.x it sat in
`common/navigation/`, which made `common` depend on a feature: the exact arrow §1 forbids, and
one the `shared_layer_independence` lint now rejects. It belongs to auth; `router.dart`, which is
top-level and may import features, wraps protected routes with it.

It is the **single authority** for leaving a protected area. Session expiry, sign-out, and an
unreadable store all end the same way: `authStateProvider` becomes `signedOut`, the guard
rebuilds, and it redirects once.

```dart
class AuthGuard extends ConsumerWidget {
  const AuthGuard({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading && !auth.hasValue) return const _Blank(); // cold start only
    return auth.value == AuthStatus.signedIn ? child : const _RedirectToLogin();
  }
}

/// Redirects in initState, so a rebuild cannot push the login route twice.
class _RedirectToLogin extends StatefulWidget {
  const _RedirectToLogin();
  @override
  State<_RedirectToLogin> createState() => _RedirectToLoginState();
}

class _RedirectToLoginState extends State<_RedirectToLogin> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
    });
  }

  @override
  Widget build(BuildContext context) => const _Blank();
}

class _Blank extends StatelessWidget {
  const _Blank();
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
```

Wired in the router (`router.dart`):

```dart
Route<dynamic> generateRoute(RouteSettings settings) => switch (settings.name) {
  MainShell.routeName => _buildFadeRoute(settings, const AuthGuard(child: MainShell())),
  LoginScreen.routeName => _buildFadeRoute(settings, const LoginScreen()),
  _ => _buildFadeRoute(settings, const _NotFoundScreen()),
};
```

Every protected route is wrapped, including pushed detail routes. A detail route pushed on top
of a guarded shell is covered in practice (the shell's guard clears the stack), but "in
practice" is not a rule; wrap it.

### Top-level wiring

- **`main.dart`**: as above. Boots and hands a container to `App`.
- **`app.dart`**: `App` wraps `MaterialApp` in `ScreenUtilInit(designSize: Size(390, 844))`, reads `navigatorKeyProvider` and `themeProvider`, sets `onGenerateRoute: generateRoute`, and clamps text scaling to 1.0 to 2.0 in `builder`. Tests pump `App` directly with overrides, so the flow test (§7.9) exercises the real router and guard.
- **`main_shell.dart`**: bottom-nav shell with `IndexedStack` over the tab screens and a `Notifier<int>` tracking tab history, for back-navigation and double-back-to-exit.
- **`router.dart`**: declares `navigatorKeyProvider`, a named-route `switch` in `generateRoute`, custom `PageRouteBuilder` transitions, protected routes wrapped in `AuthGuard`, and a default case that shows a "page not found" screen (not a toast: a route that does not exist is a bug, and a screen is reportable).

### Navigator 1.0 by default, with explicit `go_router` triggers

This uses imperative Navigator 1.0 (`onGenerateRoute` plus `Navigator.pushNamed`) on purpose:
for a bottom-tab app with a handful of pushed detail screens it is less machinery, no codegen,
and no new mental model (ADR-004). **Migrate to `go_router` the moment any one of these becomes
true**, not before:

- **Deep links or universal links.** The OS hands you a URL (`myapp://order/42`) that must resolve to a specific screen stack.
- **Web or URL-addressable routes.** You ship a Flutter Web target and the address bar must reflect and drive navigation.
- **Nested or persistent shells.** Per-tab navigation stacks that survive tab switches, with a persistent bottom bar over nested routes.
- **Centralized declarative redirects.** Auth gating that must run as a route-level policy, once redirect logic sprawls across many routes and needs one authority.

When you migrate, the seams already exist: `navigatorKeyProvider` maps onto `go_router`'s
`navigatorKey`, `AuthGuard` maps onto a top-level `redirect` that reads `authStateProvider`, and
route names stay `static const String routeName` on the screens.

---

