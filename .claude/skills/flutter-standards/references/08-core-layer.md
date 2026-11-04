## 3. Core Layer

### Config (`core/config/app_config.dart`)

Values come from the build via `--dart-define-from-file` (§11.1). The same compiled code runs in
every environment and nothing sensitive is committed. Validation **throws in every build mode**,
release included: a release build is exactly where a wrong base URL costs the most, and an
`assert` would be stripped from it.

```dart
enum AppEnv { dev, staging, prod }

const String _devBaseUrl = 'http://192.168.1.100:4000/api/v1'; // local only, dev only

final class AppConfig {
  const AppConfig({required this.env, required this.baseUrl});

  final AppEnv env;
  final Uri baseUrl;

  /// Reads the build's defines and refuses to start on a bad combination.
  factory AppConfig.fromEnvironment() => AppConfig.parse(
    envName: const String.fromEnvironment('APP_ENV'),
    rawUrl: const String.fromEnvironment('BASE_URL'),
  );

  /// The validation itself, separated so tests can exercise every branch.
  factory AppConfig.parse({
    required String envName,
    required String rawUrl,
    bool debug = kDebugMode,
  }) {
    final env = switch (envName) {
      'dev' => AppEnv.dev,
      'staging' => AppEnv.staging,
      'prod' => AppEnv.prod,
      '' when debug => AppEnv.dev, // a bare `flutter run` while developing
      _ => throw StateError('APP_ENV must be dev, staging or prod; got "$envName".'),
    };

    final url = Uri.tryParse(rawUrl.isEmpty && env == AppEnv.dev ? _devBaseUrl : rawUrl);
    if (url == null || !url.hasAuthority) {
      throw StateError(
        'BASE_URL is missing or not absolute for $env. '
        'Pass it with --dart-define-from-file=config/${env.name}.json.',
      );
    }
    if (env != AppEnv.dev && url.scheme != 'https') {
      throw StateError('$env requires an https BASE_URL; got "$url".');
    }
    return AppConfig(env: env, baseUrl: url);
  }
}

const Duration kConnectTimeout = Duration(seconds: 10);
const Duration kSendTimeout = Duration(seconds: 30);
const Duration kReceiveTimeout = Duration(seconds: 30);
```

Two failure modes the 1.x version allowed and this one does not:

- **A prod build with no `BASE_URL` shipped pointing at a LAN address.** The old `defaultValue`
  was the dev URL and the guard was an `assert`, so a release build with a missing define
  compiled, passed the stripped assert, and talked to `192.168.1.100`. The dev URL is now used
  only when the environment is dev.
- **A typo in `APP_ENV` silently meant dev.** `'production'` fell through to the dev branch.
  An unknown name now throws.

`AppConfig.parse` holds the validation so a test can drive every branch with an explicit
`debug` flag; `fromEnvironment` only reads the defines. The runtime throw is the backstop. The
primary guard runs before a build exists:
`tool/check_release_config.dart` in CI (§11.2) rejects a staging or prod config file that would
fail here.

### Crash reporter (`core/reporting/reporter.dart`)

`reporter` appears throughout this document. It is a thin facade over Crashlytics or Sentry, so
that swapping vendors touches one file and so tests can substitute a no-op.

```dart
abstract interface class Reporter {
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    List<Object> information = const [],
  });
  void recordFlutterError(FlutterErrorDetails details);
}

final class NoopReporter implements Reporter {
  const NoopReporter();
  @override
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    List<Object> information = const [],
  }) {}
  @override
  void recordFlutterError(FlutterErrorDetails details) {}
}

/// Set once in main(), before the error hooks. Defaults to a no-op so tests and the
/// dev loop never need a real vendor SDK.
Reporter reporter = const NoopReporter();
```

A top-level mutable rather than a provider on purpose: `FlutterError.onError` and
`PlatformDispatcher.onError` are installed before any `ProviderScope` exists, so the reporter
has to be reachable without a `Ref`. It is the only global in this document, and it is
write-once at boot.

**What the reporter may receive.** No tokens, no headers, no request or response bodies, no
query strings. Network failures are reduced to a `NetworkFailure` value before they reach it
(see the reporting interceptor). Configure the vendor SDK's scrubbing hook (`beforeSend` in
Sentry, custom keys discipline in Crashlytics) as a second line, because a `FormatException`
can carry a fragment of the payload it failed to parse.

### Result (`core/result/result.dart`)

The data-layer outcome type. A finished call either produced a value or it failed. Two cases,
no more. Repositories return `Future<Result<T>>`; nothing below the repository knows what a
loading spinner is.

```dart
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.exception);
  final AppException exception;
}
```

Hand-written, not freezed: it is ten lines and Dart 3 sealed classes already give exhaustive
`switch`. `exception` is non-nullable, so no consumer ever writes `exception!`.

```dart
// Consumption is always an exhaustive switch. No casts, no null checks.
final message = switch (result) {
  Ok(:final value) => 'Loaded ${value.length} items',
  Err(:final exception) => errorToMessage(exception),
};
```

### AppException (`core/result/app_exception.dart`)

The error type carried by `Err`. **Genuinely plain Dart**: this file imports nothing but
`dart:core`. It does not know Dio exists.

```dart
enum ErrorType {
  timeout, // the request took too long
  connection, // no route to the server
  cancelled, // the caller or the session abandoned the request; never shown to the user
  unauthorized, // the session is over: refresh was rejected
  forbidden, // signed in, not allowed (403)
  rejected, // the server refused this input: 400, 409, 422, or 401 on an unauthenticated endpoint
  retryable, // transient and safe to retry: token refreshed but not replayed, or 429
  server, // 5xx
  unknown,
}

class AppException implements Exception {
  const AppException({
    this.statusCode,
    this.message,
    this.type = ErrorType.unknown,
    this.cause,
    this.stackTrace,
  });

  final int? statusCode;
  final ErrorType type;

  /// Server-supplied copy that is safe to show a user, and nothing else. Populated only
  /// for ErrorType.rejected. Never a Dart error string, never an exception's toString().
  final String? message;

  /// Diagnostics only. Goes to the crash reporter and the logs; never to the UI.
  final Object? cause;
  final StackTrace? stackTrace;

  /// Non-transport failures (JSON shape changed, mapping threw, cache corrupt).
  /// `message` stays null on purpose: there is no user-safe sentence to put in it.
  factory AppException.unexpected(Object error, [StackTrace? stack]) =>
      AppException(type: ErrorType.unknown, cause: error, stackTrace: stack);

  @override
  String toString() => 'AppException($type, status: $statusCode, message: $message, cause: $cause)';
}
```

