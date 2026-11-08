# Extract ui/

Scope: pulling rendering out of a connected Flutter widget or React component into pure `ui/` widgets, without changing what the screen does. The rules for `ui/` and the target shape are owned by the [`ui-isolation`](../../ui-isolation/SKILL.md) skill (Rules for `ui/`, The wiring pattern), and the short procedure is hulk's ["Extracting ui/ from a connected widget"](../../../agents/hulk.md) section. This file adds the order of steps and a before and after per stack. It does not restate the `ui/` rules.

## Order of steps

Each numbered step is one step in the catalog sense: run the screen's tests after it.

1. **Pin the states.** Widget or component tests through the connected parent cover each state the screen shows and each callback. If not, ask hawkeye first (`01-characterization-tests.md`).
2. **Resolve state in the parent.** In the connected widget, turn every state read into a plain value and every action into a callback, including the user-facing error message. Nothing moves yet.
3. **Extract one state's rendering** into a `ui/` widget that takes those values and callbacks. Start with the loaded state; it has the most markup.
4. **Repeat for each other state.** One widget per state, or one widget with explicit parameters per state; the parent chooses which to show (`ui-isolation` rule 5).
5. **Run the `ui/` checks.** Flutter `ui_purity` and `ui_stateless` through `dart run tool/check_architecture.dart`; React `ui-is-presentational` through `npm run boundaries`. If they are not installed, say so in the report; installing them is outside a refactor unless asked (`ui-isolation`, Install the checks).
6. **Add pure `ui/` tests** if hawkeye wants them: no provider, no mock server (`ui-isolation`, Testing). The parent's tests from step 1 stay unchanged.

## Flutter, before

```dart
// presentation/components/orders_view.dart: rendering and state mixed
class OrdersView extends ConsumerWidget {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ordersNotifierProvider);
    if (state is DataError) {
      return Center(child: Text(errorToMessage(state.exception)));
    }
    final orders = state is DataSuccess<List<Order>> ? state.data : const <Order>[];
    return ListView(
      children: [
        for (final o in orders)
          ListTile(
            title: Text(o.reference),
            onTap: () => Navigator.pushNamed(context, OrderScreen.routeName, arguments: o.id),
          ),
      ],
    );
  }
}
```

## Flutter, after

```dart
// presentation/ui/orders_list.dart: pure
class OrdersList extends StatelessWidget {
  const OrdersList({super.key, required this.orders, required this.onTapOrder});

  final List<Order> orders;
  final ValueChanged<String> onTapOrder;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          for (final o in orders)
            ListTile(title: Text(o.reference), onTap: () => onTapOrder(o.id)),
        ],
      );
}
```

The connected `OrdersView` keeps `ref.watch` and `Navigator`, and switches on the state as in `ui-isolation`, The wiring pattern. Behavior check: the loading state in the before code rendered an empty list. If the after code shows a spinner instead, that is a behavior change; keep the empty list, and report the spinner as a suggestion for iron-man.

## React, before

```tsx
// features/orders/components/orders-view.tsx: rendering and state mixed
export function OrdersView() {
  const orders = useOrders();
  const navigate = useNavigate();
  if (orders.isError) return <p role="alert">{toUserMessage(orders.error)}</p>;
  return (
    <ul>
      {(orders.data ?? []).map((o) => (
        <li key={o.id}>
          <button onClick={() => navigate(`/orders/${o.id}`)}>{o.reference}</button>
        </li>
      ))}
    </ul>
  );
}
```

## React, after

```tsx
// features/orders/ui/orders-list.tsx: pure
type Props = { orders: Order[]; onSelect: (id: string) => void };

export function OrdersList({ orders, onSelect }: Props) {
  return (
    <ul>
      {orders.map((o) => (
        <li key={o.id}>
          <button onClick={() => onSelect(o.id)}>{o.reference}</button>
        </li>
      ))}
    </ul>
  );
}
```

`OrdersView` keeps `useOrders`, `useNavigate`, and `toUserMessage`, and renders `<OrdersList orders={orders.data ?? []} onSelect={(id) => navigate(`/orders/${id}`)} />`. The error branch moves to its own `ui/` widget taking `message`, keeping `role="alert"`.

## Easy to miss

- The error message is resolved in the parent. A `ui/` widget never receives an exception or a query error ([`ui-isolation`](../../ui-isolation/SKILL.md) rule 2).
- Accessibility moves with the markup: labels, roles, focus order, and tap targets must be identical after (`ui-isolation` rule 6).
- Visual local state (an expanded flag, a text controller) may move with the widget only with the justified suppression ADR-010 requires (`ui-isolation` rule 7).
- A `ui/` widget that imports a `common/widgets/` file which reads a notifier passes the Flutter lint. Check those imports by hand (`ui-isolation`, Known limit).

## Sources

- Kit: [`ui-isolation`](../../ui-isolation/SKILL.md) (Three roles, Rules for `ui/`, The wiring pattern, Testing, Known limit); hulk agent file, ["Extracting ui/ from a connected widget"](../../../agents/hulk.md); [ADR-010](../../../../docs/adr/010-visual-state-in-ui.md). No public source beyond the kit.
