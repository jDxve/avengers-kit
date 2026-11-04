## 4. Rules

### 4.1 Controllers

**REQUIRED**
- Route definition, guard stack, DTO binding. No business logic, no database access.
- Return a mapped response type, never a raw Drizzle row.
- **Authentication is deny-by-default.** Register the auth guard globally and opt routes out
  explicitly. Never rely on remembering to add a guard per controller, because the failure
  mode is a silently unprotected endpoint.

  ```ts
  // common/decorators/public.decorator.ts
  export const IS_PUBLIC_KEY = 'isPublic';
  export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

  // common/guards/jwt.guard.ts
  @Injectable()
  export class JwtGuard extends AuthGuard('jwt') {
    constructor(private reflector: Reflector) { super(); }

    canActivate(ctx: ExecutionContext) {
      const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
        ctx.getHandler(),
        ctx.getClass(),
      ]);
      return isPublic ? true : super.canActivate(ctx);
    }
  }

  // app.module.ts
  providers: [{ provide: APP_GUARD, useClass: JwtGuard }]
  ```

- **Authorization is per-route and explicit.** Global auth says who the caller is. It never
  says what they may do. Every non-public route declares `@Roles(...)` or an equivalent, and
  every resource lookup is scoped to ownership (section 8).
- **Ordering constraint:** `APP_GUARD` guards run before controller-level guards, and among
  themselves in registration order. A global guard that needs `request.user` must be
  registered after the auth guard, or it will read an empty context. If that ordering is
  hard to guarantee, move the guard to controller level instead. Policy guards that depend
  on the authenticated user (password age, idle session, MFA enrollment) are the usual
  casualties here.

**DEFAULT**
- Split by audience when their guard stacks or shapes genuinely differ: `admin/`, `user/`,
  `public/`. One controller plus `RolesGuard` is fine for a small domain.

### 4.2 Services

**REQUIRED**
- Business logic lives in services, never in controllers, guards, or interceptors.
- Constructor injection. Never `new` a service.
- A facade that only forwards one call per method is deleted. Inject the real services
  directly. A facade is justified when it orchestrates several services, owns a transaction
  spanning them, or applies a rule before delegating.

**DEFAULT**
- Split by responsibility, not by entity. A cohesive service with several closely related
  operations is correct. Split when the operations have different business rules, different
  collaborators, different testing needs, or change for different reasons.
- **Review trigger, not a rule:** a service past ~300 lines or ~8 public methods gets a
  cohesion check at review. Often it is fine. Sometimes it is three services wearing one
  name. Line count prompts the question; it does not answer it.

### 4.3 Validation and contracts

**REQUIRED**
- Global validation pipe with Zod via `nestjs-zod`. No other validation library.

  ```ts
  export const CreateUserSchema = z.object({ email: z.string().email() }).strict();
  export class CreateUserDto extends createZodDto(CreateUserSchema) {}

  // app.module.ts
  providers: [{ provide: APP_PIPE, useClass: ZodValidationPipe }]
  ```

- **Mass assignment is blocked.** Request schemas use `.strict()`, so an unknown key such as
  `role`, `isAdmin` or `status` returns 400. Response schemas strip unknown keys. `.strict()` is
  not recursive: apply it to every nested object, or a nested unknown key is silently stripped.
  Installed mobile clients cannot be recalled, so keep accepting a removed request field until
  your minimum supported version no longer sends it.
- Environment variables validated at boot. The process fails to start on a missing or
  malformed value. A server that starts without a secret and dies on first request is worse
  than one that never starts.
- Response DTOs are defined. The output shape is part of the contract.
- OpenAPI generated from the DTOs, served in non-production and exported in CI.
- One error response shape across the entire API, with stable machine-readable codes:
  ```json
  { "code": "PAYROLL_PERIOD_LOCKED", "message": "...", "requestId": "..." }
  ```
  Clients branch on `code`, never on `message`. Message text is free to change, codes are
  not.

**Backward compatibility:** within a version, adding optional fields is safe. Removing a
field, renaming one, tightening validation, or changing an error code is breaking and needs
a new version or a deprecation window.

### 4.4 Database

**REQUIRED**
- **Transactions where writes must be atomic.** If two writes must both succeed or both be
  undone, they share a transaction. Writes that are independent do not need one.
- When a transaction spans services, the caller opens it and passes the executor down:
  ```ts
  async create(data: CreateUser, tx: Executor = this.db) { ... }
  ```
  A service never opens its own transaction if it can be called from inside another.