**The invariant that keeps internals off the screen.** `message` holds only text a server
wrote for a user, and only the mapper writes it, and only for `rejected`. Everything a Dart
runtime produced, a `TypeError` from a changed JSON shape, a `FormatException` from a corrupt
cache, goes in `cause`, which no UI path reads. Putting `error.toString()` into `message` is how
an app ends up showing someone `type 'Null' is not a subtype of type 'String' in type cast`
in a toast. The split makes the rule checkable: a reviewer only has to ask whether anything
other than `mapDioException` assigns `message`.

**429 is `retryable`.** A rate limit is transient and the user's next tap may succeed; rc.1 fell
through to `unknown`. **Why `ErrorType` grew from five cases to nine.** In 1.x a wrong password (401 from
`/auth/login`), a permission failure (403), and a refresh that succeeded but could not replay an
upload all rendered as "Your session has expired. Please log in again." Each was a different
truth told with the same sentence. The enum now has one case per thing the user should be told,
and `errorToMessage` (§4) switches on it exhaustively, so a tenth case is a compile error at the
one place copy is chosen.

### Request flags (`core/network/request_flags.dart`)

```dart
/// RequestOptions.extra key. True on endpoints that authenticate by their body
/// (login, register, refresh, revoke, password reset): no bearer is attached, and a
/// 401 is a verdict on the input, not on the session.
const String kSkipAuth = 'skipAuth';

/// Sent on non-idempotent writes that must survive a token refresh (§3 replay policy).
const String kIdempotencyKeyHeader = 'Idempotency-Key';
```

Retrofit applies them declaratively: `@Extra({kSkipAuth: true})` on a method, and
`@Header(kIdempotencyKeyHeader) String key` as a parameter. See §5.

### Dio error mapper (`core/network/dio_error_mapper.dart`)

The one place a Dio type becomes an `AppException`. In `core/network/`, not `core/result/`,
because knowing about Dio is a network-layer job. Swap the HTTP client and you replace this
file and nothing else.

```dart
AppException mapDioException(DioException e) {
  final status = e.response?.statusCode;
  final skipAuth = e.requestOptions.extra[kSkipAuth] == true;

  final type = e.error is ReplayRefused
      ? ErrorType.retryable
      : switch (e.type) {
          DioExceptionType.cancel => ErrorType.cancelled,
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout => ErrorType.timeout,
          DioExceptionType.connectionError => ErrorType.connection,
          _ => switch (status) {
            401 when skipAuth => ErrorType.rejected, // wrong password: about the input
            401 => ErrorType.unauthorized,
            403 => ErrorType.forbidden,
            429 => ErrorType.retryable,
            400 || 409 || 422 => ErrorType.rejected,
            final int s when s >= 500 => ErrorType.server,
            _ => ErrorType.unknown,
          },
        };

  return AppException(
    statusCode: status,
    type: type,
    // Only a rejection carries server copy; every other type gets generic copy in the UI.
    message: type == ErrorType.rejected ? _extractServerMessage(e.response?.data) : null,
    cause: e,
    stackTrace: e.stackTrace,
  );
}

/// Longest server sentence the UI will show. Anything longer is not a sentence for a user.
const int kMaxServerMessage = 160;

/// Pulls the server's own message out of a JSON error envelope, if there is one.
/// It is untrusted input on its way to the screen: one line of plain text, bounded, or nothing.
String? _extractServerMessage(Object? data) {
  final raw = switch (data) {
    {'message': final String m} => m,
    {'error': {'message': final String m}} => m,
    _ => null,
  };
  if (raw == null) return null;
  final text = raw
      .replaceAll(RegExp(r'[\x00-\x1F\x7F\u2028\u2029\u202A-\u202E\u2066-\u2069]+'), ' ')
      .trim();
  if (text.isEmpty || text.length > kMaxServerMessage) return null;
  return text;
}
```

**Server copy is untrusted input.** It reaches the screen, so it is constrained on the way in:
control characters, line and paragraph separators, and bidirectional overrides become spaces
(a `U+202E` can make a sentence read backwards); an empty or over-long message is dropped, and
the user sees the generic `rejected` copy instead. Flutter's `Text` renders no markup, so this is
about spoofing and layout, not injection. When the backend can send stable error codes, map
those to local `Strings` and treat the free-text message as the fallback: a compromised or
careless backend can still write a misleading sentence that passes every check here.

### Repository guard (`core/network/repository_guard.dart`)

A mixin that collapses the repetitive try/catch in every repository method. It catches
`DioException` **and** everything else, because a DTO whose JSON shape changed throws a
`TypeError`, not a `DioException`, and an uncaught one of those escapes into the notifier as
a raw crash.

```dart
mixin RepositoryGuard {
  Future<Result<T>> guard<T>(
    Future<T> Function() request, {
    Result<T> Function(DioException error)? onDioError,
  }) async {
    try {
      return Ok(await request());
    } on DioException catch (e) {
      return onDioError?.call(e) ?? mapError<T>(e);
    } catch (e, stack) {
      // Mapping/parsing failures are bugs, not user errors: report, then degrade.
      reporter.recordError(e, stack, fatal: false);
      return Err(AppException.unexpected(e, stack));
    }
  }

  Result<T> mapError<T>(DioException error) => Err(mapDioException(error));
}
```

