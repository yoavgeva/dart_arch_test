/// Bounded-context / modulith isolation enforcement.
///
/// Analogous to `ArchTest.Modulith` in the Elixir library.
///
/// ```dart
/// final slices = defineSlices({
///   'home':     'features/home/**',
///   'discover': 'features/discover/**',
///   'auth':     'features/auth/**',
/// })
/// .allowDependency('home', 'auth')
/// .allowDependency('discover', 'auth');
///
/// slices.enforceIsolation(graph);
/// ```
library;

import 'package:dart_arch_test/src/assertions.dart';
import 'package:dart_arch_test/src/collector.dart';
import 'package:dart_arch_test/src/library_set.dart';
import 'package:dart_arch_test/src/pattern.dart';
import 'package:dart_arch_test/src/violation.dart';

/// A set of named bounded-context slices with explicit allowed cross-slice
/// dependencies.
class Slices {
  Slices._(this._slices, this._allowed);

  /// `{ sliceName -> pattern }`.
  final Map<String, String> _slices;

  /// Set of allowed `(from, to)` slice pairs.
  final Set<(String, String)> _allowed;

  /// Allows [fromSlice] to import libraries from [toSlice].
  Slices allowDependency(String fromSlice, String toSlice) {
    assert(_slices.containsKey(fromSlice), 'Unknown slice: $fromSlice');
    assert(_slices.containsKey(toSlice), 'Unknown slice: $toSlice');
    return Slices._(_slices, {..._allowed, (fromSlice, toSlice)});
  }

  /// Enforces that slices only cross-import according to
  /// [allowDependency] declarations.
  ///
  /// A slice may always import its own libraries. Only cross-slice imports are
  /// checked.
  void enforceIsolation(DependencyGraph graph) {
    final violations = <Violation>[];
    final sliceLibs = <String, Set<String>>{
      for (final entry in _slices.entries)
        entry.key: filesMatching(entry.value).resolve(graph),
    };

    final entries = sliceLibs.entries.map((e) => (e.key, e.value));
    for (final (fromSlice, fromLibs) in entries) {
      for (final (toSlice, toLibs) in entries) {
        if (fromSlice == toSlice) continue;
        if (_allowed.contains((fromSlice, toSlice))) continue;

        for (final lib in fromLibs) {
          for (final dep in Collector.dependenciesOf(graph, lib)) {
            if (toLibs.contains(dep)) {
              violations.add(
                Violation(
                  rule: 'enforceIsolation',
                  subject: lib,
                  dependency: dep,
                  message:
                      'slice "$fromSlice" must not import'
                      ' slice "$toSlice"',
                ),
              );
            }
          }
        }
      }
    }

    if (violations.isNotEmpty) throw ArchTestFailure(violations);
  }

  /// Asserts that slices have absolutely no cross-slice dependencies
  /// (strict isolation — ignores any [allowDependency] declarations).
  void shouldNotDependOnEachOther(DependencyGraph graph) {
    Slices._(_slices, {}).enforceIsolation(graph);
  }

  /// Asserts every library matched by [scope] belongs to at least one slice.
  ///
  /// Libraries whose URI matches any pattern in [except] are skipped.
  ///
  /// Throws [ArchTestFailure] listing uncovered libraries.
  void allLibrariesCoveredBy(
    LibrarySelector scope,
    DependencyGraph graph, {
    List<String> except = const [],
  }) {
    final scopeLibs = scope.resolve(graph);
    final sliceLibs = <String>{
      for (final pattern in _slices.values)
        ...filesMatching(pattern).resolve(graph),
    };

    final violations = <Violation>[];
    for (final lib in scopeLibs) {
      if (except.any((p) => matchesGlob(p, lib))) continue;
      if (!sliceLibs.contains(lib)) {
        violations.add(
          Violation(
            rule: 'allLibrariesCoveredBy',
            subject: lib,
            message: '$lib does not belong to any declared slice',
          ),
        );
      }
    }
    if (violations.isNotEmpty) throw ArchTestFailure(violations);
  }

  /// Returns dependency cycles between slices.
  ///
  /// Builds a slice-level dependency graph (slice → set of dep slices)
  /// and runs cycle detection on it.
  List<List<String>> sliceCycles(DependencyGraph graph) {
    final sliceLibs = <String, Set<String>>{
      for (final e in _slices.entries)
        e.key: filesMatching(e.value).resolve(graph),
    };

    final sliceGraph = <String, Set<String>>{};
    for (final fromEntry in sliceLibs.entries) {
      final fromSlice = fromEntry.key;
      final fromLibs = fromEntry.value;
      final depSlices = <String>{};
      for (final lib in fromLibs) {
        for (final dep in Collector.dependenciesOf(graph, lib)) {
          for (final toEntry in sliceLibs.entries) {
            final toSlice = toEntry.key;
            final toLibs = toEntry.value;
            if (toSlice != fromSlice && toLibs.contains(dep)) {
              depSlices.add(toSlice);
            }
          }
        }
      }
      sliceGraph[fromSlice] = depSlices;
    }

    return Collector.cycles(sliceGraph);
  }

  /// Asserts there are no cycles between slices.
  void shouldBeFreeOfSliceCycles(DependencyGraph graph) {
    final cycles = sliceCycles(graph);
    if (cycles.isEmpty) return;
    final violations = cycles
        .map(
          (c) => Violation(
            rule: 'shouldBeFreeOfSliceCycles',
            subject: c.first,
            message: 'slice cycle: ${c.join(' → ')}',
          ),
        )
        .toList();
    throw ArchTestFailure(violations);
  }
}

/// Defines bounded-context slices.
///
/// ```dart
/// defineSlices({
///   'home':     'features/home/**',
///   'discover': 'features/discover/**',
/// })
/// .allowDependency('home', 'auth')
/// .enforceIsolation(graph);
/// ```
Slices defineSlices(Map<String, String> sliceDefs) => Slices._(sliceDefs, {});
