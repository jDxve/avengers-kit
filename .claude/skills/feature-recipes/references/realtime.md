# Realtime updates

Scope: showing changes to Flutter and React users without a manual refresh, from polling up to WebSockets served by NestJS. The stack rules for when WebSockets earn their place and what breaks with more than one instance live in [`nestjs-standards` 03](../../nestjs-standards/references/03-stack.md) and [08](../../nestjs-standards/references/08-multi-instance-gotchas.md). This recipe adds the connection security, the resync after a reconnect, and the client side. Server-sent events and NestJS's own gateway documentation were not read, so neither is described here.

## When it is justified

Polling first. `nestjs-standards` 03 lists WebSockets under "Add when a requirement justifies it": "You need server-push. Polling is often enough." Before a socket, try the query layer's refetch on focus and a short `staleTime` ([`react-standards` 05](../../react-standards/references/05-rules.md) 4.4), or a timed refresh in the Flutter notifier. A WebSocket server, and the Redis adapter it needs with more than one instance, arrive only when the project's contract states the need with a number (how fresh, for how many users) (AGENTS.md rule 6; kit rule for the number). A hosted realtime vendor is an Open decision for Dave.

## Contract sections it fills

- Domain: the events (name, payload of ids and a version or cursor), and the channels or rooms a user may join.
- API: the connect endpoint and how it authenticates; the REST endpoint that returns missed changes after a cursor.
- Authorization: who may join which channel, and who may send which message.
- Security: the boundary rows below; message size and rate limits.
- Invariants, Failure paths, Tests, Release (the adapter, sticky sessions, proxy upgrade settings), Open decisions (polling or sockets, vendor).

## Invariants and enforcers

| Invariant | Enforced by |
| --- | --- |
| The connection is authenticated before any protected data is sent. RFC 6455 prescribes no authentication; the server uses its usual HTTP mechanisms | RFC 6455 10.5. OWASP WebSocket cheat sheet: until the token is validated, accept only the authentication message and send nothing protected; close on failure or timeout |
| With cookie auth, the handshake checks `Origin` against an allowlist, because browsers send cookies on the handshake (cross-site WebSocket hijacking) | RFC 6455 10.2 (servers SHOULD verify `Origin` and answer 403 when it is unacceptable); OWASP "Origin Header Validation", allowlist only; CSRF token in the handshake where the app already uses one |
| Tokens never go in the URL query string | OWASP (they leak into access logs); `SEC-LOG-04` |
| Every message is authorized, not just the connection: joining a channel checks ownership like any lookup, and the server filters each outgoing event by the recipient's access | OWASP "Message-Level Authorization"; `SEC-API-01` and `SEC-API-02` applied to channels (kit rule) |
| Every incoming message is validated with a strict Zod schema and a size limit | RFC 6455 10.4 (implementations SHOULD limit frame and message size); OWASP "Input Validation"; `SEC-API-03` (kit rule to apply it here) |
| Sign-out and session expiry close the user's connections | OWASP "Session Management"; [`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.8 revocation |
| An event is a hint. The REST API is the source of truth, and after a reconnect the client fetches everything after its last cursor | Kit rule; cursor pagination from `api-contract` `05-idempotency-and-pagination.md` |
| A client ignores an event older than the state it already holds | Kit rule, by version or cursor; the same race as [`react-standards` 07](../../react-standards/references/07-async-correctness.md) item 1 (out-of-order responses) |
| With more than one instance, events reach clients on every instance | [`nestjs-standards` 08](../../nestjs-standards/references/08-multi-instance-gotchas.md): "Redis adapter plus sticky sessions"; `caching-redis.md` for Redis itself |
| Connections and messages are limited per user, idle connections close, and dead ones are found by ping and pong | OWASP "Denial-of-Service Protection" |
| Only `wss://` | RFC 6455 10.6 (implementations MUST support TLS and SHOULD use it); OWASP "Always Use WSS" |

## Flutter

The socket belongs to the data layer, behind a provider scoped to the session, so sign-out disposes it with the rest of the session's state (`SEC-MOB-06`; [`flutter-standards` 08](../../flutter-standards/references/08-core-layer.md) "Threat model and limits"). Reconnect with backoff and jitter, then resync from the cursor before applying new events (kit rule). A `ui/` widget receives the connection status as a value, never the socket (`ui-isolation`).

## React or Next.js

The subscription lives in a hook in the connected layer, cleans up on unmount ([`react-standards` 07](../../react-standards/references/07-async-correctness.md) item 2), and survives StrictMode's double effect (item 6). An event either writes into the query cache or invalidates the query keys it affects ([`react-standards` 05](../../react-standards/references/05-rules.md) 4.4). In Next.js the socket is opened from a client component (4.2); the server holds no per-user socket in a server component.

## NestJS

Authentication runs in the handshake, before the connection joins any channel. Channel names come from the server's lookup of what the user may see, not from the client's request. Log connect, authentication, authorization failures, and disconnects with the user id and request id, never message contents or tokens (OWASP "Security Monitoring and Logging"; [`observability-and-debugging`](../../observability-and-debugging/references/01-structured-logging.md) `01-structured-logging.md`). The proxy in front must pass the upgrade and allow long-lived connections (OWASP "Infrastructure Configuration"; `devops-engineering`).

## Security items

`SEC-API-01`, `SEC-API-02`, `SEC-API-03`, `SEC-API-08`, `SEC-API-14`, `SEC-API-16`, `SEC-LOG-01`, `SEC-LOG-04`, `SEC-MOB-06`, `SEC-WEB-06`, `SEC-WEB-09`.

## Failure paths and what the user sees

| Failure | What the user sees |
| --- | --- |
| Connection lost | A small "reconnecting" status; the data already shown stays |
| Reconnected | Missed changes appear after the resync, without a reload |
| Authentication fails or the session expired | The server closes the connection (RFC 6455 close code 1008, policy violation); the client runs its normal refresh or sign-out path |
| Message too large | The server closes with 1009 (message too big, RFC 6455) and the client reports a bug, not a user error |
| Join refused | The channel's forbidden state, same copy as the REST 403 or 404 |

## Tests

- e2e: connect without credentials is closed; a handshake with an unknown `Origin` gets 403; joining another user's channel is refused; sending past the size limit closes the connection.
- e2e: sign-out closes the user's open connections.
- e2e: events emitted while a client was disconnected are returned by the resync endpoint after its cursor.
- Unit: the client drops an event whose version is older than its state.
- Two instances: an event published on one reaches a client on the other. This needs Redis and two app processes; the agent writes the test and the command, and Dave runs it if it needs infrastructure the agent cannot start.

## Sources

- IETF RFC 6455, "The WebSocket Protocol" (sections 7.4.1, 10.2, 10.4, 10.5, 10.6), December 2011, read 2026-11-08. https://www.rfc-editor.org/rfc/rfc6455
- OWASP Cheat Sheet Series, "WebSocket Security Cheat Sheet", GitHub master at commit `fdd74a3` (2026-10-04), read 2026-11-08. https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html
- Kit standards: `nestjs-standards` 03, 05 (4.8), 08; `react-standards` 05 (4.2, 4.4), 07; `flutter-standards` 08; `api-contract` `05-idempotency-and-pagination.md`; `observability-and-debugging` `01-structured-logging.md`; `security-engineering` `20-api.md`, `10-web.md`, `30-mobile.md`.