The guard sits in `core/network/` for the same reason the mapper does: it catches
`DioException`, so it is transport-aware by definition. `core/result/` stays free of Dio, which
is what lets the domain layer depend on it.

`onDioError` handles status codes that are not really failures, such as a 404 meaning "no data
yet" (illustrative; the reference app's profile repository in §5 does exactly this):

```dart
@override
Future<Result<Household?>> fetchMyHousehold() => guard(
      () async => (await _apiService.getMyHousehold())?.toDomain(),
      onDioError: (e) =>
          e.response?.statusCode == 404 ? const Ok(null) : mapError(e),
    );
```

### DataState (`core/state/data_state.dart`)

The **UI state** type. Owned by notifiers, never returned by a repository. Four cases,
because a screen genuinely has four: nothing requested yet, in flight, loaded, failed.

```dart
sealed class DataState<T> {
  const DataState();

  /// The one conversion point between the data layer and the UI layer.
  /// A cancelled request returns the screen to idle: nothing failed that the user should hear about.
  static DataState<T> from<T>(Result<T> result) => switch (result) {
    Ok(:final value) => DataSuccess<T>(data: value),
    Err(exception: AppException(type: ErrorType.cancelled)) => DataIdle<T>(),
    Err(:final exception) => DataError<T>(exception: exception),
  };
}

final class DataIdle<T> extends DataState<T> {
  const DataIdle();
}

final class DataLoading<T> extends DataState<T> {
  const DataLoading();
}

final class DataSuccess<T> extends DataState<T> {
  const DataSuccess({required this.data});
  final T data;
}

final class DataError<T> extends DataState<T> {
  const DataError({required this.exception});
  final AppException exception;
}

extension DataStateX<T> on DataState<T> {
  bool get isLoading => this is DataLoading<T>;
  T? get valueOrNull => switch (this) {
    DataSuccess(:final data) => data,
    _ => null,
  };
}
```

**Hand-written, for the reason `Result` is.** Dart 3 sealed classes already give exhaustive
`switch`, and that exhaustiveness is the only property anything here relies on. Through rc.3
this type was `@freezed`, which meant `build_runner`, a generated file to commit, and a
regeneration step on every clone, to produce four cases and two getters. Nothing consumes
`DataState` through a generated `copyWith`, `==` or `toString`: notifiers replace the state,
they never copy it. Writing it by hand removes codegen from any app that does not otherwise
need it.

`exception` is `required`, so `DataError` always carries one. `from` is a static on the class
itself (rc.1 put it on an extension, where its `<T>` shadowed the extension's). Every
constructor call inside it names its type argument: a bare `const DataIdle()` would infer
`DataIdle<Never>`, which passes `is DataIdle<T>` checks by covariance and hides the mistake.

**The rule, stated precisely.** Repositories return `Result<T>`. Notifiers hold
`DataState<T>` (or a composite state class containing `DataState<T>` fields) and are the only
place `idle` and `loading` are produced. Local reads, fire-and-forget operations, and anything
whose failure the UI does not surface may return a plain `Future<T>` or `Future<void>`. Not
every async call needs a result wrapper; every *networked operation whose outcome the user
sees* does.

### The session (`core/session/`)

Credentials are the highest-stakes data in the app, so they get one owner. **`SessionStore` is
the only code that reads or writes session keys.** Repositories, interceptors, and notifiers go
through it; nothing else holds a `FlutterSecureStorage` reference except the first-install wipe.
Four properties fall out of that:

1. **The session is one value under one key.** Access and refresh token are written together as
   one JSON string, so a crash during a rotation cannot leave a new access token beside an
   already-consumed refresh token. rc.1 wrote two keys; a process death between the writes meant
   the next cold start signed in, presented a dead refresh token, and logged the user out.
2. **The token lives in memory for the process.** The interceptor reads it on every request
   from a field, not from the keystore. A keystore read is a platform-channel round trip and,
   on some Android devices, slow enough to show up in request latency.
3. **Ending a session cannot fail.** Memory is cleared first and synchronously. Whatever the
   keystore does afterwards, the session is over the moment `clear()` is called.
4. **Recovery is scoped, and it is ours.** On a storage failure the store deletes the session
   keys it owns, one at a time, and nothing else. It never calls `deleteAll()`, and the plugin is
   not allowed to erase on its behalf (below).

**Secure storage holds session credentials and nothing else.** Anything that must survive a
sign-out (onboarding flags, theme, cached profile) belongs in `shared_preferences`. This makes
"clear the session" and "clear what is in secure storage" the same operation, which is what
keeps recovery narrow.

#### Platform options (`core/session/secure_storage.dart`)

```dart
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(
      // The plugin default (true) deletes a key it cannot decrypt and reports it as absent.
      // SessionStore owns recovery and must see the failure, so the plugin may not erase.
      resetOnError: false,
      migrateWithBackup: true,
    ),
    // Readable after first unlock, and bound to THIS device. Plain `first_unlock`
    // items are included in encrypted backups and can restore onto a new phone.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
});
```

> **`resetOnError: false` is load-bearing.** In v11 the Android default is `true`: when the
> plugin cannot decrypt a key it deletes that key and reports it as absent. `SessionStore` then
> sees `SessionMissing` instead of `SessionUnreadable`, so the contract row "read throws:
> nothing deleted" was silently false on Android in rc.1. A test in the reference app pins
> the option (`secure_storage_test.dart`).
>
> **Version note.** `flutter_secure_storage` changed its Android backend in v10 and removed
> `encryptedSharedPreferences` in v11. Do not pass that parameter. Pin the major version, and
> re-check this block, the backup rules below, and the `SessionStore` tests whenever it moves
> (§12.3). `migrateWithBackup: true` makes the v9-to-v10 cipher migration crash-resistant and
> can be dropped once your install base has migrated.

**Android: keep the secure store out of backup and device transfer.** A restored or transferred
blob lands on a device whose Keystore cannot unwrap it, producing
`InvalidKeyException: Failed to unwrap key`. For apps targeting Android 12 (API 31) and above,
`allowBackup="false"` stops cloud backup but **not** device-to-device transfer; that needs
`dataExtractionRules`.

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application
    android:allowBackup="false"
    android:dataExtractionRules="@xml/data_extraction_rules"
    ... >
```

```xml
<!-- android/app/src/main/res/xml/data_extraction_rules.xml -->
<?xml version="1.0" encoding="utf-8"?>
<!-- flutter_secure_storage 11 writes three SharedPreferences files: the encrypted data, the
     wrapped key that decrypts it, and its algorithm/config markers. A restored key file
     cannot be unwrapped by the new device's Keystore, so all three stay off backups and
     device transfers. Re-check these names whenever the plugin's major version moves. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="FlutterSecureStorage.xml" />
        <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
        <exclude domain="sharedpref" path="FlutterSecureStorageConfiguration.xml" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="sharedpref" path="FlutterSecureStorage.xml" />
        <exclude domain="sharedpref" path="FlutterSecureKeyStorage.xml" />
        <exclude domain="sharedpref" path="FlutterSecureStorageConfiguration.xml" />
    </device-transfer>
</data-extraction-rules>
```

rc.1 excluded only `FlutterSecureStorage.xml`. The wrapped AES key lives in
`FlutterSecureKeyStorage.xml`; restored onto a new device, it is exactly the blob the Keystore
cannot unwrap. The three names come from the plugin's Android source at the pinned version.
Both manifest attributes and all six exclusions are checked in CI by
`tool/check_release_config.dart`.

**iOS: the Keychain survives uninstall.** Keychain items are not deleted when the app is
removed, so a reinstall can silently resurrect a previous user's tokens. On the first launch
after install, detected via a `shared_preferences` flag (which *is* cleared on uninstall),
`launch_utils.dart` calls `deleteAll()` on secure storage before anything reads it. This is the
one sanctioned `deleteAll()`: it runs before any session exists, and secure storage holds only
session data by the rule above.

#### Storage keys (`core/session/storage_keys.dart`)

```dart
/// The whole session, access and refresh token together, as one JSON value.
/// One key means one write: a crash cannot leave a new access token beside a consumed
/// refresh token.
const String kSession = 'session';

/// The 1.x and 2.0.0-rc.1 layout. Read once to migrate, then deleted with the session.
const List<String> kLegacySessionKeys = ['access_token', 'refresh_token'];

/// Every key SessionStore owns. Recovery and sign-out delete exactly these.
const List<String> kSessionStorageKeys = [kSession, ...kLegacySessionKeys];
```

Per-user cache keys live in `shared_preferences` and are namespaced by user id
(`'cache_${userId}_profile'`) in `launch_utils.dart` or the owning local source.

#### SessionStore (`core/session/session_store.dart`)

```dart
final class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});

  /// Throws FormatException on anything that is not a complete session.
  factory SessionTokens.decode(String raw) => switch (jsonDecode(raw)) {
    {'a': final String a, 'r': final String r} => SessionTokens(accessToken: a, refreshToken: r),
    _ => throw const FormatException('stored session is incomplete'),
  };

  final String accessToken;
  final String refreshToken;

  String encode() => jsonEncode({'a': accessToken, 'r': refreshToken});
}

