## 11. API behavior and external dependencies

### HTTP

**REQUIRED**
- Explicit limits on request body, headers, and URL length, sized to what the endpoints
  actually accept rather than left at the framework default.
- Outbound calls have connect and read timeouts. Retries are bounded, use backoff with
  jitter, and only wrap operations that are safe to repeat. Watch for retry multiplication:
  three layers each retrying three times is 27 requests from one click.
- Pagination semantics are defined: a stable sort, a maximum page size, and cursor
  pagination where offset pagination gets expensive or shifts under inserts.
- Correct status codes, and an explicit `Cache-Control` policy. Private or per-user
  responses are never cacheable in a shared cache.
- Each request gets a correlation id. A caller-supplied one is validated and length-limited
  before use, or replaced. It is never an authorization signal.

### External integrations

**REQUIRED**
- Every provider response is untrusted input. Validate its shape before using it, with the
  same rigor as a request body.
- Credentials live in a secret manager or the deployment environment, with a rotation
  procedure written down.
- Webhooks: verify the signature against the **raw** request body, before any JSON parsing
  or body-parser middleware rewrites it. Enforce timestamp or replay protection where the
  provider supports it, and make handling idempotent, because providers redeliver.
- Behavior is defined for provider timeouts, rate limits, partial outages, and duplicate
  callbacks. "It usually works" is not a definition.
- **A timeout does not mean the operation did not happen.** The request may have succeeded
  with the response lost in transit. Before retrying anything irreversible, reconcile:
  look the operation up by your idempotency key or query its status. Blind retries on
  timeout are how a payment gets charged twice.

### Uploads

**REQUIRED, if you accept uploads**
- Enforce the size limit before any expensive processing, not after.
- Validate file content, not the extension or the client-supplied MIME type. Both are
  attacker-controlled.
- Storage keys are generated server-side. Uploads live outside any executable web root,
  and download access is authorized the same way any other resource is.
- Never log file contents or sensitive metadata.

---

