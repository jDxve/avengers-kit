## 8. Tooling and Enforcement

The dependency rules above are only real if CI can fail on them. Five things carry that weight,
and §11.2 runs every one of them on every PR:

| Tool | Catches | Runs as |
| --- | --- | --- |
| `analysis_options.yaml` | style, relative imports, unawaited futures, unresolved imports | `dart analyze` |
| `riverpod_lint` (native plugin) | Riverpod misuse that compiles and misbehaves | `dart analyze` |
| `app_lints` (native plugin, local) | the four layering rules | `dart analyze` |
| `tool/check_lint_fixture.dart` | a rule that silently stopped firing; a plugin the app silently stopped loading | `dart run` |
| `tool/check_architecture.dart` | feature cycles, unjustified suppressions | `dart run` |

> **The single most expensive mistake in this document's history, made twice.** 1.x said
> `flutter analyze` "includes custom_lint + riverpod_lint". It did not, so every boundary rule
> ran on the author's screen and nowhere else. rc.1 fixed that by adding `dart run custom_lint`
> to CI, and that stopped working too: `custom_lint` 0.8.1 requires `analyzer ^8`, while
> `riverpod_lint` 3.x moved to the SDK's native plugin system on `analyzer` 13 to 14. The two no
> longer resolve in one `pubspec`. rc.2 moves `app_lints` to a native plugin (ADR-007).
>
> Native plugins carry the same trap in a new shape. Verified on Flutter 3.47.8 / Dart 3.13.7:
> **`dart analyze` at the package root reports plugin diagnostics; `flutter analyze` does not,
> and neither does `dart analyze <some/subdirectory>`; and a misspelled plugin path is ignored
> without a warning.** Each of those leaves CI green with zero enforcement. So CI runs
> `dart analyze` with no path argument, and `tool/check_lint_fixture.dart` plants a canary
> violation in the app itself to prove both plugins actually loaded.

### `analysis_options.yaml`

```yaml
include: package:flutter_lints/flutter.yaml

formatter:
  page_width: 100

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - test/coverage_helper_test.dart
    - tool/lints/** # its own packages, analyzed by their own CI steps
    - build/**
    - android/**
    - ios/**
  errors:
    always_use_package_imports: error # the boundary lints key off package: paths
    unawaited_futures: error # fire-and-forget deletes raced navigation in 1.x

linter:
  rules:
    always_use_package_imports: true
    unawaited_futures: true
    cancel_subscriptions: true
    close_sinks: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_constructors_in_immutables: true
    prefer_const_literals_to_create_immutables: true
    prefer_final_fields: true
    unnecessary_this: true
    sort_pub_dependencies: true

# Native analyzer plugins (Dart 3.10+). Reported by `dart analyze` run at the package root
# with no path argument; not by `flutter analyze` (Flutter 3.47.8). Only this root file may
# configure them.
plugins:
  app_lints:
    path: tool/lints
  riverpod_lint: 3.1.9
```

`plugins:` is honored only in the root options file of the package or workspace, never in a
nested one. `app_lints` registers its rules as *warning* rules, which are on by default:
forgetting a `diagnostics:` line cannot disable them. Plugin rule severity is set in the rule's
code (`ERROR`), not in `analyzer: errors:`, and suppressions name the plugin:
`// ignore: app_lints/no_cross_feature_imports`.

`formatter: page_width: 100` matches the code in this document. Under the default 80, `dart format`
splits `if (x) return y;` one-liners across lines and `curly_braces_in_flow_control_structures`
then fails `--fatal-infos`.

An unresolved import is an analyzer **error** (`uri_does_not_exist`), so `dart analyze` fails on
it before the boundary lints are consulted. That matters because the lints skip URIs they cannot
classify rather than guessing.

### Boundary lints: the implementation, not pseudo-config

> **This is the part most architecture READMEs get wrong.** A lint rule is Dart code. YAML can
> enable a rule; it cannot define what the rule matches. A config block that appears to declare
> `from` and `to` path globs is silently ignored unless code you wrote reads it.