/// Cold-start outcome. "Never signed in" and "storage would not answer" are different
/// facts with different telemetry, even though both start the app signed out.
sealed class SessionLoad {
  const SessionLoad();
}

final class SessionFound extends SessionLoad {
  const SessionFound(this.tokens);
  final SessionTokens tokens;
}

final class SessionMissing extends SessionLoad {
  const SessionMissing();
}

final class SessionUnreadable extends SessionLoad {
  const SessionUnreadable(this.error);
  final Object error;
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.watch(secureStorageProvider)),
);

class SessionStore {
  SessionStore(this._storage);

  final FlutterSecureStorage _storage;
  SessionTokens? _tokens;
  bool _persisting = false; // false when "remember me" was off
  Future<void> _tail = Future.value();

  SessionTokens? get tokens => _tokens;
  String? get accessToken => _tokens?.accessToken;

  Future<SessionLoad> load() async {
    try {
      final raw = await _storage.read(key: kSession);
      final tokens = raw != null ? SessionTokens.decode(raw) : await _readLegacy();
      if (tokens == null) return const SessionMissing();
      _persisting = true;
      return SessionFound(_tokens = tokens);
    } catch (e, stack) {
      // Device still locked after a reboot (transient), a keystore migration, or a corrupt
      // blob. Report and start signed out. Do NOT delete: the first case recovers on its own,
      // and the next sign-in overwrites the key anyway.
      reporter.recordError(e, stack, fatal: false);
      return SessionUnreadable(e);
    }
  }

  /// Sign-in. Memory first, so the session works for this process even if the keystore does not.
  Future<void> save(SessionTokens tokens, {required bool persist}) {
    _tokens = tokens;
    _persisting = persist;
    return persist ? _serial(() => _persist(tokens)) : _serial(_deleteKeys);
  }

  /// Token rotation. Applies only if [from] is still the current session, so a refresh
  /// that finishes after a sign-out or an account switch cannot resurrect the old session.
  Future<bool> rotate({required SessionTokens from, required SessionTokens to}) async {
    if (!identical(_tokens, from)) return false;
    _tokens = to;
    if (_persisting) await _serial(() => _persist(to));
    return true;
  }

  /// Sign-out and expiry. The session is over when this is called; storage cleanup is
  /// best effort and never throws.
  Future<void> clear() {
    _tokens = null;
    _persisting = false;
    return _serial(_deleteKeys);
  }

