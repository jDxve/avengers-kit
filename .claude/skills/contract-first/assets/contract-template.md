---
feature: <feature>
status: draft
---

# {Feature} contract

## Goal

One or two sentences on what the user can do, and what is out of scope.

## Domain

Models and the repository or service interface, in real types.

```dart
final class Order {
  const Order({required this.id, required this.status, required this.totalCents});
  final String id;
  final OrderStatus status;
  final int totalCents;
}

abstract interface class OrdersRepository {
  Future<Result<List<Order>>> list({required int page});
  Future<Result<Order>> cancel(String id, {required String idempotencyKey});
}
```

## API

Endpoints, or a link to the OpenAPI operation. Error codes the client branches on.

## Authorization

Who may do each operation, and what ownership or tenant scope applies to each lookup. Write "public" where that is the decision.

## State

Who owns which state, and the transitions. Name the notifier or query keys.

| State | Source | Shown as |
| --- | --- | --- |
| loading | `ordersNotifierProvider` | `OrdersLoading` |
| success, non-empty | | `OrdersList` |
| success, empty | | `OrdersEmpty` |
| error | | `OrdersError` |

## Invariants

| Invariant | Enforced by |
| --- | --- |
| An order cancels once, even on double tap | Conditional update checked by row count; concurrency test |

## Mutation queue

Delete if writes are online only, and say so.

- Queued operations and their ordering group:
- Idempotency key, per user intent:
- Retry ceiling and backoff:
- Dead-letter behavior the user sees:
- On sign-out:

## UI contract

Everything the `ui/` widgets need. Plain values and callbacks only.

```dart
class OrdersList extends StatelessWidget {
  const OrdersList({
    super.key,
    required this.orders,
    required this.onTapOrder,
    required this.onRefresh,
  });
  final List<Order> orders;
  final ValueChanged<String> onTapOrder;
  final Future<void> Function() onRefresh;
}

class OrdersError extends StatelessWidget {
  const OrdersError({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
}
```

Mockups: links or file paths per widget.

## Failure paths

What the user sees for each: offline, timeout, rejected input, conflict, forbidden.

## Release

Delete if there is no schema, config, or infrastructure change, and say so.

- Migration order and whether it is reversible:
- New config or secrets, by name:
- Flag or kill switch:
- Rollback or fix-forward path:

## Tests

The tests that prove the invariants and failure paths.

## Open decisions

Unresolved questions for Dave. Do not start the affected work until these are answered.
