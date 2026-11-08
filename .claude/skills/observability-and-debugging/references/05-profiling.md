# Profiling and alerts

Scope: how to measure slowness on each stack before changing anything, which tool answers which question, and how alerts are framed. The rules are owned by [`react-standards` 09](../../react-standards/references/09-performance.md) (a measurement before an optimization; Core Web Vitals from real users), [`flutter-standards` 16](../../flutter-standards/references/16-production-and-release.md) 11.4 (budgets measured in profile mode on the low-end reference device, `traceAction` summaries compared release over release), [`nestjs-standards` 05, 4.4](../../nestjs-standards/references/05-rules.md) (`EXPLAIN ANALYZE` on the slowest list endpoints), and `devops-engineering` [SKILL.md](../../devops-engineering/SKILL.md) "Observability" (alerts on symptoms users feel, each with an owner and a runbook). Query plans are `database-drizzle` [02-indexes-and-queries.md](../../database-drizzle/references/02-indexes-and-queries.md). This file adds the tool notes and the shared method.

## The method

1. **Name the budget and the number.** Which budget is missed (the project's, or the defaults in flutter 16 11.4 and the Core Web Vitals below), by how much, at which percentile, on which device or data size.
2. **Reproduce it under fixed conditions**: the same build mode, device or throttling, data size, and warm or cold start, written down so the next run matches.
3. **Profile once to find the biggest contributor.** Do not fix anything yet.
4. **Change one thing.**
5. **Measure again under the same conditions**, and report before and after with the conditions. If the number did not move, revert the change, even if it "should" help (react 09: "This felt slow so I added `memo`" is not a reason).

A performance claim without both numbers is not a finding. A lab number from a developer machine is not evidence of what users see (react 09, Core Web Vitals "from real users, not only from the lab").

## Flutter

From the Flutter DevTools performance docs:

- Profile in **profile mode**. Frame times in debug mode are not indicative of release performance.
- A frame is janky when it takes more than about 16 ms on a 60 FPS device. The frame chart splits each frame into UI thread work (your Dart code building the layer tree) and raster thread work (the engine drawing it). A slow UI bar points at build, layout, or Dart work; a slow raster bar points at what is drawn, even when the Dart code is cheap.
- Profile on a real device; flutter 16 11.4 sets the low-end reference device as the place budgets are measured.

Budgets in CI: flutter 16 11.4 measures startup and scrolling with `integration_test` and `traceAction` timeline summaries, compared release over release. The `FlutterDriver.traceAction` API docs describe it as running an action and returning a performance trace for it; the integration test binding has its own `traceAction`, whose page was not read for this file. Memory: a DevTools memory snapshot on the longest list (11.4).

## Web: browser and React

- **Chrome DevTools Performance panel**: record the interaction, with CPU and network throttling set while recording. Throttling is relative to the machine's own speed, and the panel can calibrate a CPU preset to match low- and mid-tier mobile devices (Chrome DevTools performance reference). Record the throttling used next to the result.
- **React Profiler**: the `<Profiler id onRender>` component reports `actualDuration` (time rendering the subtree for this update) and `baseDuration` (an estimate of re-rendering the whole subtree without memoization). Comparing them shows whether memoization is working. Profiling adds overhead and is disabled in the production build by default; a special profiling build opts in (react.dev, `<Profiler>`). The React DevTools Profiler is the interactive equivalent; react 09 names it as a measurement tool.
- **Core Web Vitals**, from web.dev: LCP within 2.5 s, INP of 200 ms or less, CLS of 0.1 or less, each assessed at the 75th percentile of page loads, segmented by mobile and desktop. A page passes when all three meet the target at the 75th percentile. INP replaced FID as a stable Core Web Vital in 2024.
- Before reaching for `memo`, check the causes react 09 lists first: state too high in the tree, an overloaded context, unstable identities passed to memoized children, unkeyed lists, or rendering thousands of rows.

## Node.js (NestJS)

From the Node.js v26 command-line docs and diagnostics guide:

- **CPU**: `node --cpu-prof dist/main.js` starts the V8 CPU profiler at startup and writes a `.cpuprofile` file before exit, in the current directory unless `--cpu-prof-dir` is set. The sampling interval defaults to 1000 microseconds (`--cpu-prof-interval`). The flags are stable since v22.4.0 and v20.16.0. Profile a local build under a load that reproduces the slow path, and stop the process cleanly so the file is written.
- **Memory**: a heap snapshot through the inspector (`--inspect`, Memory tab), `--heapsnapshot-signal=SIGUSR2`, or `v8.writeHeapSnapshot()`. The guide warns that taking a snapshot stops all other work on the main thread, can take more than a minute, and can double the heap size and crash the process. So snapshots are taken locally; one against a shared or live process is a step Dave decides and runs (AGENTS.md rule 10).
- **Event loop blocking**: a CPU profile of a slow request that shows a long synchronous stack (parsing a large payload, a synchronous crypto or compression call) is the usual finding. The fix is the standard's to choose (`nestjs-standards` 05, 4.9 for moving work to a queue).

## The database

A slow endpoint is often a query. Get the query from the server's log for the slow request id, then follow `database-drizzle` `02-indexes-and-queries.md` for `EXPLAIN ANALYZE` and the index review. An agent writes the statement and Dave runs it, as that file says.

## Alerts

`devops-engineering` Observability: alert on symptoms users feel (error rate, latency, failed sign-ins, queue depth, dead letters), each alert with an owner and a runbook.

From the Google SRE book, "Monitoring Distributed Systems":

- **The four golden signals** are latency, traffic, errors, and saturation; if you can only measure four metrics of a user-facing system, measure these.
- **Latency**: track the latency of failed requests separately from successful ones; a fast 500 mixed into the average hides the problem, and a slow error is worse than a fast one.
- **Errors** include explicit failures (500s), implicit ones (a 200 with the wrong content), and failures by policy (a request slower than the committed time).
- **Saturation**: how full the service is, on its most constrained resource. Latency increases are often a leading indicator of it.
- **Symptoms versus causes**: "what is broken" is the symptom, "why" is the cause. Page a person on symptoms.
- **Tails**: a mean hides a slow tail. Collect latency in buckets (a histogram) so the distribution is visible, rather than only an average.

Thresholds and paging rules are the project's, recorded in `docs/ops.md`, never invented by an agent. An alert config an agent writes names its owner and links a runbook made from `devops-engineering` `assets/runbook-template.md`.

## Sources

- Flutter documentation, "Use the Performance view" (DevTools), Flutter 3.47 docs, read 2026-11-08. https://docs.flutter.dev/tools/devtools/performance
- Flutter API docs, `FlutterDriver.traceAction`, read 2026-11-08. https://api.flutter.dev/flutter/flutter_driver/FlutterDriver/traceAction.html
- Flutter API docs, `IntegrationTestWidgetsFlutterBinding.traceAction`, not read in this session (the page did not load). https://api.flutter.dev/flutter/integration_test/IntegrationTestWidgetsFlutterBinding/traceAction.html
- Chrome DevTools documentation, "Performance features reference" (throttling while recording), read 2026-11-08. https://developer.chrome.com/docs/devtools/performance/reference
- React documentation, "`<Profiler>`", react.dev, read 2026-11-08. https://react.dev/reference/react/Profiler
- web.dev, "Web Vitals", read 2026-11-08. https://web.dev/articles/vitals
- Node.js documentation, "Command-line API" (`--cpu-prof`, `--cpu-prof-dir`, `--cpu-prof-interval`, `--heapsnapshot-signal`), Node.js v26.13.0, read 2026-11-08. https://nodejs.org/api/cli.html
- Node.js Learn, "Using Heap Snapshot" (diagnostics, memory), read 2026-11-08. https://nodejs.org/en/learn/diagnostics/memory/using-heap-snapshot
- Google, *Site Reliability Engineering*, chapter 6 "Monitoring Distributed Systems" (online edition), read 2026-11-08. https://sre.google/sre-book/monitoring-distributed-systems/
- PostgreSQL `EXPLAIN` documentation: cited through `database-drizzle` `02-indexes-and-queries.md`, which lists the edition read.
- Kit standards: `react-standards` 09; `flutter-standards` 16; `nestjs-standards` 05 (4.4, 4.9); `devops-engineering` SKILL.md and `assets/runbook-template.md`; `database-drizzle` `02-indexes-and-queries.md`.
