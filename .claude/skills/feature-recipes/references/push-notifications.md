# Push notifications

Scope: sending push notifications from a NestJS backend to a Flutter app through Firebase Cloud Messaging (FCM) or the Apple Push Notification service (APNs), the device registrations behind them, and what happens when the user taps one. Web push in the browser is not covered: its sources were not read, so a project that needs it adds a contract of its own. Do not reuse this registration table, provider client, or SEC-MOB ids for browser subscriptions. A web push contract covers the service worker, VAPID keys, the subscription endpoint as untrusted input, the permission prompt, and the click target (kit rule). The rules for routing, outbox, and sign-out live in the stack standards and are linked; this recipe adds the registration lifecycle and the cross-stack view.

## When it is justified

The trigger is re-engagement or a URL entry point ([`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.6, "Push and deep links"). A push provider is new infrastructure and a vendor, so the project's own contract states the need in its Goal, and names the provider as an Open decision for Dave (AGENTS.md rule 6; kit rule for the Open decision). The recipe picks no provider.

Push is a hint, not a channel of record. APNs describes itself as best effort: it may reorder notifications to the same device token, stores only one notification per bundle ID while a device is offline, and may throttle or not deliver some (APNs, "Sending notification requests to APNs"). Anything the user must see also exists in the app's own state, fetched over the API (kit rule).

## Contract sections it fills

- Domain: a device registration (user id, tenant where the project has one, the provider's registration token or installation id, platform, the session it was registered under, last upload timestamp).
- API: register and unregister operations, plus the notification types and the deep link each carries.
- Authorization: a registration belongs to the caller; nobody registers a token for another user.
- Security: the "push payloads" line of the template's sensitive data list, and the ids below.
- Invariants, Failure paths, Tests: from the sections below.
- Release: the provider credentials, by secret name.
- Open decisions: the provider, and the staleness window.

## Invariants and enforcers

| Invariant | Enforced by |
| --- | --- |
| A registration is bound to the signed-in user, taken from the session, never from the request body | Strict request schema (`SEC-API-03`); e2e test that a `userId` in the body returns 400 |
| One registration token belongs to one user at a time; registering it again under user B moves it from A | Unique constraint on the token ([`database-drizzle`](../../database-drizzle/SKILL.md) `01-schema-design.md`); e2e test (kit rule) |
| Sign-out removes the device's registration, even when the device is offline at sign-out | Client unregisters before clearing the session; the server also deletes registrations of a revoked session ([`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.8). Follows thor's [sign-out rule](../../../agents/thor.md#mutation-queues) and `SEC-MOB-06` (kit rule for the server half) |
| Registrations the provider reports dead are deleted and never retried | FCM: `UNREGISTERED` (404), or `INVALID_ARGUMENT` (400) when the payload is known valid. APNs: 410 `Unregistered` or `ExpiredToken`, which APNs says not to retry. Unit test with a provider stub |
| Stale registrations are pruned | The server stores a timestamp on every upload and prunes past the contract's window. FCM's default is that a registration is stale after a month without connecting, and it says the window is the app's choice |
| No sensitive data in a payload: it carries a notification type, an id, and generic copy, and the app fetches detail over the authenticated API | Payload builder with an allowlist of fields, and its unit test (kit rule). Apple: do not put customer information or sensitive data in a payload; encrypt it if you must |
| A tapped notification's route is untrusted input: parsed, validated, and sent through the auth guard | `SEC-MOB-10`, [`flutter-standards` 09](../../flutter-standards/references/09-common-layer.md) "Navigator 1.0 by default" (`go_router` trigger) |
| Permission is asked in context, when the feature needs it, never at launch | `SEC-MOB-19` |
| Sends go through an outbox, after commit, and a failed send never fails the request that caused it | [`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.4 (outbox) and 4.9; `background-jobs.md` when a queue is justified |
| A retried send does not show twice | Dispatch keyed by the outbox row id (kit rule). APNs merges notifications sent with the same `apns-collapse-id` (at most 64 bytes) |

## Flutter

The registration upload, the permission prompt, and the tap handler live in the connected layer and the data layer; `ui/` widgets only receive a rationale message and callbacks (`ui-isolation`). Upload the current registration on every app start and whenever the SDK reports a change, because FCM recommends the server refresh its timestamp on every upload (FCM, "Best practices for FCM registration management"). A deep link to a protected route goes through the guard ([`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.6). Unregister before the session is cleared, then follow `flutter-standards` [08](../../flutter-standards/references/08-core-layer.md) "Threat model and limits" for the rest of sign-out.

## React or Next.js

No browser push here. A web client shows the same events as in-app state through the query layer ([`react-standards` 05](../../react-standards/references/05-rules.md) 4.4), refreshed as `realtime.md` describes. Do not reuse this registration table, provider client, or SEC-MOB ids for browser subscriptions. A web push contract covers the service worker, VAPID keys, the subscription endpoint as untrusted input, the permission prompt, and the click target (kit rule).

## NestJS

The registration table follows `database-drizzle` (tenant scoping in `07-tenant-scoping.md` where the project has tenants). The provider client has timeouts, bounded retries, and parses every provider response with Zod ([`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md), "External integrations"). APNs says 5xx responses may be retried after 15 minutes with backoff, and `TooManyRequests` after a delay. Log the outbox id, the notification type, and the outcome, never the token or the payload ([`observability-and-debugging`](../../observability-and-debugging/references/01-structured-logging.md) `01-structured-logging.md`).

## Security items

`SEC-API-01`, `SEC-API-03`, `SEC-API-20`, `SEC-API-21`, `SEC-MOB-06`, `SEC-MOB-10`, `SEC-MOB-19`, `SEC-LOG-01`, `SEC-LOG-04`.

## Failure paths and what the user sees

| Failure | What the user sees |
| --- | --- |
| Permission denied | The feature still works in the app; a settings screen says how to turn notifications on (copy from resources) |
| Provider down or rate limiting | Nothing; the outbox retries up to its ceiling, then dead-letters and alerts. The action that caused it already succeeded |
| Tap on a link to a deleted or forbidden item | The target screen's not-found or forbidden state, never a crash |
| Tap while signed out | The login screen, then the target if the link is still valid for that user |
| Notification never arrives | The same item is visible in the app on next open (kit rule) |

## Tests

- e2e: register binds to the caller; a body `userId` returns 400; B registering A's token moves it; sign-out and session revocation delete the registration.
- Unit: provider stub returning FCM `UNREGISTERED` and APNs 410 deletes the row and does not retry; a 5xx is retried with backoff up to the ceiling.
- Unit: the payload builder emits only allowlisted fields.
- Unit or e2e: running the outbox dispatcher twice on one row sends once; a send failure leaves the parent request's response unchanged.
- Flutter: the link parser and the signed-out flow test from `SEC-MOB-10`.

## Sources

- Firebase documentation, "Best practices for FCM registration management", page last updated 2026-11-05, read 2026-11-08. https://firebase.google.com/docs/cloud-messaging/manage-tokens
- Apple Developer documentation, "Sending notification requests to APNs" (best-effort delivery, storage, `apns-collapse-id`), unversioned page, read 2026-11-08. https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
- Apple Developer documentation, "Generating a remote notification" (sensitive data in payloads, 4 KB limit), unversioned page, read 2026-11-08. https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification
- Apple Developer documentation, "Handling notification responses from APNs" (410, which errors not to retry), unversioned page, read 2026-11-08. https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns
- Kit standards: `nestjs-standards` 05 (4.4, 4.8, 4.9), 12; `flutter-standards` 08, 09, 16 (11.6); `react-standards` 05 (4.4); thor "Mutation queues"; `database-drizzle`; `observability-and-debugging` `01-structured-logging.md`; `security-engineering` `20-api.md`, `30-mobile.md`, `50-secrets-logs-errors.md`.
