// Append to tool/lints/lib/main.dart, and register UiPurity and UiStateless in the plugin.

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