- **A database transaction cannot roll back the outside world.** It will not unsend an
  email, uncharge a card, or unpublish a message. For work crossing a system boundary:
  commit your own state first, then dispatch, using the transactional outbox pattern (write
  the intent in the same transaction, a worker dispatches it afterward) and make the
  dispatch idempotent. Where a multi-step external workflow must be undone, model
  compensating actions explicitly. Do not pretend a transaction covers it.
- Migrations are generated with `drizzle-kit generate`, reviewed, committed, and applied by a
  separate controlled deploy step (`drizzle-kit migrate`), never by each app instance.
  `drizzle-kit push` is allowed only against a local disposable database, never a shared, CI,
  staging or production one. Any PR with schema changes includes the generated migration. Never
  hand-edit the database above local.
- Every list endpoint is paginated. No query without `.limit()`.
- **Money is never binary floating point.** Store integer minor units (cents) or the
  database's exact decimal type, and do the arithmetic in that representation end to end.
  `0.1 + 0.2` is the classic demo, but the real damage is a rounding drift that reconciles
  to a few cents off and takes a week to trace.
- **Time is stored as an unambiguous instant**, normally UTC with a timezone-aware column.
  Business-local calendar rules (a cutoff at 5pm local, a pay period boundary, a holiday)
  are applied explicitly at the point of use, with the zone named in code rather than
  inherited from the server's locale. Store the zone alongside the instant when the local
  interpretation itself is part of the record.
- Enforce invariants with database constraints wherever the database can express them. An
  application-level check is a convenience for the user; the constraint is the guarantee.

**DEFAULT**
- Index foreign keys used in joins or filters. Postgres does not create these automatically
  (unlike the index behind a unique constraint), and a missing one shows up as a sequential
  scan on every join. Index columns used to filter or sort list endpoints.
- Indexes cost write throughput and storage, so validate against real query plans rather
  than adding one per column. `EXPLAIN ANALYZE` on your three slowest list endpoints finds
  more than guessing does.
- Direct Drizzle access in services, no repository layer. It is simpler and it is the norm
  with Drizzle. The cost is that unit tests must mock the Drizzle client, so where a domain has
  heavy branching rules, separate the rule from the query and test the rule alone.
- Watch for N+1: an `await` inside a `.map()` that touches the database is almost always one.

### 4.5 Module boundaries

**REQUIRED**
- **The dependency graph is acyclic.** Domains may depend on other domains. They may not
  form a cycle.
- Cross-domain access goes through the other module's `exports`. Never reach into its
  internal services, repositories, or tables. A module's exports are its public API; treat
  everything else as private.
- **`forwardRef` is forbidden between domain modules.** It exists to paper over a cycle, and
  a cycle between domains means the boundary is wrong. Fix it by one of: moving the shared
  concept into the module that owns it, extracting a third module, or inverting one
  direction into an event.
- Narrow exception: a framework or third-party integration that genuinely requires it, where
  restructuring would do more harm. It carries a comment naming the constraint, and it is
  called out in the PR. It is never the resolution to a domain-to-domain cycle, and
  "restructuring is inconvenient" is not the constraint.

**DEFAULT**
- Direct dependency for synchronous reads and for operations the caller must know succeeded
  (Orders asking Inventory to reserve stock).
- Domain events for fan-out and for anything the caller does not need to wait on (Orders
  emits `order.placed`, Notifications and Analytics react). Events also break would-be
  cycles.
- `@Global()` for database, config, and logger only. Everything else is imported explicitly.

### 4.6 Errors

**REQUIRED**
- `common/errors/` holds the **base classes and the filter mapping only**: `DomainError`,
  `NotFoundError`, `ConflictError`, `ForbiddenError`, and how each maps to an HTTP status.
  Generic infrastructure, no business meaning.
- **Specific business errors live with the domain that owns them**, in
  `modules/<domain>/<domain>.errors.ts`. `PayrollPeriodLockedError` belongs to payroll, not
  to `common/`. Otherwise the shared folder slowly accumulates domain knowledge, which is
  the thing section 3 exists to prevent.
- Error codes are unique across the API. Prefix them by domain (`PAYROLL_*`, `LEAVE_*`) so
  uniqueness is structural rather than a thing you have to check.
- The filter maps known domain and application errors to the error contract. Everything
  else, meaning genuine programming failures, returns a generic 500 carrying only the
  request id, and is logged and sent to error tracking. Do not invent a domain error for
  every unexpected exception; an error code is a promise to clients and should only exist
  for conditions they can act on.