The rules live in a local package at `tool/lints`, a native analyzer plugin. The analysis
server builds it from the path in `analysis_options.yaml`; the app does not depend on it.

```yaml
name: app_lints
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  analysis_server_plugin: ^0.3.25
  analyzer: ^14.6.0
```

Every rule has the same shape: a file at location A may not import a URI at location B. The
base class does the plumbing once; each rule is a predicate.

```dart
// tool/lints/lib/main.dart
import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

final plugin = AppLintsPlugin();

class AppLintsPlugin extends Plugin {
  @override
  String get name => 'app_lints';

  @override
  void register(PluginRegistry registry) {
    // Warning rules are on by default: forgetting a config line cannot silently disable them.
    registry
      ..registerWarningRule(LayerBoundary())
      ..registerWarningRule(NoCrossFeatureImports())
      ..registerWarningRule(SharedLayerIndependence())
      ..registerWarningRule(DomainPurity())
      ..registerWarningRule(UiPurity())
      ..registerWarningRule(UiStateless());
  }
}

abstract class _ImportRule extends AnalysisRule {
  _ImportRule(this.diagnosticCode, String description)
    : super(name: diagnosticCode.lowerCaseName, description: description);

  @override
  final LintCode diagnosticCode;

  /// True when [self] importing [target] breaks this rule. [pkg] is this app's package name.
  bool violates(Uri self, Uri target, String pkg);

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _DirectiveVisitor(this, context);
    registry
      ..addImportDirective(this, visitor)
      ..addExportDirective(this, visitor); // re-exporting an internal is importing it
  }
}

class _DirectiveVisitor extends SimpleAstVisitor<void> {
  _DirectiveVisitor(this.rule, this.context);

  final _ImportRule rule;
  final RuleContext context;

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    final self = context.libraryElement?.uri;
    if (self == null || self.scheme != 'package' || self.pathSegments.isEmpty) return;
    final pkg = self.pathSegments.first;

    // Conditional imports carry extra URIs; each one is a real dependency.
    final raws = [node.uri.stringValue, for (final c in node.configurations) c.uri.stringValue];
    for (final raw in raws.whereType<String>()) {
      // Resolve against this library so relative and package: forms compare equal.
      if (rule.violates(self, self.resolve(raw), pkg)) {
        rule.reportAtNode(node);
        return;
      }
    }
  }
}

LintCode _code(String name, String message) =>
    LintCode(name, message, severity: DiagnosticSeverity.ERROR);

/// (feature, layer) for package:<pkg>/features/<feature>/<layer>/..., else null.
/// For the feature's root file (features/<feature>/<feature>.dart) the "layer" is that file name.
(String, String)? _slice(Uri u, String pkg) {
  final s = u.pathSegments;
  if (u.scheme != 'package' || s.length < 4 || s[0] != pkg || s[1] != 'features') return null;
  return (s[2], s[3]);
}

/// The top-level folder under lib/ (core, common, features, ...), for this package only.
String? _area(Uri u, String pkg) {
  final s = u.pathSegments;
  return u.scheme == 'package' && s.length > 1 && s[0] == pkg ? s[1] : null;
}

/// Inside one feature, presentation/ and data/ meet only at domain/.
class LayerBoundary extends _ImportRule {
  LayerBoundary()
    : super(
        _code(
          'layer_boundary',
          'presentation/ and data/ meet only at the domain/ contract; neither imports the other.',
        ),
        'Same-feature presentation and data layers may not import each other.',
      );

  @override
  bool violates(Uri self, Uri target, String pkg) {
    final from = _slice(self, pkg);
    final to = _slice(target, pkg);
    if (from == null || to == null || from.$1 != to.$1) return false;
    return (from.$2 == 'presentation' && to.$2 == 'data') ||
        (from.$2 == 'data' && to.$2 == 'presentation');
  }
}

/// True for package:<pkg>/features/<feature>/<file>.dart: the feature's public API file.
bool _isFeatureRoot(Uri u, String pkg) {
  final s = u.pathSegments;
  return u.scheme == 'package' && s.length == 4 && s[0] == pkg && s[1] == 'features';
}

/// Another feature's public surface is its domain/ and its root file; everything else is private.
class NoCrossFeatureImports extends _ImportRule {
  NoCrossFeatureImports()
    : super(
        _code(
          'no_cross_feature_imports',
          "Another feature's data/ and presentation/ are private. Depend on its domain/ "
              'or its root <feature>.dart, or move the shared piece to common/ or core/.',
        ),
        "Features may import only another feature's domain/ and root file.",
      );

  @override
  bool violates(Uri self, Uri target, String pkg) {
    final from = _slice(self, pkg);
    final to = _slice(target, pkg);
    return from != null &&
        to != null &&
        from.$1 != to.$1 &&
        to.$2 != 'domain' &&
        !_isFeatureRoot(target, pkg);
  }
}

/// core/ and common/ are below every feature and may not reach up into one.
class SharedLayerIndependence extends _ImportRule {
  SharedLayerIndependence()
    : super(
        _code(
          'shared_layer_independence',
          'core/ and common/ may not import a feature. Move the dependency down, '
              'or move this file into the feature.',
        ),
        'core/ and common/ may not depend on features/.',
      );

  @override
  bool violates(Uri self, Uri target, String pkg) =>
      const {'core', 'common'}.contains(_area(self, pkg)) && _area(target, pkg) == 'features';
}

/// domain/ is platform- and transport-independent: an allowlist, not a denylist.
class DomainPurity extends _ImportRule {
  DomainPurity()
    : super(
        _code(
          'domain_purity',
          'domain/ may import only dart:core/async/collection/math/typed_data, '
              "package:meta, package:collection, core/result/, and other features' domain/.",
        ),
        'domain/ depends only on an allowlist.',
      );

  static const _dart = {'core', 'async', 'collection', 'math', 'typed_data'};
  static const _packages = {'meta', 'collection'};

  @override
  bool violates(Uri self, Uri target, String pkg) {
    if (_slice(self, pkg)?.$2 != 'domain') return false;
    if (target.scheme == 'dart') return !_dart.contains(target.path);
    if (target.scheme != 'package' || target.pathSegments.isEmpty) return false;
    final s = target.pathSegments;
    if (s.first != pkg) return !_packages.contains(s.first);
    final to = _slice(target, pkg);
    if (to != null) return to.$2 != 'domain';
    return !(s.length > 2 && s[1] == 'core' && s[2] == 'result');
  }
}

/// True for package:<pkg>/features/<feature>/presentation/ui/...
bool _isUi(Uri u, String pkg) {
  final s = u.pathSegments;
  return u.scheme == 'package' &&
      s.length > 5 &&
      s[0] == pkg &&
      s[1] == 'features' &&
      s[3] == 'presentation' &&
      s[4] == 'ui';
}

/// presentation/ui/ renders props and fires callbacks: an allowlist, not a denylist.
class UiPurity extends _ImportRule {
  UiPurity()
    : super(
        _code(
          'ui_purity',
          'presentation/ui/ takes data through its constructor and reports through callbacks. '
              'It may import only Flutter, common/resources, common/widgets, common/models, '
              'other ui/ files, and domain/models. Wire state in screens/ or components/.',
        ),
        'presentation/ui/ is presentational and depends only on an allowlist.',
      );

  static const _dart = {'core', 'async', 'collection', 'math', 'typed_data', 'ui'};
  // Add visual-only packages here (an SVG or icon package). Never state, network or storage.
  static const _packages = {'flutter', 'meta', 'collection'};

  @override
  bool violates(Uri self, Uri target, String pkg) {
    if (!_isUi(self, pkg)) return false;
    if (target.scheme == 'dart') return !_dart.contains(target.path);
    if (target.scheme != 'package' || target.pathSegments.isEmpty) return false;
    final s = target.pathSegments;
    if (s.first != pkg) return !_packages.contains(s.first);
    if (s.length > 2 && s[1] == 'common') {
      return !const {'resources', 'widgets', 'models'}.contains(s[2]);
    }
    final to = _slice(target, pkg);
    if (to == null) return true;
    if (to.$1 == _slice(self, pkg)!.$1 && _isUi(target, pkg)) return false;
    return !(to.$2 == 'domain' && s.length > 4 && s[4] == 'models');
  }
}

/// Local visual state (a controller, an animation) is a justified exception, not the default.
class UiStateless extends AnalysisRule {
  UiStateless() : super(name: 'ui_stateless', description: 'presentation/ui/ widgets are stateless.');

  static final _code = LintCode(
    'ui_stateless',
    'presentation/ui/ widgets are stateless. For purely visual state (animation, focus, text '
        'controller), suppress this with an "// ADR-NNN:" line above; business state goes in a notifier.',
    severity: DiagnosticSeverity.ERROR,
  );

  @override
  LintCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _UiStatelessVisitor(this, context));
  }
}

class _UiStatelessVisitor extends SimpleAstVisitor<void> {
  _UiStatelessVisitor(this.rule, this.context);

  final UiStateless rule;
  final RuleContext context;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final self = context.libraryElement?.uri;
    if (self == null || self.scheme != 'package' || self.pathSegments.isEmpty) return;
    if (!_isUi(self, self.pathSegments.first)) return;
    const stateful = {'StatefulWidget', 'HookWidget', 'StatefulHookWidget'};
    if (stateful.contains(node.extendsClause?.superclass.name.lexeme)) rule.reportAtNode(node);
  }
}
```

