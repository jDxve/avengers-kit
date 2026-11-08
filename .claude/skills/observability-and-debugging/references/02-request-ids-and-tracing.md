# Request ids and tracing

Scope: one id that follows a request from the client through the server and back in the error response, so a user's report, a tracker event, and the server's log lines can be joined; and when distributed tracing is worth adding. The rules are owned by [`nestjs-standards` 05, 4.7](../../nestjs-standards/references/05-rules.md) (a request id on every log line, propagated through async work, returned in error responses; tracing only when there is the surface for it), [12](../../nestjs-standards/references/12-api-behavior-and-external-dependencies.md) (each request gets a correlation id; a caller-supplied one is validated and length-limited or replaced, and never used for authorization), [03](../../nestjs-standards/references/03-stack.md) (distributed tracing only with more than one service to trace across), 4.3 (the error shape `{ code, message, requestId }`), and [`react-standards` 05, 4.6](../../react-standards/references/05-rules.md) (the user sees a generic message plus the `requestId`; the tracker gets it too). The check for a caller-supplied id is `security-engineering` `SEC-API-18`.

## The chain

1. **Server assigns the id** at the start of each request, in middleware or an interceptor that runs before anything logs. If the client sent one, the server validates its format and length or replaces it (12; `SEC-API-18`).
2. **Every log line carries it**, including lines written by async work the request started: a queued job or an outbox row stores the id it was created under and logs it when it runs (4.7, "propagated through async work").
3. **Every error response carries it** as `requestId` (4.3). A project may also return it in a response header on every response; the kit standards do not name a header, so the project records its choice.
4. **The client shows it** on an error screen, generic message plus id (4.6; `SEC-LOG-08`), and **attaches it to the tracker event** for that failure (4.6, "with the release version and the `requestId` attached").
5. **Support and debugging start from it**: the user quotes it, and every server line and tracker event for that request is one search away.

Flutter gap: `security-engineering` `SEC-LOG-08` records that `AppException` in `flutter-standards` 08 has no `requestId` field yet, so a Flutter client cannot show or report the id until the standard adds it. Until then, a Flutter bug report joins to server logs by time, user id, and route only, which is weaker; say so in the report.

## Joining a client report to server lines

| Starting point | Where the id is | Next |
| --- | --- | --- |
| A user's screenshot or support ticket | The error screen's id | Server lines with that `requestId` |
| A web tracker event | The event's `requestId` tag or context | Server lines with that `requestId`, and the event's breadcrumbs for what the user did before |
| A Flutter crash report | Not present (gap above) | `NetworkFailure` method, templated path, and status, plus time and user id, to narrow the server lines |
| A server error line | The line's `requestId` | The tracker events tagged with it, if the client sent one |

The timeline built from these is step 2 of `03-log-to-failing-test.md`.

## Tracing: only with more than one service

A single NestJS service rarely needs distributed tracing (4.7 DEFAULT; 03 lists it under "Add when a requirement justifies it"). The request id and structured logs answer "what happened in this request". Add tracing when a request crosses services the project runs (an API and a worker over a queue, or two APIs), and the contract or `docs/ops.md` states the need (AGENTS.md rule 6).

When a project adds it:

- **Use W3C Trace Context.** The W3C Recommendation (23 November 2021) defines the `traceparent` header, which carries a 16-byte trace id and an 8-byte parent id in a fixed-length format, and the optional `tracestate` header for vendor data. A trace id or parent id of all zeros is invalid, and a receiver must ignore a `traceparent` whose trace id is invalid.
- **OpenTelemetry's default propagator uses those W3C headers**, per the OpenTelemetry context propagation docs. Propagation is usually handled by the instrumentation libraries; the Propagators API is for manual cases.
- **Keep personal data out of trace headers.** The specification says tracing vendors must not use `traceparent` or `tracestate` for personally identifiable or sensitive information, and that services may restart the `traceparent` at trust boundaries, for example for requests to or from external services.
- **Treat an incoming `traceparent` like the request id**: it correlates, it never authorizes (12).
- **Log the trace id next to the request id** so a log line leads to its trace.
- Span attributes follow the same redaction rules as log fields (`01-structured-logging.md`).

Choosing a tracing backend, an exporter, and a sampling rate is infrastructure: the project's ops record names it, and it is added only for the stated need (`devops-engineering` Observability, "Use what the project's platform already gives you").

## Review questions

1. Is the id assigned before the first log line of a request, and is a client-sent id validated or replaced?
2. Do queued jobs and outbox dispatch log the id of the request that created them?
3. Does every error response, including validation and auth failures, carry `requestId`?
4. Does each client show it and attach it to tracker events? For Flutter, is the gap recorded?
5. If tracing exists, is there more than one service, and is the need written down?

## Sources

- W3C, "Trace Context", W3C Recommendation 23 November 2021, read 2026-11-08 (sections on `traceparent`, `tracestate`, trace-id and parent-id, and 6. Privacy Considerations). https://www.w3.org/TR/trace-context/
- OpenTelemetry documentation, "Context propagation", read 2026-11-08. https://opentelemetry.io/docs/concepts/context-propagation/
- Kit standards: `nestjs-standards` 03, 05 (4.3, 4.7), 12; `react-standards` 05 (4.6); `flutter-standards` 08; `security-engineering` `20-api.md` and `50-secrets-logs-errors.md`; `devops-engineering` SKILL.md.
