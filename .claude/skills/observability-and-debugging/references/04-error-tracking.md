# Error tracking

Scope: what an error tracker must receive on each stack so an event can be read, grouped, and joined to the server's logs, and what it must never receive. The rules are owned by `devops-engineering` [SKILL.md](../../devops-engineering/SKILL.md) "Observability" (error tracking with the release version; alerts on symptoms, each with an owner and a runbook), [`nestjs-standards` 05, 4.7](../../nestjs-standards/references/05-rules.md) (error tracking wired up; unhandled rejections and uncaught exceptions logged before exit), [`react-standards` 05, 4.6](../../react-standards/references/05-rules.md) (global handlers, boundaries, release and `requestId` attached) and [11](../../react-standards/references/11-production-readiness.md) (source maps uploaded and not served publicly unless intended), and [`flutter-standards` 08](../../flutter-standards/references/08-core-layer.md) ("Crash reporter", "Reporting interceptor") and [16](../../flutter-standards/references/16-production-and-release.md) 11.3 to 11.5 (symbols, alerts, halt criteria). The scrubbing checks are `security-engineering` `SEC-LOG-03` and `SEC-LOG-08`. This file adds the cross-stack checklist. The tracker product is the project's choice; its own documentation is the source for its API, and none is named or cited here.

## What every event carries

| Field | Why | Owner |
| --- | --- | --- |
| Release version: the commit SHA on web and server, the build number on mobile | Ties the event to one artifact, so a regression is visible per release and a rollback can be checked | `devops-engineering` Observability; react 11; flutter 16 |
| Environment | Keeps staging noise out of production alerts | Kit rule |
| `requestId`, when the failure followed an API call | Joins the event to the server's log lines (`02-request-ids-and-tracing.md`) | react 4.6 |
| Internal user id and tenant id, never an email or a name | Counts affected users without sending personal data | Kit rule, from `SEC-LOG-01` |
| A templated route (`/orders/:id`), never a raw URL or query string | Groups events by endpoint and keeps ids and search terms out | flutter 08 `NetworkFailure`; `SEC-LOG-04` |

## Readable stack traces

- **Web**: upload source maps to the tracker for each release, and do not serve them publicly unless that is intended (react 11). Verify by forcing an error in a release build on a local or staging deploy and reading the event's frames.
- **Flutter**: build with `--obfuscate --split-debug-info`, archive the symbol files per build number, and upload them to the crash reporter. "A release whose symbols were not uploaded is a release you cannot debug" (flutter 16, 11.3).
- **NestJS**: the server's own stack traces are readable as built; the release tag is what matters.

## What reaches the tracker, per stack

- **NestJS**: unexpected errors from the global exception filter, and unhandled rejections and uncaught exceptions before exit (4.7). Expected domain errors (4xx) are not tracker events; they are log lines (`01-structured-logging.md`, Levels).
- **React or Next.js**: the four failure classes of 4.6. Render errors through boundaries; event-handler, post-`await`, and timer failures through the global `error` and `unhandledrejection` handlers. Expected failures (403, 404, validation) are UI states, not events.
- **Flutter**: errors through `FlutterError.onError` and `PlatformDispatcher.onError` to the `Reporter` facade, and network failures only as `NetworkFailure` values, only when actionable: 5xx, certificate failures, unknowns. Offline, timeouts, cancellations, session expiry, and 4xx stay off the dashboard (08).

## What never reaches it

Owned by `SEC-LOG-01` and `SEC-LOG-03`: no request or response bodies, headers, cookies, query strings, tokens, or personal data, with the vendor's scrubbing hook as a second line (flutter 08 names `beforeSend` in Sentry). Breadcrumbs that record UI text or network calls follow the same rule. Check the tracker's defaults for automatic capture (console, network, input text) and turn off what would send personal data (kit rule).

## Grouping

Trackers group events into issues, and grouping is only as good as the event. Kit rules:

- An error message with a value inside it (an id, an amount, an email) splits one bug into many issues and leaks the value. Put values in fields, not in the message (`SEC-LOG-05` applies to errors as well as logs).
- A templated path, not a raw one, keeps one endpoint's failures together (flutter 08 notes the same for `NetworkFailure`).
- A wrapped error keeps its original as the cause, so the issue groups on the real origin rather than the wrapper.

## Alerts

`devops-engineering` Observability sets the rule: alert on symptoms users feel, each alert with an owner and a runbook. For the tracker that means:

- A new issue in a new release (flutter 16 11.4 "alert on any new fatal issue").
- Crash-free sessions below the project's threshold on mobile (flutter 16 11.5 gives 99.5% as a default halt criterion and asks you to record your own).
- An error-rate rise per release on web and server. Thresholds are the project's, recorded in `docs/ops.md` or the runbook, never invented here.

The four golden signals that frame alerting are in `05-profiling.md`, "Alerts".

## Review questions

1. Does every event carry release, environment, and, where there was a request, `requestId`?
2. Are source maps or symbols uploaded for this release, and are web source maps kept private?
3. Is the scrubbing hook configured and tested (`SEC-LOG-03`)?
4. Do expected failures stay out of the tracker?
5. Does each alert have an owner and a runbook?

## Sources

- None external. The tracker's own documentation, named by the project, is the source for its API and defaults; none was read for this file.
- Kit standards: `devops-engineering` SKILL.md; `nestjs-standards` 05 (4.7); `react-standards` 05 (4.6) and 11; `flutter-standards` 08 and 16; `security-engineering` `50-secrets-logs-errors.md`.