About two hundred and fifty lines, written once, and every PR that points an import arrow the
wrong way goes red before review.

**Why textual URIs resolved against the library, not the element model.** The obvious version
does `path.contains('/data/')` on the raw import string. That breaks four ways: a directory named
`metadata` or a package named `mydata` matches by substring; a relative import never contains the
package path; Windows paths use backslashes; and conditional imports hide a second URI. Resolving
each URI string against the library's own `package:` URI with `Uri.resolve` normalises relative
and absolute forms to the same value, and comparing path *segments* removes the substring
hazard. The rules touch only AST directives, `Uri`, and `context.libraryElement?.uri`, the
smallest surface of an API that is still pre-1.0.

**The rules allow what §1 allows, and that alignment is the point.** A lint stricter than its
own document is the worst of both: the first legitimate `orders -> billing/domain` import gets
an `ignore:` comment, and once one `ignore:` is in the codebase the rule is advisory. The reverse
is just as bad, and rc.1 had it: its worked example imported `data/` from `presentation/`, which
its own lint forbade. Running the rules over the reference app is what found it.

### The fixture and the canary: proving the rules fire

A lint rule that matches nothing reports nothing, and a rule that reports nothing looks exactly
like a codebase with no violations. `tool/lints/fixture/` is a tiny Dart package that enables
the plugin and contains every case written out. Native plugins have no `expect_lint`, so the
fixture marks expectations with `// expect: <rule>` on the line above, and
`tool/check_lint_fixture.dart` compares them with `dart analyze --format=machine`: every
expectation must fire, nothing else may, and every rule must fire at least once.

