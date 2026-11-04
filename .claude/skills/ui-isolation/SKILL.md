---
name: ui-isolation
description: Rules for pure presentational widgets in ui/ folders, and how to install the lint and boundary checks that enforce them. Use when writing, wiring, reviewing, or extracting ui/ widgets in Flutter or React.
---

# UI isolation

## Three roles

| Role | Flutter | React | May touch state |
| --- | --- | --- | --- |
| Route | `presentation/screens/` | `routes/` or `app/` page | Starts loads |
| Connected | `presentation/components/` | `features/<f>/components/` | Yes. Resolves state into values and callbacks, handles navigation and toasts |
| Pure | `presentation/ui/` | `features/<f>/ui/` | No |

Existing code stays where it is. Only `ui/` is held to these rules.

## Rules for `ui/`

1. Data comes in as parameters and events go out as callbacks.
2. Parameters are plain values or domain model types, never `DataState`, `AppException`, a query result, or a DTO.
3. No state library, HTTP client, repository, storage, or navigation. In Flutter that means no Riverpod provider, notifier, or `ref`.
4. All copy and tokens come from the project's resources, or arrive as parameters.
5. One widget per state, or one widget with explicit parameters per state. The parent chooses which to show.
6. Accessibility is part of the widget: labels on icon-only controls, tap targets, 2.0x text in Flutter, keyboard operation in React.
7. Stateless by default. Purely visual state needs a justified suppression citing ADR-010.

## The wiring pattern

```dart
// presentation/components/orders_view.dart: connected
class OrdersView extends ConsumerWidget {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(ordersNotifierProvider.notifier);
    return switch (ref.watch(ordersNotifierProvider)) {
      DataIdle() || DataLoading() => const OrdersLoading(),
      DataSuccess(:final data) when data.isEmpty => OrdersEmpty(onCreate: notifier.create),
      DataSuccess(:final data) => OrdersList(
        orders: data,
        onTapOrder: (id) => Navigator.pushNamed(context, OrderScreen.routeName, arguments: id),
        onRefresh: notifier.refresh,
      ),
      DataError(:final exception) => OrdersError(
        message: errorToMessage(exception),
        onRetry: notifier.load,
      ),
    };
  }
}
```

```tsx
// features/orders/components/orders-view.tsx: connected
export function OrdersView() {
  const orders = useOrders();
  const navigate = useNavigate();
  if (orders.isPending) return <OrdersLoading />;
  if (orders.isError) return <OrdersError message={toUserMessage(orders.error)} onRetry={orders.refetch} />;
  if (orders.data.length === 0) return <OrdersEmpty />;
  return <OrdersList orders={orders.data} onSelect={(id) => navigate(`/orders/${id}`)} />;
}
```

## Testing

A `ui/` test needs no provider, mock server, or fake repository. If it does, the widget is not pure.

## Install the checks

Claude Code hooks do not bind manual edits, so these repo-level checks (lint, boundaries, CI) are the real enforcement. Both reject on an allowlist.

**Flutter**, from [assets/flutter/](assets/flutter/):

1. Append `ui_rules.dart` to `tool/lints/lib/main.dart`.
2. Register them in `AppLintsPlugin.register`: `..registerWarningRule(UiPurity())` and `..registerWarningRule(UiStateless())`.
3. Add `'ui_purity'` and `'ui_stateless'` to `_rules` in `tool/check_architecture.dart`.
4. Copy `fixture/` into `tool/lints/fixture/`, and add stub files for the imports if your fixture requires them to resolve.
5. Run `dart run tool/check_lint_fixture.dart`.

**React**, from [assets/react/](assets/react/):

1. Add the rule in `dependency-cruiser-rule.cjs` to `forbidden` in `.dependency-cruiser.cjs`, and `ui-is-presentational` to `EXPECTED_RULES` in `scripts/verify-boundaries.sh`.
2. Add the block in `eslint-ui-block.js` to `eslint.config.js`. If you already use `no-restricted-syntax`, merge the selectors, because a later block replaces the rule.
3. Copy `fixtures/` as described in its README, then run `scripts/verify-boundaries.sh`.

Extend the allowlists only with packages that are purely visual.

Exception: `flutter_hooks` may be added to the `ui_purity` allowlist so a `ui/` widget can use hooks for purely visual local state, under ADR-010 and ADR-011. `hooks_riverpod`, `HookConsumerWidget` and `ref` stay out of `ui/`; they belong in the connected parent. Hooks that hold async or data state (such as `useFuture`, `useStream`) are not visual state and are caught by review only.

## Known limit

The Flutter rule checks imports one file at a time. A `ui/` widget that imports a `common/widgets/` file which reads a notifier passes the lint. Review catches this, or keep `common/widgets/` pure.
