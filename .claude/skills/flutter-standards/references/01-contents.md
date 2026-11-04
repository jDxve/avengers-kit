## Contents

| | |
| --- | --- |
| [Quick start](#quick-start) | Adopt it in a new app, add a feature, review a PR |
| [Rule index](#rule-index) | Every rule on one page: mandatory, conditional, or optional, and what enforces it |
| [0. Relationship to the Official Flutter Architecture](#0-relationship-to-the-official-flutter-architecture) | The mapping onto the official guidance, and the two deviations |
| [1. Architecture Philosophy](#1-architecture-philosophy) | Why feature-first, and what the boundaries buy |
| [2. Folder Structure](#2-folder-structure) | Where every file goes, at two scales |
| [3. Core Layer](#3-core-layer) | Config, `Result` vs `DataState`, errors, the session, the auth interceptor |
| [4. Common Layer](#4-common-layer) | Shared resources, error copy, global error hooks, wiring |
| [5. Feature Anatomy](#5-feature-anatomy-worked-example-auth) | One vertical slice end to end |
| [6. State Management with Riverpod](#6-state-management-with-riverpod) | Provider graph, notifier conventions, lifecycle |
| [7. Testing](#7-testing) | The test matrix, coverage policy, and the tests that pin the invariants |
| [8. Tooling and Enforcement](#8-tooling-and-enforcement) | What a machine checks so review does not have to |
| [9. Naming and File Conventions](#9-naming-and-file-conventions) | File, class, and provider naming |
| [10. New Feature Checklist](#10-new-feature-checklist) | The order to build a slice in, and the rules that never bend |
| [11. Production and Release](#11-production-and-release) | Flavors, CI, hardening, readiness gates, rollout and incidents |
| [12. Governance](#12-governance) | ADRs, exceptions, dependency policy, reference app, versioning, verification record |

**Reading order.** New to the document: Quick start, the Rule index, then §1 and §5. Implementing
it: §3 (core), §10 (checklist), §8 (lints), §11.2 (CI). Reviewing a PR: the Rule index. Changing
the playbook itself: §12.

---