```yaml
# The fixture imports things it never uses, on purpose. Only plugin diagnostics matter here.
analyzer:
  errors:
    unused_import: ignore
    duplicate_import: ignore

plugins:
  app_lints:
    path: ..
```

```dart
// tool/lints/fixture/lib/features/orders/presentation/imports.dart
// expect: layer_boundary
import 'package:fixture/features/orders/data/orders_dto.dart';

// expect: layer_boundary
import '../data/orders_dto.dart'; // relative form resolves to the same URI

import 'package:fixture/features/orders/domain/order.dart'; // allowed
// expect: no_cross_feature_imports
import 'package:fixture/features/billing/data/invoice_dto.dart';
// expect: no_cross_feature_imports
import 'package:fixture/features/billing/presentation/billing_notifier.dart';
// expect: no_cross_feature_imports
import 'package:fixture/core/result/result.dart'
    if (dart.library.io) 'package:fixture/features/billing/data/invoice_dto.dart';
import 'package:fixture/features/billing/domain/invoice.dart'; // allowed: public contract
import 'package:fixture/features/billing/billing.dart'; // allowed: public API file
import 'package:fixture/common/widgets/button.dart'; // allowed
import 'package:fixture/metadata/version.dart'; // allowed: not a substring match

import 'dart:async'; // allowed

// expect: no_cross_feature_imports
export 'package:fixture/features/billing/data/invoice_dto.dart';
```