  /// Storage operations run one at a time, in call order, so a rotation that is still
  /// writing can never land after the sign-out that followed it. The chain swallows and
  /// reports anything an operation lets escape: one failure must not skip every later op.
  Future<void> _serial(Future<void> Function() op) =>
      _tail = _tail.then((_) => op()).catchError((Object e, StackTrace stack) {
        reporter.recordError(e, stack, fatal: false);
      });

  /// Lets a test put an operation on the chain that escapes its own error handling.
  @visibleForTesting
  Future<void> debugEnqueue(Future<void> Function() op) => _serial(op);

  /// One-time migration from the two-key layout. Rewrites it as one key, then drops the old ones.
  Future<SessionTokens?> _readLegacy() async {
    final access = await _storage.read(key: kLegacySessionKeys[0]);
    final refresh = await _storage.read(key: kLegacySessionKeys[1]);
    if (access == null || refresh == null) return null;
    final tokens = SessionTokens(accessToken: access, refreshToken: refresh);
    await _serial(() async {
      await _persist(tokens);
      for (final key in kLegacySessionKeys) {
        await _deleteKey(key);
      }
    });
    return tokens;
  }

  Future<void> _persist(SessionTokens t) async {
    try {
      await _storage.write(key: kSession, value: t.encode());
    } catch (e, stack) {
      // A failing write usually means a key the keystore can no longer unwrap.
      // Recovery: delete our keys (and only ours), retry once.
      reporter.recordError(e, stack, fatal: false);
      await _deleteKeys();
      try {
        await _storage.write(key: kSession, value: t.encode());
      } catch (e, stack) {
        // Still failing. The session lives in memory for this process; next launch signs in again.
        reporter.recordError(e, stack, fatal: false);
      }
    }
  }

  Future<void> _deleteKeys() async {
    for (final key in kSessionStorageKeys) {
      await _deleteKey(key); // one failed delete must not skip the rest
    }
  }

  Future<void> _deleteKey(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, stack) {
      reporter.recordError(e, stack, fatal: false);
    }
  }
}
```

**What changed from 1.x and why.** The old `safeRead` called `deleteAll()` on any read
exception. On iOS with first-unlock accessibility, a background launch before the user has
unlocked the phone after a reboot throws on read; `deleteAll()` turned that transient state into
a forced sign-out. It also erased keys that were not session data, and if `deleteAll()` itself
threw, the "guard" crashed the launch it existed to protect.

**What changed in rc.2.** One key instead of two, with a one-time migration of the old pair.
And `_serial` cannot be poisoned: in rc.1 it was `_tail = _tail.then(op)`, safe only while
every operation caught its own errors. One future edit that let an error escape would have
turned the chain into an errored future, and every later storage call, sign-out's delete
included, would have been skipped silently for the life of the process.

The table below is the contract the `SessionStore` tests in §7 pin, one test per row:

| Situation | Outcome |
| --- | --- |
| No session keys | `SessionMissing`, signed out, nothing reported |
| Read throws | `SessionUnreadable`, signed out, reported, **nothing deleted** |
| Stored blob is corrupt | `SessionUnreadable`, left for the next sign-in to overwrite |
| Rotation | exactly one storage write |
| Write throws | session keys deleted (only ours), write retried once, session continues in memory |
| Keystore never answers on sign-out | the session is over at the call; memory does not wait for storage |
| Delete throws | remaining keys still deleted, reported, `clear()` completes |
| An operation escapes its own handling | later operations still run |
| Refresh finishes after sign-out | `rotate` returns false, old session not restored |
| Remember me off | tokens in memory only; rotations not persisted; stale keys deleted |
| A 1.x two-key session on disk | read once, rewritten as one key, old keys deleted |

`debugEnqueue` is the one test seam: it is the only way to put an operation that escapes its own
handling onto the chain, which is the case the chain's `catchError` exists for.

### HTTP clients (`core/network/http_client.dart`)

Every Dio in the app, including the refresh client and the replay client, is built by one
function from one adapter factory. Transport policy (timeouts, certificate pinning, proxy
rules) therefore cannot diverge between the client a request starts on and the client that
replays it. In 1.x the refresh and replay clients were bare `Dio()` instances: pinning added to
the main client would have been silently bypassed by the two requests that carry the most
sensitive tokens.

```dart
/// Overridden in main() with AppConfig.fromEnvironment(), and in tests with a fixture.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden in main()'),
);

/// The single transport seam. Certificate pinning goes here (IOHttpClientAdapter's
/// validateCertificate / createHttpClient). Flow tests override it with a scripted backend.
final httpAdapterFactoryProvider = Provider<HttpClientAdapter Function()>(
  (ref) => IOHttpClientAdapter.new,
);

Dio buildDio(AppConfig config, HttpClientAdapter adapter) => Dio(
  BaseOptions(
    baseUrl: config.baseUrl.toString(),
    headers: {'Accept': 'application/json'},
    connectTimeout: kConnectTimeout,
    sendTimeout: kSendTimeout,
    receiveTimeout: kReceiveTimeout,
  ),
)..httpClientAdapter = adapter;
```

### Token refresher (`core/network/token_refresher.dart`)

Calls `/auth/refresh` on an interceptor-free client (a 401 from the refresh endpoint must not
re-enter the auth interceptor) and **classifies** the outcome. The 1.x refresher returned
`null` for every failure, so a timeout on the refresh call logged the user out. The rule now:
**only a server verdict on the refresh token ends a session; a network failure never does.**

```dart
sealed class RefreshOutcome {
  const RefreshOutcome();
}

final class Refreshed extends RefreshOutcome {
  const Refreshed(this.accessToken);
  final String accessToken;
}

/// The server rejected the refresh token, or there is no session to refresh. Ends the session.
final class RefreshRejected extends RefreshOutcome {
  const RefreshRejected();
}

/// Offline, timed out, 5xx, 429, or a malformed response. The session stays; the caller sees why.
final class RefreshUnavailable extends RefreshOutcome {
  const RefreshUnavailable(this.error);
  final DioException error;
}

