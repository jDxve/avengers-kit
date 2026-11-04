# My Flutter Way

**Flutter Production Playbook**

Feature-first over the official Flutter architecture. Typed networking. Riverpod notifiers. `Result<T>` in data, `DataState<T>` in UI. Session safety. Testing. CI-enforced boundaries.

My conventions for building production-grade Flutter apps.

- Flutter, Dart 3.x
- State: Riverpod 3
- Architecture: feature-first and layered
- Lints: native analyzer plugins
- Playbook version: 2.2.0-rc.1

**Author**: JOHN DAVE BAÑAS

---

This is how I structure and write Flutter apps: not just the architecture, but the
conventions, error handling, session lifecycle, tests, and lints that keep it honest. Follow it
when scaffolding a new app, adding a feature, or reviewing code.

It is deliberately built **on top of the official Flutter architecture guidance**, not as an
alternative to it. Section 0 maps every piece of this document onto the Flutter team's
vocabulary and states the two places I diverge, with reasons. Everything else is an
implementation of that guidance with a specific stack.

> **Status of this document.** Version `2.2.0-rc.1`. A version loses its `-rc` suffix only when
> the reference application (§12.4) passes its CI pipeline (§11.2) on GitHub at the pinned
> versions (§12.3), including the Android emulator and iOS simulator jobs. This version has been
> executed against the reference app from a clean clone: static analysis, both analyzer plugins,
> the lint fixture, 98 tests, the coverage floors, all 29 sabotages, the feature template, the
> release-config check, the OSV scan, and prod and dev Android builds. §12.6 records what ran,
> on what, and what has not run yet.

> **Status of the code samples.** Snippets are extracts from the reference implementation, with
> imports omitted. Where a block shows a whole file it is that file, byte for byte; a
> `/* ... */` or a trailing comment marks an elision. Configuration blocks
> (YAML, Gradle, manifest, workflow) and the scripts under `tool/` are given in full, because
> half a config is worse than none. Anything illustrative rather than real is labelled
> **conceptual** inline.