- Never leak stack traces, Drizzle or driver errors, SQL, or table names to clients.
- **Catching is for translating a failure you expected, never for relabelling one you did
  not.** An empty `catch {}` is always wrong, but so is wrapping everything you catch in a
  domain error. Three cases, three behaviors:
  - A domain error from a layer below: let it through untouched. Re-wrapping it loses the
    code the client was going to branch on.
  - An infrastructure failure you anticipated and can describe (a unique-constraint
    violation that means "already exists", a provider timeout, a storage quota): translate
    it into the domain error that says what happened, attaching the original as `cause`.
  - Anything else: do not catch it at all, or log and rethrow it unchanged. It reaches the
    filter as an unexpected failure and becomes a generic 500. A `TypeError` dressed up as
    `PAYROLL_COMPUTATION_FAILED` tells the client to retry a bug.
- The response carries the request id so a user report maps to a log line.

### 4.7 Logging and observability

**REQUIRED**
- Structured logs. No `console.log` in committed code.
- A request id on every log line, propagated through async work, returned in error
  responses.
- Never log secrets, tokens, passwords, OTPs, full auth request bodies, or regulated
  personal data.
- Production log level `info` or above. `debug` is never on in production.
- Unhandled rejections and uncaught exceptions logged before exit.
- Error tracking wired up (Sentry or equivalent).

**DEFAULT**
- Log business events, not only HTTP traffic. "Payroll run 42 finalized by user 7" is worth
  more at 2am than a 200 status line.
- Metrics and tracing when you have the surface to justify them. A single service rarely
  needs distributed tracing.

### 4.8 Auth lifecycle

**REQUIRED**
- Passwords hashed with bcrypt or argon2, cost factor configurable.
- Short-lived access token, long-lived refresh token.
- Server-side revocation that actually works: logout, password change, and role change all
  invalidate existing sessions. A stateless JWT with no revocation list cannot do this, so
  either keep a session or denylist record, or accept the access-token TTL as your worst
  case and keep it short.

**Refresh token rotation, specified.** The usual implementations are subtly wrong, so this
is the full shape:

- **The invariant: one live successor per family.** A family has at most one unused,
  unrevoked, unexpired token at any moment. Everything else in this subsection exists to
  protect that sentence. Break it and reuse detection becomes meaningless, because a family
  with two valid chains can no longer tell a retry from a theft.

  Enforce it in the schema, not in application code:

  ```sql
  CREATE UNIQUE INDEX one_live_token_per_family
      ON refresh_tokens (family_id)
   WHERE used_at IS NULL AND revoked_at IS NULL;
  ```

  A second successor is then rejected by the database rather than discouraged by a comment.
- **Storage.** One row per issued refresh token: `id`, `familyId`, `userId`, `tokenHash`,
  `expiresAt`, `usedAt`, `revokedAt`, `replacedBy`. Store a hash, never the token itself; a
  leaked database should not yield usable sessions. A family is one login on one device, and
  it persists across every rotation within that login. `replacedBy` makes the chain explicit
  and is what the rules below read.
- **Rotation is atomic.** Claiming the old token, inserting its replacement, and setting
  `replacedBy` happen in one transaction. A partial rotation leaves the user with no valid
  token and no way back.
- **Claim by conditional update.** Exactly one request may consume a token, so claim it with
  a predicate and check the affected-row count:

  ```sql
  UPDATE refresh_tokens SET used_at = now()
   WHERE id = $1 AND used_at IS NULL AND revoked_at IS NULL;
  -- rowCount 0: someone else already claimed it, or it was revoked
  ```

- **What to do when the claim fails.** Do not reach for a clock. The state of the successor
  answers the question precisely:

  | State of the presented token | Meaning | Response |
  |---|---|---|
  | `replacedBy` set, successor **unused** | A concurrent refresh or a retry. The legitimate client has not yet proved it holds the successor | `409 REFRESH_IN_PROGRESS`, retriable. **Issue nothing.** Do not revoke |
  | `replacedBy` set, successor **already used** | The legitimate client moved on, so whoever holds this old token should not have it | Theft. Revoke the whole family, log a security event |
  | `revokedAt` set | Family already revoked | `401`. Issue nothing |

  The second row is the sharp rule. "Was the successor consumed" is a fact; "was this within
  60 seconds" is a guess, and a guess is what lets both a retry and an attacker through.