class TokenRefresher {
  TokenRefresher(this._client, this._session);

  final Dio _client; // built by buildDio, no interceptors
  final SessionStore _session;

  static const _verdicts = {400, 401, 403};

  Future<RefreshOutcome> call() async {
    final current = _session.tokens;
    if (current == null) return const RefreshRejected();
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': current.refreshToken},
        options: Options(extra: {kSkipAuth: true}),
      );
      final access = res.data?['accessToken'];
      if (access is! String) throw const FormatException('refresh response has no accessToken');
      final rotated = res.data?['refreshToken'];
      final next = SessionTokens(
        accessToken: access,
        refreshToken: rotated is String ? rotated : current.refreshToken,
      );
      if (!await _session.rotate(from: current, to: next)) return const RefreshRejected();
      return Refreshed(access);
    } on DioException catch (e) {
      return _verdicts.contains(e.response?.statusCode)
          ? const RefreshRejected()
          : RefreshUnavailable(e);
    } on FormatException catch (e, stack) {
      reporter.recordError(e, stack, fatal: false);
      return RefreshUnavailable(
        DioException(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          error: e,
          stackTrace: stack,
        ),
      );
    }
  }
}
```

### Auth interceptor (`core/network/auth_interceptor.dart`)

Attaches the bearer on every request that does not opt out with `kSkipAuth`. On a 401 it
refreshes **once per token generation**, replays the original request if the replay policy
allows it, and expires the session **only** on a server verdict. Six invariants, each pinned by
at least one test in §7.7, and each of those tests is proven able to fail by
`tool/check_sabotage.dart`:

| # | Invariant | Mechanism |
| --- | --- | --- |
| 1 | N concurrent 401s cause exactly one refresh | token **generation** counter |
| 2 | A rejected refresh is attempted once and tears down once | **expire-once** latch that also bumps the epoch, and no refresh once the session is over |
| 3 | A request from an old session is never refreshed for or replayed | session **epoch**, checked before and after the refresh |
| 4 | A network failure never logs the user out | `RefreshUnavailable` propagates the real error |
| 5 | A replay's own failure is what the caller sees | the replay's `DioException` is forwarded, not the original 401 |
| 6 | Nothing is sent twice unless it is safe to send twice | **replay policy**: idempotent method or `Idempotency-Key`, reusable body |

> **Why a generation counter, not "QueuedInterceptor serializes".** `QueuedInterceptor` does
> serialize `onError` callbacks: the second 401 is not processed until the first finishes. It
> does **not** stop the second one from refreshing again, because that request was dispatched
> with the stale token and the interceptor has no memory of what just happened. Serialization
> alone gives N sequential refreshes for N concurrent 401s, which with a rotating refresh token
> means the second refresh presents an already-consumed token and logs the user out. Each
> request is stamped with the generation it was sent under; a request whose generation is
> behind the current one knows a sibling already refreshed, and reuses that token. Because
> `onError` is serialized, the counter needs no lock.
>
> **Why a session epoch as well.** The generation counter answers "has the token changed since
> this request left?" It cannot answer "is this still the same session?" In 1.x, signing in
> bumped the generation, so a request sent by user A that came back 401 after user B signed in
> looked like an ordinary stale-token case: it read the current token, which was B's, and
> replayed A's request with B's credentials. The epoch is bumped on every sign-in, sign-out, and
> expiry; a 401 from an older epoch is dropped as cancelled, silently, without a refresh and
> without a replay. The epoch is checked again after the refresh call returns, because a
> sign-out can happen while the refresh is in flight.
>
> **Why `_expired` replaced the failed-generation marker.** rc.1 had two mechanisms for
> invariant 2: a `_failedGeneration` check and the epoch bump in `_expireOnce`. Each covered the
> other, so its test passed with either one deleted, including the deletion its own comment
> named; reproduced against rc.1's code, the test stays green with its sabotage applied. rc.2
> keeps one mechanism per job, each with its own test: the epoch bump quiets siblings already in
> flight (they become `StaleSession`, one caller hears "session expired" instead of three), and
> `if (_expired)` stops a request sent *after* the teardown from refreshing again. The second
> also closes a gap rc.1 had: a request sent while signed out whose 401 arrived after the next
> user's `save` but before `startSession` would have refreshed with the new user's token.

```dart
/// Marker errors, carried in DioException.error so the mapper can tell them apart.
final class ReplayRefused implements Exception {
  const ReplayRefused();
}

