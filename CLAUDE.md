@AGENTS.md

## Claude Code

- The session runs as `captain-america`, who routes to `iron-man`, `thor`, `hulk`, `hawkeye`, `black-widow`, and `nick-fury`.
- Stack detail lives in the `flutter-standards`, `react-standards`, and `nestjs-standards` skills. Load the one you are working in.
- Work is agentic (Claude Code) or manual (Dave). Manual changes are reviewed against the same contract, boundary, and stack rules.
- Fixed stack: Drizzle and Zod (`docs/adr/012-backend-drizzle-and-zod-validation.md`). Repo convention never overrides them; flag a differing repo for migration.
- Flutter state defaults to Riverpod. Another library needs a stated need that Dave approves (`docs/adr/011-flutter-state-riverpod-default.md`).
- Hooks enforce the contract gate. If one blocks you, follow its message. Do not route around it through Bash.
- No em dashes in docs, comments, or commit messages.
- Commit or push only when asked.
