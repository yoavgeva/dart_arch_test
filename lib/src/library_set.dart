/// A lazily-evaluated set of library URIs selected by a glob pattern,
/// analogous to `ArchTest.ModuleSet` in the Elixir library.
library;

import 'package:dart_arch_test/src/collector.dart';
import 'package:dart_arch_test/src/pattern.dart';

/// A selector that resolves to a concrete set of library URIs from a
/// [DependencyGraph].
// ignore: one_member_abstracts
abstract interface class LibrarySelector {
  /// Resolves this selector against [graph], returning the matching URIs.
  Set<String> resolve(DependencyGraph graph);
}

/// Primary implementation: selects libraries whose URI matches a glob pattern.
class LibrarySet implements LibrarySelector {
  LibrarySet._(this._includes, this._excludes);

  /// Creates a [LibrarySet] for libraries matching [pattern].
  ///
  /// Pattern uses glob syntax: `**` for any depth, `*` for one segment.
  ///
  /// Examples:
  /// ```dart
  /// filesMatching('features/home/**')  // all files under features/home/
  /// filesMatching('**/*Service.dart')  // files ending in Service.dart
  /// filesMatching('features/home/home_screen.dart')  // exact file
  /// ```
  factory LibrarySet.matching(String pattern) => LibrarySet._([pattern], []);

  /// Creates a [LibrarySet] that matches all libraries in the graph.
  factory LibrarySet.all() => LibrarySet._(['**'], []);

  final List<String> _includes;
  final List<String> _excludes;

  /// Returns a new [LibrarySet] that additionally excludes [pattern].
  LibrarySet excluding(String pattern) =>
      LibrarySet._([..._includes], [..._excludes, pattern]);

  /// Returns a [LibrarySelector] that is the union of this set and [other].
  LibrarySelector unionWith(LibrarySelector other) => _UnionSet(this, other);

  @override
  Set<String> resolve(DependencyGraph graph) {
    final all = Collector.allLibraries(graph);
    return all.where(_matches).toSet();
  }

  bool _matches(String uri) {
    final matched = _includes.any((p) => matchesGlob(p, uri));
    if (!matched) return false;
    return !_excludes.any((p) => matchesGlob(p, uri));
  }
}

/// Union of two selectors.
class _UnionSet implements LibrarySelector {
  _UnionSet(this._a, this._b);

  final LibrarySelector _a;
  final LibrarySelector _b;

  @override
  Set<String> resolve(DependencyGraph graph) => {
    ..._a.resolve(graph),
    ..._b.resolve(graph),
  };
}

/// Intersection of two selectors.
class _IntersectionSet implements LibrarySelector {
  _IntersectionSet(this._a, this._b);

  final LibrarySelector _a;
  final LibrarySelector _b;

  @override
  Set<String> resolve(DependencyGraph graph) {
    final aSet = _a.resolve(graph);
    return _b.resolve(graph).where(aSet.contains).toSet();
  }
}

/// Convenience top-level functions mirroring the Elixir DSL.

/// Returns a [LibrarySet] for files matching [pattern].
///
/// ```dart
/// filesMatching('features/home/**')
///   .shouldNotDependOn(filesMatching('features/discover/**'));
/// ```
LibrarySet filesMatching(String pattern) => LibrarySet.matching(pattern);

/// Returns a [LibrarySet] matching all libraries in the graph.
LibrarySet allFiles() => LibrarySet.all();

/// Returns a [LibrarySelector] that is the union of [a] and [b].
LibrarySelector union(LibrarySelector a, LibrarySelector b) => _UnionSet(a, b);

/// Returns a [LibrarySelector] that is the intersection of [a] and [b].
LibrarySelector intersection(LibrarySelector a, LibrarySelector b) =>
    _IntersectionSet(a, b);