final class StaleSession implements Exception {
  const StaleSession();
}

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.readToken,
    required this.refresh,
    required this.onExpired,
    required this._retryClient,
  });

  final Future<String?> Function() readToken;
  final Future<RefreshOutcome> Function() refresh;
  final Future<void> Function() onExpired;
  final Dio _retryClient;

  // All mutable state is touched only inside serialized callbacks or synchronous
  // session calls, so none of it needs a lock.
  int _generation = 0; // token era: +1 per successful refresh
  int _epoch = 0; // session era: +1 per sign-in, sign-out, and expiry
  bool _expired = false; // the current session is over: no refresh, no second teardown

  static const _kGen = 'auth.gen';
  static const _kEpoch = 'auth.epoch';
  static const _kReplayed = 'auth.replayed';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[kSkipAuth] == true) return handler.next(options);
    final token = await readToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    options.extra[_kGen] = _generation;
    options.extra[_kEpoch] = _epoch;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    if (err.response?.statusCode != 401 || o.extra[kSkipAuth] == true) {
      return handler.next(err); // not ours: wrong password, 403, 500, offline...
    }

    // Invariant 3: sent under a session that has since ended or been replaced.
    if (o.extra[_kEpoch] != _epoch) return handler.next(_stale(o));

    // Invariant 2: this session already ended. Never refresh for it again.
    if (_expired) return handler.next(err);

    // A replay that 401s again: the fresh token itself is rejected.
    if (o.extra[_kReplayed] == true) {
      await _expireOnce();
      return handler.next(err);
    }

    final sentGen = o.extra[_kGen] as int? ?? _generation;
    final String token;

    if (sentGen < _generation) {
      // Invariant 1: a sibling already refreshed while this request was in flight.
      final current = await readToken();
      if (current == null) return handler.next(_stale(o));
      token = current;
    } else {
      final outcome = await refresh();
      // Invariant 3, again: the user may have signed out while the refresh was in flight.
      if (o.extra[_kEpoch] != _epoch) return handler.next(_stale(o));
      switch (outcome) {
        case Refreshed(:final accessToken):
          _generation++;
          token = accessToken;
        case RefreshRejected():
          await _expireOnce();
          return handler.next(err);
        case RefreshUnavailable(:final error):
          // Invariant 4: the session is still valid. Report what actually happened.
          return handler.next(error);
      }
    }

    // Invariant 6: refreshed and persisted, but this request cannot safely be sent twice.
    // Surface it as retryable, never as an expired session; the caller's own retry
    // carries the new token.
    if (!_canReplay(o)) {
      return handler.next(
        DioException(requestOptions: o, response: err.response, error: const ReplayRefused()),
      );
    }

    try {
      handler.resolve(await _retryClient.fetch(_withToken(o, token)));
    } on DioException catch (retryErr) {
      // Invariant 5: only a 401 on the replay means the fresh token is rejected.
      if (retryErr.response?.statusCode == 401) await _expireOnce();
      handler.next(retryErr);
    } catch (e, stack) {
      // A non-Dio throw must not escape the interceptor, and must not masquerade as a 401.
      handler.next(DioException(requestOptions: o, error: e, stackTrace: stack));
    }
  }

  /// Call from AuthStateNotifier.setAuthenticated. Opens a new session era.
  void startSession() {
    _epoch++;
    _generation++;
    _expired = false;
  }

  /// Call from AuthStateNotifier.signOut, before clearing the session.
  /// Everything in flight becomes stale; nothing is left to tear down.
  void endSession() {
    _epoch++;
    _expired = true;
  }

  Future<void> _expireOnce() async {
    if (_expired) return;
    _expired = true;
    _epoch++; // other in-flight 401s of this session go quiet instead of toasting N times
    try {
      await onExpired();
    } catch (e, stack) {
      reporter.recordError(e, stack, fatal: false);
    }
  }

  /// Safe to send twice: a body that can be re-read, and either an idempotent method or an
  /// Idempotency-Key the server deduplicates on.
  bool _canReplay(RequestOptions o) {
    if (o.data is FormData || o.data is Stream) return false;
    const idempotent = {'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'};
    return idempotent.contains(o.method.toUpperCase()) ||
        o.headers.keys.any((k) => k.toLowerCase() == kIdempotencyKeyHeader.toLowerCase());
  }

  DioException _stale(RequestOptions o) =>
      DioException.requestCancelled(requestOptions: o, reason: const StaleSession());

  RequestOptions _withToken(RequestOptions o, String token) => o.copyWith(
    headers: {...o.headers, 'Authorization': 'Bearer $token'},
    extra: {...o.extra, _kReplayed: true},
  );
}
```

**The replay policy, and the backend contract behind it.** A POST that returned 401 was, on a
correctly built backend, never executed: authentication runs before the handler. That is a
property of the server, not of the client, and the client cannot verify it. So the client
does not assume it. A request is replayed only when sending it twice is harmless on its own
terms: an idempotent method, or a non-idempotent write that carries an `Idempotency-Key` the
server deduplicates on. Everything else is refreshed but not replayed, and reaches the UI as
`ErrorType.retryable` ("Please try again."), which is true. This is ADR-005.

`FormData` and `Stream` bodies are never replayed whatever the method: they are
single-consumption, and re-sending one either throws or uploads an empty body. The order of the
checks is part of the policy. The replay check comes *after* the refresh, so the caller's
retry carries a valid token and fails at most once; placed before the refresh, an upload after
token expiry would fail twice. The multipart test in §7 pins this.

**Wiring (`core/network/dio_providers.dart`).** The interceptor is its own provider so the auth
notifier can reach `startSession` and `endSession`. Navigation is not its job: `onExpired`
clears the session and notifies `SessionExpiry`, the auth state flips to signed out, and the
route guard (§4) is the single authority that sends the user to the login screen. In 1.x both
the interceptor and the guard navigated, which double-pushed the login route. `SessionExpiry`
wraps the stream controller so consumers get a stream and one way to emit, never the
controller itself (and `close_sinks` is satisfied without a suppression).

```dart
/// Session-expiry events, from the interceptor to AuthStateNotifier. Exposes the stream
/// and one way to emit, not the controller.
final class SessionExpiry {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;
  void notify() => _controller.add(null);
  Future<void> dispose() => _controller.close();
}

final sessionExpiredProvider = Provider<SessionExpiry>((ref) {
  final expiry = SessionExpiry();
  ref.onDispose(expiry.dispose);
  return expiry;
});

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  final config = ref.watch(appConfigProvider);
  final newAdapter = ref.watch(httpAdapterFactoryProvider);
  final session = ref.watch(sessionStoreProvider);
  final expired = ref.watch(sessionExpiredProvider);

  return AuthInterceptor(
    readToken: () async => session.accessToken, // memory, not the keystore
    refresh: TokenRefresher(buildDio(config, newAdapter()), session).call,
    retryClient: buildDio(config, newAdapter()),
    onExpired: () async {
      await session.clear(); // never throws
      expired.notify();
    },
  );
});

