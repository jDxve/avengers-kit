## 9. Naming and File Conventions

**Files and folders:** `snake_case.dart`, `snake_case/` directories. One primary class per file;
the filename matches its subject (`auth_repository_impl.dart` holds `AuthRepositoryImpl`).

**Layer suffixes:**

| Thing | File | Type |
| --- | --- | --- |
| Service | `<feature>_service.dart` | `<Feature>ApiService` (Retrofit abstract class) |
| DTO | `<thing>_dto.dart` | `<Thing>RequestDto` / `<Thing>ResponseDto` |
| Local source | `<thing>_local_source.dart` | `<Thing>LocalSource` |
| Domain model | `<thing>.dart` | `<Thing>` (no suffix) |
| Repository contract | `<feature>_repository.dart` | `abstract interface class <Feature>Repository` |
| Repository impl | `<feature>_repository_impl.dart` | `<Feature>RepositoryImpl` |
| Feature root | `features/<feature>/<feature>.dart` | `<feature>RepositoryProvider` + exports (ADR-009) |
| Notifier | `<thing>_notifier.dart` | `<Thing>Notifier` + `<thing>NotifierProvider` |
| Screen | `<name>_screen.dart` | `<Name>Screen` with `static const String routeName` |
| Test | mirrors the file under test, `_test.dart` | `test/features/auth/data/auth_repository_impl_test.dart` |
| ADR | `docs/adr/NNN-<slug>.md` | `ADR-NNN` in prose and in suppression comments |
| Suppression | `// ignore: app_lints/<rule>` | the line above cites the ADR (§12.2) |

**Providers:** `camelCase` ending in `Provider`. One provider declared next to the thing it
exposes, except repository providers, which live in the feature's root file so they can see
`data/` while presentation cannot.

**Constants:** global constants prefixed `k` (`kSession`, `kSkipAuth`). Private file-level
constants start with `_k`.

**Strings, colors, dimensions:** never inline. Copy via `Strings.x`, colors via
`context.xColor`, sizes via `Dimensions.pxNN`.

**Imports** (ordered, blank line between groups):

1. Dart SDK (`dart:async`)
2. Flutter and third-party packages
3. Local `package:` imports

Always `package:` imports inside `lib/`, never `../../` relatives. Absolute paths make the layer
a file lives in obvious from its import line and survive file moves. Enforced, not preferred.

**Style:** `const` constructors wherever possible; `required` named parameters; immutable state
with manual `copyWith`; expression bodies for one-liners; comments that explain **why**, not
what. Prefer Dart 3 pattern matching over `is` checks and casts when consuming `Result` or
`DataState`.

---