```dart
// tool/lints/fixture/lib/features/billing/domain/invoice.dart
// expect: domain_purity
import 'dart:io';

// expect: domain_purity
import 'package:fixture/core/network/http_client.dart';
// expect: domain_purity
import 'package:fixture/features/billing/data/invoice_dto.dart';
// expect: domain_purity
import 'package:fixture/features/billing/billing.dart'; // the root wires data, so domain may not
import 'package:fixture/core/result/result.dart'; // allowed
import 'package:fixture/features/orders/domain/order.dart'; // allowed

import 'dart:collection'; // allowed

class Invoice {}
```

```dart
// tool/lints/fixture/lib/features/orders/presentation/ui/imports.dart
import 'package:flutter/material.dart'; // allowed
import 'package:fixture/common/resources/strings.dart'; // allowed
import 'package:fixture/features/orders/domain/models/order.dart'; // allowed
import 'order_card.dart'; // allowed
// expect: ui_purity
import 'package:flutter_riverpod/flutter_riverpod.dart';
// expect: ui_purity
import '../notifier/orders_notifier.dart';
// expect: ui_purity
import 'package:fixture/features/orders/domain/repository/orders_repository.dart';
// expect: ui_purity
import 'package:fixture/core/state/data_state.dart';
```

The fixture also proves a suppression silences the rule (an `ignore:` that did not work would
show up as an unexpected diagnostic):

```dart
// tool/lints/fixture/lib/features/legacy/presentation/suppressed.dart
// A justified exception must silence the rule; if it does not, the checker sees an extra diagnostic.
// ADR-013: the legacy importer reads billing DTOs until the v3 API ships.
// ignore: app_lints/no_cross_feature_imports
import 'package:fixture/features/billing/data/invoice_dto.dart';
```

The fixture proves the rules; it cannot prove the *app* loads them. So the same script then
writes a two-file canary under `lib/features/zz_lint_canary/` (a `presentation/` file importing
its `data/`, and a notifier with a public field), runs `dart analyze` on the whole app, requires
both `layer_boundary` and `avoid_public_notifier_properties` on the canary, and deletes it. With
the plugin path misspelled, both disappear (one plugin failing to load took the other down with
it in testing), and the check fails.

```dart
/// Plants one violation per plugin in this app, analyzes only that folder, removes it.
List<String> _canary() {
  final pkg = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
  final dir = Directory('lib/features/zz_lint_canary');
  try {
    File('${dir.path}/data/source.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('const int canary = 0;\n');
    File('${dir.path}/presentation/canary_notifier.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:$pkg/features/zz_lint_canary/data/source.dart';

class CanaryNotifier extends Notifier<int> {
  int exposed = canary;

  @override
  int build() => exposed;
}
''');
    // The whole package, no path argument: analyzing a subdirectory skips plugins entirely.
    final run = Process.runSync('dart', ['analyze', '--format=machine']);
    final out = '${run.stdout}${run.stderr}'
        .split('\n')
        .where((l) => l.contains('zz_lint_canary'))
        .join('\n')
        .toLowerCase();
    return [
      if (!out.contains('|layer_boundary|'))
        'app_lints did not load (check plugins: in analysis_options.yaml)',
      if (!out.contains('|avoid_public_notifier_properties|')) 'riverpod_lint did not load',
    ];
  } finally {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
```

**When a boundary lint is wrong.** Reproduce it in the fixture first: add the import that
misfired with the expectation you believe is right, and run `dart run tool/check_lint_fixture.dart`.
If the fixture agrees with you, fix the predicate and keep the new fixture line, so the false
positive cannot come back. If the fixture agrees with the lint, the import is the problem; if it
is a justified exception, §12.2 applies.