final dioProvider = Provider<Dio>((ref) {
  final dio = buildDio(ref.watch(appConfigProvider), ref.watch(httpAdapterFactoryProvider)());
  dio.interceptors.addAll([
    if (kDebugMode) LoggerInterceptor(),
    ref.watch(authInterceptorProvider),
    ReportingInterceptor(), // last: sees only failures that survived refresh and replay
  ]);
  return dio;
});
```

**Proactive refresh beats reactive refresh.** Refreshing on a 401 costs the user one wasted
round trip per expiry. If your access token carries an `exp`, check it in `onRequest` and
refresh when it is within, say, thirty seconds of expiring. The 401 path then becomes the
fallback for clock skew and server-side revocation. The generation counter and the epoch are
what make adding this safe.

### Logging interceptor (`core/network/logging_interceptor.dart`)

Debug-only logging. Redacts `Authorization` headers and every `/auth/` body in both directions,
and a test asserts that neither a bearer nor a password reaches `debugPrint`. Registered only
under `kDebugMode`, so it cannot leak into a release logcat. It is registered before
`AuthInterceptor`, so it logs headers as the caller set them, before the bearer is attached.

### Reporting interceptor (`core/network/reporting_interceptor.dart`)

Registered after `AuthInterceptor`, so it only sees failures that survived refresh and replay.
It reports **actionable** failures only, and reports a redacted value, never the
`DioException` itself: a `DioException`'s string form can include the full URI with its query
string, which is where search terms, emails, and occasionally tokens end up.

```dart
/// What reaches the crash reporter: method, a templated path, status, and type.
/// Never headers, bodies, query strings, or raw ids.
final class NetworkFailure implements Exception {
  NetworkFailure(DioException e)
    : method = e.requestOptions.method,
      path = e.requestOptions.uri.path.replaceAll(_id, '/:id'),
      status = e.response?.statusCode,
      type = e.type;

  // Numeric ids and UUIDs become ':id', which also groups the dashboard by endpoint.
  static final _id = RegExp(r'/(\d+|[0-9a-fA-F]{8}-[0-9a-fA-F-]{27})(?=/|$)');

  final String method;
  final String path;
  final int? status;
  final DioExceptionType type;

  @override
  String toString() => 'NetworkFailure($method $path, status: $status, type: ${type.name})';
}

class ReportingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_actionable(err)) {
      reporter.recordError(NetworkFailure(err), err.stackTrace, fatal: false);
    }
    handler.next(err);
  }

  /// Offline, timeouts, cancellations, session expiry and 4xx verdicts are expected
  /// outcomes and stay off the dashboard. 5xx, certificate failures, and unknowns do not.
  static bool _actionable(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return status >= 500;
    return e.type == DioExceptionType.badCertificate || e.type == DioExceptionType.unknown;
  }
}
```

The rule: the user sees a message, and we see the stack trace. Neither substitutes for the
other, and network reporting happens in exactly one place rather than sprinkled through
repositories. Timeouts and offline rates are a metrics question, not a crash question; track
them as analytics events if you need them (§11.6).

### Theme notifier (`common/notifiers/theme_notifier.dart`)

An immutable `ThemeSettings` (followDevice plus isDark) with a `mode` getter, driven by a
`Notifier`. Preferences persist to `shared_preferences` and are loaded once before `runApp`.

```dart
final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeSettings>(ThemeNotifier.new);

class ThemeNotifier extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() => ThemeSettings.defaults;

  Future<void> load() async { /* read prefs into state */ }

  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(isDark: value);
    await _save();
  }
}
```

---
### Threat model and limits

What the session and networking design protects against, and the test that proves each one.
Every test named here is also in `check_sabotage.dart`, so none of them can pass vacuously.

| Scenario | Mechanism | Test |
| --- | --- | --- |
| User B signs in while user A's request is in flight | session epoch | "an old session's 401 is dropped, never replayed with the new user's token" |
| Sign-out while `/auth/refresh` is in flight | epoch rechecked after refresh; `rotate` identity check | "a sign-out during the refresh call...", "a refresh that finishes after sign-out..." |
| Several requests 401 at once | token generation | "two concurrent 401s trigger exactly one refresh" |
| Refresh token dead | expire-once latch; no refresh after teardown | "a dead refresh token tears down once", "a request sent after expiry..." |
| Offline or 5xx during refresh | `RefreshUnavailable` keeps the session | "a refresh that times out keeps the session" |
| App killed mid-rotation | one storage write per rotation | "rotation is one write" |
| Keystore read fails, write fails, delete fails, or hangs | the `SessionStore` contract table | one test per row |
| Previous install's iOS keychain on reinstall | first-launch wipe | "first launch after install wipes a keychain..." |
| Tokens leave the device in a backup | backup exclusions; `this_device` accessibility | `check_release_config.dart`, `secure_storage_test.dart` |
| A non-idempotent write sent twice by a replay | replay policy | "a POST without an idempotency key is refreshed but not replayed" |
| Tokens or personal data in logs and crash reports | redaction | "the debug logger never prints a bearer...", "a 5xx is reported as a redacted NetworkFailure" |
| Spoofed, multi-line or oversized server copy | sanitization | "server copy is constrained before it can reach the screen" |

**What it does not protect against.** State these to anyone who relies on the design:

- **The device owner, or malware with root or accessibility rights.** Keystore and Keychain raise the cost of reading tokens; they do not make them secret from a compromised device. The access token also lives in process memory for the session.
- **A network attacker the device already trusts.** TLS proves the server presents a certificate the device accepts; a user-installed or corporate CA passes that test. Certificate pinning (§11.3) narrows it, can itself be bypassed on a rooted device, and turns a certificate rotation into an outage if there is no backup pin.
- **Backup paths outside the rules.** The Android exclusions cover cloud backup and device-to-device transfer as the platform defines them, not OEM backup tools or a rooted filesystem. `this_device` keeps iOS items from restoring onto another device; it does not hide them from the device they are on.
- **Exactly-once execution.** The client sends an idempotency key and refuses unsafe replays; only the backend can deduplicate (§5). Without that, a retried write can still execute twice.
- **Stolen refresh tokens.** Rotation, reuse detection and revocation are server responsibilities. The client honors a rotated token; it cannot detect that someone else used the old one.
- **What the server says.** Sanitized server copy is still the server's words.