- **Why the loser gets nothing.** Issuing it a fresh token would create a second live
  successor and break the invariant above. Instead it retries: for a cookie-stored token the
  browser already holds the winner's `Set-Cookie`, so the retry presents the new token and
  succeeds. For a client that stores the token itself, refresh must be single-flight within
  the client and written to storage shared across tabs. Treat `REFRESH_IN_PROGRESS` as
  "re-read your stored token and try again", with a small bounded number of attempts.

- **The one genuinely hard case: the response was lost.** The server rotated, the client
  never received the successor. The client holds a used token and nothing else, and from the
  server's side this is indistinguishable from the concurrent case, so it gets the same
  `409`. Two defensible policies, and you must pick one in writing:

  **Strict (DEFAULT).** No re-issue. The client re-authenticates. A stolen token whose
  successor is unconsumed cannot be turned into a session.

  **Recoverable.** Allow re-issue, but only by revoking the unused successor and minting the
  replacement **in the same transaction**, so exactly one live token survives and the
  invariant holds. The cost is real and must be accepted explicitly: an attacker holding a
  stolen token with an unconsumed successor can take the session over this way, kicking the
  legitimate client. That event is at least loud, so if you choose this, rate-limit it per
  family, log every occurrence as a security event, and alert on repeats.

  Storing the successor in recoverable form so a retry can be handed the identical token is
  a third option, and a worse one: it puts a live credential at rest to solve a problem a
  retriable `409` already solves for cookie clients.

- **Test these four separately**, because they are four different code paths: two
  simultaneous refreshes with the same token (exactly one succeeds, the other gets `409`,
  the family survives); a retry after a lost response (per your chosen policy); reuse of a
  token whose successor was consumed (family revoked); and refresh in an already-revoked
  family (`401`, nothing issued). Assert on the row count in `refresh_tokens` too: a family
  must never hold two live tokens.
- **Revocation semantics.** Logout revokes one family. Password change and "sign out
  everywhere" revoke every family for that user. Role and permission changes must take
  effect on a schedule matching their risk: revocation is only checked at refresh time, so
  an already-issued access token keeps its old claims until it expires. If that window is
  unacceptable for privilege changes, carry an authorization version in the token and check
  it per request. **Write the worst-case exposure window down**, and test that the behavior
  matches the number.
- **Verify tokens, don't just decode them.** Pin the accepted algorithm explicitly, and
  validate issuer, audience, and expiry. A decoder that accepts whatever `alg` the token
  declares accepts `none`, and a verifier that accepts both RS256 and HS256 can be tricked
  into verifying a forged token with the public key as the HMAC secret. Never trust a
  decoded-but-unverified payload for anything.
- Signing keys live in a secret manager or the deployment environment, never in the repo,
  with a documented rotation and compromise procedure.
- **If tokens are in cookies:** `HttpOnly`, `Secure`, and an explicit `SameSite` policy, and
  CSRF protection, because the browser attaches the cookie whether or not your frontend
  asked it to. If the client stores tokens itself, write down the XSS assumption you are
  accepting.
- Rate limiting on login, OTP, password reset, registration, and invite redemption. Limit on
  both account and source, since account-only limits are trivially bypassed by rotating IPs
  and source-only limits miss distributed attempts against one account.
- Failed-attempt tracking, verified end to end. **Lockout is a denial-of-service vector:**
  an attacker who knows an email can lock the owner out at will. Prefer escalating delay,
  or a time-boxed lock with a self-service unlock path, over an indefinite one that needs an
  admin.
- Revocation reaches long-lived connections too (websockets), not just HTTP.

### 4.9 Async work

**REQUIRED, if you have a queue**
- Jobs are idempotent. They will be retried.
- Retries have backoff and a ceiling, plus a dead-letter path.
- A failed notification never fails the parent request.

**DEFAULT**
- Anything slow, retryable, or inessential to the response goes on the queue: email, SMS,
  exports, report generation, outbound webhooks.

### 4.10 Naming and files

- Files: `kebab-case.<type>.ts` (`create-user.service.ts`, `user.controller.ts`).
- Classes: `PascalCase` matching the filename.
- Barrel `index.ts` is optional. They are a common cause of Nest DI failures through
  circular imports, so when a provider resolves as `undefined`, suspect a barrel first.

### 4.11 Testing

**REQUIRED**
- Unit tests for: money and date math, permission logic, state machines, and anything with
  branching business rules.
- e2e tests run against a real database (containerized or disposable), not mocks.
- Every concurrency guard from section 6 has a test that actually runs two operations
  against the same row.

**DEFAULT**
- Tests next to the code as `*.spec.ts`, e2e in `test/`.
- Test behavior, not implementation. A test that breaks when you rename a private method is
  testing the wrong thing.

---