### `tool/check_architecture.dart`: what a per-file linter cannot see

A plugin rule sees one library at a time, so it cannot see a cycle that spans files, and it
cannot judge whether a suppression was justified. This script does both, with no dependencies.

```dart
// 1. The feature dependency graph is acyclic.
// 2. Every suppression of an architecture rule cites an ADR on the line above it.
// Run from the package root: dart run tool/check_architecture.dart
import 'dart:io';

const _rules = [
  'layer_boundary',
  'no_cross_feature_imports',
  'shared_layer_independence',
  'domain_purity',
  'ui_purity',
  'ui_stateless',
];
final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
final _suppression = RegExp('ignore(?:_for_file)?:.*\\bapp_lints/(?:${_rules.join('|')})\\b');
final _adr = RegExp(r'^\s*//\s*ADR-\d+');

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final pkg = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
  final graph = <String, Set<String>>{};
  final problems = <String>[];

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final rel = file.path.replaceAll(r'\', '/').substring('lib/'.length);
    final self = Uri.parse('package:$pkg/$rel');
    final source = file.readAsStringSync();

    final from = _feature(self, pkg);
    if (from != null) {
      final edges = graph.putIfAbsent(from, () => <String>{});
      for (final m in _directive.allMatches(source)) {
        final to = _feature(self.resolve(m.group(1)!), pkg);
        if (to != null && to != from) edges.add(to);
      }
    }

    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (_suppression.hasMatch(lines[i]) && (i == 0 || !_adr.hasMatch(lines[i - 1]))) {
        problems.add(
          '${file.path}:${i + 1}: architecture rule suppressed without '
          'an "// ADR-NNN: reason" line directly above it (§12.2)',
        );
      }
    }
  }

  problems.addAll(_cycles(graph));
  if (problems.isEmpty) {
    stdout.writeln('architecture: ok (${graph.length} features, no cycles)');
    return;
  }
  problems.forEach(stderr.writeln);
  exitCode = 1;
}

String? _feature(Uri u, String pkg) {
  final s = u.pathSegments;
  return u.scheme == 'package' && s.length > 3 && s[0] == pkg && s[1] == 'features' ? s[2] : null;
}

/// Depth-first search. Reports each back edge as a readable path: "orders -> billing -> orders".
List<String> _cycles(Map<String, Set<String>> graph) {
  final state = <String, int>{}; // 1 = on the stack, 2 = finished
  final stack = <String>[];
  final found = <String>[];

  void visit(String node) {
    state[node] = 1;
    stack.add(node);
    for (final next in graph[node] ?? const <String>{}) {
      if (state[next] == 1) {
        found.add('feature cycle: ${[...stack.sublist(stack.indexOf(next)), next].join(' -> ')}');
      } else if (state[next] == null) {
        visit(next);
      }
    }
    stack.removeLast();
    state[node] = 2;
  }

  for (final node in graph.keys) {
    if (state[node] == null) visit(node);
  }
  return found;
}
```

The import regex does not see the second URI of a conditional import. That is an accepted gap:
conditional imports between features are vanishingly rare, and `no_cross_feature_imports` still
checks both URIs per file.

### `riverpod_lint`

Runs through the same analyzer as a native plugin, pinned by version in `analysis_options.yaml`,
and catches Riverpod mistakes that compile cleanly and misbehave at runtime. Its rules are on by
default; the canary relies on `avoid_public_notifier_properties`: a `Notifier`'s only public
surface is its commands and `state`, because public mutable fields do not trigger rebuilds. That
is the §6 "public methods are commands" rule, machine-checked.

> **Version note.** The native plugin API (`analysis_server_plugin`) is pre-1.0 and moves with
> the SDK. Plugins require Dart 3.10 (Flutter 3.38) or later. When the SDK pin moves, the
> fixture run and the canary are what prove the plugins still load; ADR-007 records when to
> revisit.

Between the boundary lints (structure), the architecture script (graph), the analyzer
(imports, futures), and `riverpod_lint` (state), the conventions hold even on a branch nobody
reviewed closely.

---

