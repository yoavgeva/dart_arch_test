/// Content-based library selectors that inspect class declarations
/// rather than (or in addition to) file paths.
///
/// These selectors build on the `analyzer` package to look inside each
/// Dart file and filter libraries by:
///   - Which classes a file **extends** ([extending])
///   - Which interfaces a file **implements** ([implementing])
///   - Which annotations top-level declarations carry ([withAnnotation])
///
/// They accept the same [DependencyGraph] used by assertion functions.
///
/// ## Example
///
/// ```dart
/// // Every file that extends ChangeNotifier must live in a providers/ folder
/// test('ChangeNotifier subclasses must be in providers/', () {
///   shouldHaveUriMatching(
///     extending('ChangeNotifier'),
///     '**/providers/**',
///     graph,
///   );
/// });
///
/// // Files that implement UnreadCountSource must not import features/
/// test('UnreadCountSource impls stay in shared/', () {
///   shouldNotDependOn(
///     implementing('UnreadCountSource'),
///     filesMatching('features/**'),
///     graph,
///   );
/// });
///
/// // @immutable models must not import services
/// test('@immutable classes must not import services', () {
///   shouldNotTransitivelyDependOn(
///     withAnnotation('immutable'),
///     filesMatching('**/services/**'),
///     graph,
///   );
/// });
/// ```
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:dart_arch_test/src/collector.dart';
import 'package:dart_arch_test/src/library_set.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Returns a [LibrarySelector] matching all libraries that contain at least
/// one class (or mixin) that **extends** a class named [superclassName].
///
/// The match is by simple name only — package prefix is not considered.
///
/// ```dart
/// extending('ChangeNotifier')   // matches provider subclasses
/// extending('StatefulWidget')   // matches all StatefulWidget subclasses
/// extending('Equatable')        // matches Equatable data classes
/// ```
LibrarySelector extending(String superclassName) =>
    _ClassMatchSelector._extending(superclassName);

/// Returns a [LibrarySelector] matching all libraries that contain at least
/// one class that **implements** an interface named [interfaceName].
///
/// ```dart
/// implementing('Repository')
/// implementing('UnreadCountSource')
/// ```
LibrarySelector implementing(String interfaceName) =>
    _ClassMatchSelector._implementing(interfaceName);

/// Returns a [LibrarySelector] matching all libraries that contain at least
/// one top-level declaration carrying the annotation [annotationName].
///
/// The name is the simple name without `@` — e.g. `'immutable'` or
/// `'Injectable'`.
///
/// ```dart
/// withAnnotation('immutable')
/// withAnnotation('Injectable')
/// withAnnotation('freezed')
/// ```
LibrarySelector withAnnotation(String annotationName) =>
    _ClassMatchSelector._withAnnotation(annotationName);

/// Clears the in-process resolution cache used by [extending], [implementing],
/// and [withAnnotation].
///
/// Call this in `tearDownAll` if you need to run multiple independent
/// analysis passes in the same process.
void clearContentMatcherCache() => _ClassMatchSelector.clearCache();

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

enum _MatchMode { extending, implementing, withAnnotation }

class _ClassMatchSelector implements LibrarySelector {
  _ClassMatchSelector._extending(String name)
    : _mode = _MatchMode.extending,
      _name = name;

  _ClassMatchSelector._implementing(String name)
    : _mode = _MatchMode.implementing,
      _name = name;

  _ClassMatchSelector._withAnnotation(String name)
    : _mode = _MatchMode.withAnnotation,
      _name = name;

  final _MatchMode _mode;
  final String _name;

  // Cache keyed by (mode, name, rootPath) to avoid redundant analysis passes.
  static final Map<String, Set<String>> _cache = {};

  @override
  Set<String> resolve(DependencyGraph graph) {
    if (graph.isEmpty) return {};

    final rootPath = _rootPathFromGraph();
    if (rootPath == null) return {};

    final cacheKey = '${_mode.name}:$_name:$rootPath';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final result = _resolveFromDisk(graph, rootPath);
    _cache[cacheKey] = result;
    return result;
  }

  Set<String> _resolveFromDisk(DependencyGraph graph, String rootPath) {
    final absRoot = p.canonicalize(rootPath);

    final collection = AnalysisContextCollection(
      includedPaths: [absRoot],
      sdkPath: Collector.resolveDartSdkPath(),
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final matched = <String>{};

    for (final context in collection.contexts) {
      for (final uri in graph.keys) {
        final filePath = _uriToPath(uri, absRoot);
        if (filePath == null) continue;
        if (!File(filePath).existsSync()) continue;

        final result = context.currentSession.getParsedLibrary(filePath);
        if (result is! ParsedLibraryResult) continue;

        for (final unit in result.units) {
          if (_unitMatches(unit.unit)) {
            matched.add(uri);
            break;
          }
        }
      }
    }

    return matched;
  }

  bool _unitMatches(CompilationUnit unit) {
    for (final decl in unit.declarations) {
      if (_declMatches(decl)) return true;
    }
    return false;
  }

  bool _declMatches(CompilationUnitMember decl) {
    switch (_mode) {
      case _MatchMode.extending:
        return _matchesExtends(decl);
      case _MatchMode.implementing:
        return _matchesImplements(decl);
      case _MatchMode.withAnnotation:
        return _matchesAnnotation(decl);
    }
  }

  bool _matchesExtends(CompilationUnitMember decl) {
    if (decl is ClassDeclaration) {
      final superclass = decl.extendsClause?.superclass;
      return superclass != null && _namedTypeName(superclass) == _name;
    }
    return false;
  }

  bool _matchesImplements(CompilationUnitMember decl) {
    List<NamedType>? interfaces;
    if (decl is ClassDeclaration) {
      interfaces = decl.implementsClause?.interfaces;
    } else if (decl is MixinDeclaration) {
      interfaces = decl.implementsClause?.interfaces;
    } else if (decl is EnumDeclaration) {
      interfaces = decl.implementsClause?.interfaces;
    }
    return interfaces?.any((i) => _namedTypeName(i) == _name) ?? false;
  }

  bool _matchesAnnotation(CompilationUnitMember decl) {
    return decl.metadata.any((ann) {
      final annotationName = ann.name.name;
      // Handle both 'foo' and 'prefix.foo' annotation forms
      return annotationName == _name || annotationName.endsWith('.$_name');
    });
  }

  static String _namedTypeName(NamedType namedType) => namedType.name.lexeme;

  static String? _uriToPath(String uri, String absRoot) {
    final match = RegExp(r'^package:[^/]+/(.+)$').firstMatch(uri);
    final tail = match?.group(1);
    if (tail == null) return null;
    return p.join(absRoot, 'lib', tail);
  }

  /// Resolves the package root by walking up from [Directory.current] to find
  /// the nearest `pubspec.yaml`, or reading the `DART_ARCH_TEST_ROOT`
  /// environment variable.
  static String? _rootPathFromGraph() {
    final env = Platform.environment['DART_ARCH_TEST_ROOT'];
    if (env != null && File(p.join(env, 'pubspec.yaml')).existsSync()) {
      return env;
    }

    // Walk up from CWD to find pubspec.yaml (works for both `dart test` and
    // `flutter test` invocations regardless of working directory).
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static void clearCache() => _cache.clear();
}
