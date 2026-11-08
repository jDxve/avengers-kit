# Caching with Redis

Scope: a server-side cache in Redis shared across requests and instances of a NestJS backend, and how it relates to the client caches Flutter and React already keep. The rules for when Redis is added and why in-memory caches break with more than one instance live in [`nestjs-standards` 03](../../nestjs-standards/references/03-stack.md) and [08](../../nestjs-standards/references/08-multi-instance-gotchas.md). HTTP cache headers live in [`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md). This recipe adds key design, invalidation, expiry, and stampede protection.

## When it is justified

`nestjs-standards` 03 adds Redis only when "You need shared cache, distributed locks, or rate limiting across instances". A cache is added for a stated need with a measured number: a query or provider call that is slow or costly under real load, found by profiling ([`observability-and-debugging`](../../observability-and-debugging/references/05-profiling.md) `05-profiling.md`) after the index and query review in `database-drizzle` `02-indexes-and-queries.md` (kit rule for the number). The project's contract states the need and the target (AGENTS.md rule 6). A hosted Redis is an Open decision for Dave.

## Contract sections it fills

- Domain: each cached value, its source of truth, its owner (one service), its key shape, and its time to live.
- Invariants: the rows below, per cached value, including which writes invalidate it.
- Failure paths: behavior when Redis is slow or down.
- Release: the Redis connection settings by secret name, and whether the cache is warm or cold at deploy.
- Open decisions: hosting; the staleness each value may show.

## Invariants and enforcers

| Invariant | Enforced by |
| --- | --- |
| Added only for a stated, measured need | Kit rule; `nestjs-standards` 03 |
| Every key of per-user or per-tenant data includes the tenant and user it was read for, and keys are built by one helper | Kit rule. The same rule on the device: [`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.6 "Caching and invalidation" (keys include the user id); structured keys in [`react-standards` 05](../../react-standards/references/05-rules.md) 4.4 |
| The cache is never an authorization source. Authorization and tenant scope are checked first, against the session and the database, and only then is the cache read | Kit rule, `docs/contracts/kit-skills.md` section 9; `SEC-API-01` |
| Every key has a time to live, set in the same command that writes the value | Kit rule. Redis: `SET` accepts `EX`, `PX`, `EXAT`, `PXAT`; a plain `SET`, `DEL`, or `GETSET` clears an existing timeout, while `INCR`, `LPUSH`, and `HSET` leave it untouched (Redis `EXPIRE`) |
| A write invalidates or rewrites the keys it affects, after its transaction commits, and the time to live bounds the damage when an invalidation is lost | Kit rule; [`nestjs-standards` 05](../../nestjs-standards/references/05-rules.md) 4.4 (nothing external inside a transaction) |
| A miss on a hot key rebuilds it once, not once per request (stampede protection) | Kit rule: a short rebuild flag set with `SET <key>:rebuild <token> NX EX <seconds>`; the holder rebuilds, the others serve the stale value or wait briefly. Redis documents `SET ... NX EX` as a simple lock and discourages it in favor of Redlock where a lock must be safe; here the worst case is a duplicate rebuild, which is acceptable. Expiry times are spread with jitter (kit rule) |
| Redis being slow or down degrades to the database, not to an error | Kit rule; timeouts on the Redis client like any outbound call ([`nestjs-standards` 12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) "HTTP") |
| Per-user responses are never cacheable in a shared HTTP cache | `nestjs-standards` 12; `SEC-API-17` |
| A distributed lock is not a substitute for a constraint or an idempotency key | [`nestjs-standards` 07](../../nestjs-standards/references/07-concurrency-and-data-integrity.md) item 5 |

## Flutter

The device cache already has its rules: every cache has a TTL and one owning repository, keys include the user id, mutations invalidate, and pull-to-refresh bypasses ([`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.6). Sign-out clears it (`SEC-MOB-06`). A server cache changes none of that; the app cannot tell whether a response came from Redis.

## React or Next.js

The query cache has its own `staleTime` per query type and is invalidated by mutations ([`react-standards` 05](../../react-standards/references/05-rules.md) 4.4). Sign-out clears it (`SEC-WEB-09`). In Next.js, the framework's own caching is the subject of `react-standards` `17-nextjs-app-router.md`, not this recipe; a server component that reads per-user data never stores it in a cache shared between users (kit rule, same rule as `SEC-API-17`).

## NestJS

One service owns each cached value: it reads through the cache, writes to the database, and invalidates after commit. Rate limit counters and other in-memory state move to Redis when there is more than one instance ([`nestjs-standards` 08](../../nestjs-standards/references/08-multi-instance-gotchas.md)). Cached values hold only what the response needs, and no secret or token (`SEC-LOG-01` applied to the cache, kit rule). The Redis password and URL are secrets in config (`SEC-LOG-11`, `SEC-LOG-13`).

## Security items

`SEC-API-01`, `SEC-API-02`, `SEC-API-17`, `SEC-LOG-01`, `SEC-LOG-11`, `SEC-LOG-13`, `SEC-MOB-06`, `SEC-WEB-09`.

## Failure paths and what the user sees

| Failure | What the user sees |
| --- | --- |
| Redis down or slow | Slower responses, same data; an alert for the operator |
| Invalidation lost | Stale data for at most the key's time to live, which the contract accepted for that value |
| Cold cache after deploy | Slower first requests; the rebuild flag stops the database being hit once per request |

## Tests

- e2e: the cross-tenant test from `database-drizzle` `07-tenant-scoping.md`, run with the cache warm for tenant A, returns nothing of A's to tenant B.
- e2e: a write, then a read, returns the new value.
- Integration against a local Redis: every key written during the suite has an expiry. The agent writes it and the command; Dave runs it if starting Redis is outside what the settings allow.
- Unit: many concurrent misses on one key call the loader once.
- Unit: a Redis client that times out falls back to the database and the request succeeds.
- e2e: each authenticated `GET` has the `Cache-Control` from `SEC-API-17`.

## Sources

- Redis documentation, "EXPIRE" (what clears a timeout), Redis Open Source docs, latest, read 2026-11-08. https://redis.io/docs/latest/commands/expire/
- Redis documentation, "SET" (`NX`, `EX` and the other expiry options, the locking pattern note), Redis Open Source docs, latest, read 2026-11-08. https://redis.io/docs/latest/commands/set/
- Kit standards: `nestjs-standards` 03, 05 (4.4), 07, 08, 12; `flutter-standards` 16 (11.6); `react-standards` 05 (4.4); `database-drizzle` `02-indexes-and-queries.md`, `07-tenant-scoping.md`; `observability-and-debugging` `05-profiling.md`; `security-engineering` `20-api.md`, `10-web.md`, `30-mobile.md`, `50-secrets-logs-errors.md`.
- Not read:
  - Redlock: named by the Redis `SET` page; the Redlock page itself was not read, so nothing here rests on it.
