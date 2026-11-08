# Secrets, logs, and errors

Scope: the cross-stack checks for what never enters a log or crash report, how redaction is tested, how secrets are named and loaded, and what an error response may carry. The rules are owned by `nestjs-standards` [05-rules.md](../../nestjs-standards/references/05-rules.md) 4.6 (errors) and 4.7 (logging), `react-standards` [05-rules.md](../../react-standards/references/05-rules.md) 4.6 and [10-security.md](../../react-standards/references/10-security.md), `flutter-standards` [08-core-layer.md](../../flutter-standards/references/08-core-layer.md) ("Crash reporter", "Logging interceptor", "Reporting interceptor"), and `devops-engineering` [SKILL.md](../../devops-engineering/SKILL.md) "Config and secrets". Each item names its rule's home and adds how to verify it. Items with no home in a standard are marked kit rule.

Stack-specific items stay in their stack file: the Flutter interceptors are `SEC-MOB-03`, the web bundle is `SEC-WEB-17`, the web error screen is `SEC-WEB-20`. This file holds what is the same on every stack. None of the public sources below were read when this file was written (see Sources), so no item attributes a claim to them.

An agent that finds a secret or personal data in a log, a file, or a crash report reports its location and kind, never the value, and follows `60-incident-basics.md`.

## What never enters a log or a crash report

- [ ] SEC-LOG-01 No secret, token, password, OTP, full auth request body, or regulated personal data reaches a log line, a crash report, or an error tracker event, on any stack (`nestjs-standards` 4.7; `flutter-standards` 08 "What the reporter may receive"; `react-standards` 4.6). Verify: `SEC-LOG-02` passes for each stack in the repo; `grep -rnE "console\.(log|info|debug)|debugPrint|print\(" src lib app` and trace each hit that can see a request, a response, or a user record.
- [ ] SEC-LOG-02 Redaction has a test per stack that feeds a bearer token, a password, and a cookie through the real logger or reporter and asserts none of them appears in the output (kit rule; the Flutter instance is "the debug logger never prints a bearer..." in `flutter-standards` 08). Verify: find the test for each stack and run it; build the secret-shaped values at runtime, as in `testing-strategy` `06-fixtures-and-data.md`.
- [ ] SEC-LOG-03 Error tracker events are scrubbed before they leave the process: no request or response body, no headers, no query string, no cookie (`flutter-standards` 08 "Crash reporter", vendor scrubbing hook; `react-standards` 4.6; `nestjs-standards` 4.7). Verify: trace the tracker init on each stack to its scrubbing hook (for example `beforeSend`) and a test that calls the hook with an event carrying an `Authorization` header and asserts it is removed.
- [ ] SEC-LOG-04 No token, password, or personal data travels in a URL path or query string, because URLs are logged by proxies, servers, and trackers (kit rule; `flutter-standards` 08 "Reporting interceptor" on query strings). Verify: read each route and client call that takes a credential or a personal field and confirm it is sent in a header or body; `grep -rnE "[?&](token|access_token|password|email|otp)=" src lib app`.
- [ ] SEC-LOG-05 User-controlled values are logged as structured fields, never concatenated into the message string, so a value with a newline cannot forge a second log line (kit rule; structured logs per `nestjs-standards` 4.7). Verify: `grep -rnE 'logger\.(log|info|warn|error)\(.*\$\{' src` returns nothing that interpolates request data into the message; a test logs a value containing a newline and asserts one JSON line.
- [ ] SEC-LOG-06 Production logs at `info` or above, `debug` is never on in production, and the Flutter logging interceptor is registered only under `kDebugMode` (`nestjs-standards` 4.7, `flutter-standards` 08 "Logging interceptor"). Verify: read the production log level from validated config and its schema default; `grep -n "kDebugMode" lib/core/network/*.dart`.

## Error responses

- [ ] SEC-LOG-07 An unexpected failure returns a generic 500 with only `code`, `message`, and `requestId`: no stack trace, Drizzle or driver error, SQL, or table name (`nestjs-standards` 4.6 and 09). Verify: an e2e test that forces a database error (for example a closed connection in the testing module) and asserts the body has exactly those three keys and no driver text; the same test asserts the full error reached the log with the same `requestId`.
- [ ] SEC-LOG-08 The `requestId` reaches the user on every client, so a user can quote it to support, and the client never shows an exception's own text (`react-standards` 4.6 and `SEC-WEB-20`; Flutter: kit rule, because `AppException` in `flutter-standards` 08 has no `requestId` field yet). Verify: React, the `SEC-WEB-20` test; Flutter, a widget test of the error state that renders the id from a mocked 500, or a recorded gap in the contract until the standard adds the field.

## Accounting

- [ ] SEC-LOG-09 Business events (a status change, a payment, a role change, an export) are logged with the actor id, the action, the target id, and the `requestId`, never with the payload (`nestjs-standards` 4.7 DEFAULT "Log business events"). Verify: for each state-changing use case in the contract, find the log call and read its fields; a unit test asserts the event's field set.
- [ ] SEC-LOG-10 Privileged mutations (role, money, permissions, approvals) leave an audit trail that the acting user cannot edit or delete through the API (`nestjs-standards` 10-production-readiness "Audit trail on privileged mutations"; kit rule for the write protection). Verify: an e2e test performs one privileged mutation and asserts the audit row with actor and `requestId`; trace that no route updates or deletes audit rows.

## Secrets in config

- [ ] SEC-LOG-11 `.env.example` lists every key the app reads, with no real values, and each secret's name says it is one (`_SECRET`, `_KEY`, `_TOKEN`, `_PASSWORD`) so a reader and a log filter can tell (`devops-engineering` Config and secrets, `nestjs-standards` 09; naming is a kit rule). Verify: compare the keys in the config schema with `.env.example`; `grep -nE "=.+" .env.example` shows only placeholders.
- [ ] SEC-LOG-12 Config is validated at boot, and a validation failure or a startup log names the bad key, never its value (`devops-engineering` Config and secrets; kit rule for the message). Verify: a test boots the config schema with a malformed secret and asserts the error text contains the key name and not the value.
- [ ] SEC-LOG-13 No secret is in the repo, an image, or a public client env prefix, and the secret scan runs on every pull request (`devops-engineering` CI, `react-standards` 10, `nestjs-standards` 09). Verify: the secret scan job is present and required; `git ls-files | grep -E "(^|/)\.env($|\.)" | grep -v example` returns nothing. Image and bundle checks are `SEC-SUP-14` and `SEC-WEB-17`.

## Sources

- OWASP Logging Cheat Sheet, living document, read 2026-11-08. https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
- OWASP Secrets Management Cheat Sheet, living document, read 2026-11-08. https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
- OWASP Error Handling Cheat Sheet, living document, read 2026-11-08. https://cheatsheetseries.owasp.org/cheatsheets/Error_Handling_Cheat_Sheet.html
- Kit standards: `nestjs-standards` 05, 09, and [10-production-readiness.md](../../nestjs-standards/references/10-production-readiness.md); `react-standards` 05 and 10; `flutter-standards` 08; `devops-engineering`; linked in the scope paragraph.
