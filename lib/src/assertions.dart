/// Core assertion functions for architecture tests.
///
/// All functions collect [Violation]s and throw a [ArchTestFailure] if any
/// are found. Use inside `test(...)` blocks from the `test` package.
library;

import 'package:dart_arch_test/src/collector.dart';
import 'package:dart_arch_test/src/library_set.dart';
import 'package:dart_arch_test/src/violation.dart';

/// Thrown when one or more architecture violations are found.
class ArchTestFailure implements Exception {
  /// Creates an [ArchTestFailure] with the given [violations].
  const ArchTestFailure(this.violations);

  /// The list of violations that caused this failure.
  final List<Violation> violations;

  @override
  String toString() {
    final lines = violations.map((v) => '  $v').join('\n');
    return 'Architecture violations (${violations.length}):\n$lines';
  }
}

/// Asserts no library in [subject] directly imports any library in [object].
///
/// Pass [except] to exclude a subset of [subject] from the check.
///
/// ```dart
/// shouldNotDependOn(
///   filesMatching('features/home/**'),
///   filesMatching('features/discover/**'),
///   graph,
/// );
///
/// // Allow one file to cross the boundary
/// shouldNotDependOn(
///   filesMatching('shared/**'),
///   filesMatching('features/**'),
///   graph,
///   except: filesMatching('shared/guards/**'),
/// );
/// ```
void shouldNotDependOn(
  LibrarySelector subject,
  LibrarySelector object,
  DependencyGraph graph, {
  LibrarySelector? except,
}) {
  final objectUris = object.resolve(graph);
  final exceptUris = except?.resolve(graph) ?? const <String>{};
  final violations = <Violation>[];

  for (final lib in subject.resolve(graph)) {
    if (exceptUris.contains(lib)) continue;
    for (final dep in Collector.dependenciesOf(graph, lib)) {
      if (objectUris.contains(dep)) {
        violations.add(
          Violation(
            rule: 'shouldNotDependOn',
            subject: lib,
            dependency: dep,
            message: 'must not import $dep',
          ),
        );
      }
    }
  }

  _assertNone(violations);
}

/// Asserts libraries in [subject] only import libraries in [allowed]
/// (plus SDK and other out-of-scope libraries).
///
/// Pass [except] to exclude a subset of [subject] from the check.
void shouldOnlyDependOn(
  LibrarySelector subject,
  LibrarySelector allowed,
  DependencyGraph graph, {
  LibrarySelector? except,
}) {
  final allowedUris = allowed.resolve(graph);
  final subjectUris = subject.resolve(graph);
  final exceptUris = except?.resolve(graph) ?? const <String>{};
  final violations = <Violation>[];

  for (final lib in subjectUris) {
    if (exceptUris.contains(lib)) continue;
    for (final dep in Collector.dependenciesOf(graph, lib)) {
      // Only check deps that are in the graph (i.e., in the project)
      if (graph.containsKey(dep) &&
          !allowedUris.contains(dep) &&
          !subjectUris.contains(dep)) {
        violations.add(
          Violation(
            rule: 'shouldOnlyDependOn',
            subject: lib,
            dependency: dep,
            message: 'must not import $dep (not in allowed set)',
          ),
        );
      }
    }
  }

  _assertNone(violations);
}

/// Asserts that no library in [callers] directly imports any library in
/// [object].
///
/// Pass [except] to exclude a subset of [callers] from the check.
void shouldNotBeCalledBy(
  LibrarySelector object,
  LibrarySelector callers,
  DependencyGraph graph, {
  LibrarySelector? except,
}) => shouldNotDependOn(callers, object, graph, except: except);

/// Asserts that only libraries in [allowedCallers] import libraries in
/// [object].
///
/// Pass [except] to exclude a subset of [object] from the check.
void shouldOnlyBeCalledBy(
  LibrarySelector object,
  LibrarySelector allowedCallers,
  DependencyGraph graph, {
  LibrarySelector? except,
}) {
  final objectUris = object.resolve(graph);
  final allowedUris = allowedCallers.resolve(graph);
  final exceptUris = except?.resolve(graph) ?? const <String>{};
  final violations = <Violation>[];

  for (final lib in objectUris) {
    if (exceptUris.contains(lib)) continue;
    for (final caller in Collector.dependentsOf(graph, lib)) {
      if (!allowedUris.contains(caller)) {
        violations.add(
          Violation(
            rule: 'shouldOnlyBeCalledBy',
            subject: lib,
            dependency: caller,
            message: '$caller is not an allowed caller',
          ),
        );
      }
    }
  }

  _assertNone(violations);
}

/// Asserts no transitive dependency from [subject] to any library in [object].
///
/// Pass [except] to exclude a subset of [subject] from the check.
///
/// ```dart
/// // shared/services must not (even transitively) depend on shared/widgets
/// shouldNotTransitivelyDependOn(
///   filesMatching('shared/services/**'),
///   filesMatching('shared/widgets/**'),
///   graph,
/// );
///
/// // … but exclude one known bridge file
/// shouldNotTransitivelyDependOn(
///   filesMatching('shared/services/**'),
///   filesMatching('shared/widgets/**'),
///   graph,
///   except: filesMatching('shared/services/share_service.dart'),
/// );
/// ```
void shouldNotTransitivelyDependOn(
  LibrarySelector subject,
  LibrarySelector object,
  DependencyGraph graph, {
  LibrarySelector? except,
}) {
  final objectUris = object.resolve(graph);
  final exceptUris = except?.resolve(graph) ?? const <String>{};
  final violations = <Violation>[];

  for (final lib in subject.resolve(graph)) {
    if (exceptUris.contains(lib)) continue;
    final transitive = Collector.transitiveDependenciesOf(graph, lib);
    for (final dep in transitive) {
      if (objectUris.contains(dep)) {
        violations.add(
          Violation(
            rule: 'shouldNotTransitivelyDependOn',
            subject: lib,
            dependency: dep,
            message: 'transitively imports $dep',
          ),
        );
      }
    }
  }

  _assertNone(violations);
}

/// Asserts that no library matching [subject] exists in the graph.
void shouldNotExist(LibrarySelector subject, DependencyGraph graph) {
  final found = subject.resolve(graph);
  if (found.isEmpty) return;

  _assertNone(
    found
        .map(
          (lib) => Violation(
            rule: 'shouldNotExist',
            subject: lib,
            message: 'this library should not exist',
          ),
        )
        .toList(),
  );
}

/// Asserts no circular dependencies among libraries in [subject].
void shouldBeFreeOfCycles(LibrarySelector subject, DependencyGraph graph) {
  final subjectUris = subject.resolve(graph);

  // Build a subgraph containing only the selected libraries
  final subGraph = <String, Set<String>>{
    for (final lib in subjectUris)
      lib: (graph[lib] ?? {}).where(subjectUris.contains).toSet(),
  };

  final found = Collector.cycles(subGraph);
  if (found.isEmpty) return;

  _assertNone(
    found
        .map(
          (cycle) => Violation(
            rule: 'shouldBeFreeOfCycles',
            subject: cycle.first,
            message: 'cycle: ${cycle.join(' → ')}',
          ),
        )
        .toList(),
  );
}

/// Asserts all libraries in [subject] have URIs matching [pattern].
void shouldHaveUriMatching(
  LibrarySelector subject,
  String pattern,
  DependencyGraph graph,
) {
  final violations = <Violation>[];
  for (final lib in subject.resolve(graph)) {
    if (!_globMatch(pattern, lib)) {
      violations.add(
        Violation(
          rule: 'shouldHaveUriMatching',
          subject: lib,
          message: 'URI does not match pattern "$pattern"',
        ),
      );
    }
  }
  _assertNone(violations);
}

// ── internals ────────────────────────────────────────────────────────────────

void _assertNone(List<Violation> violations) {
  if (violations.isEmpty) return;
  throw ArchTestFailure(violations);
}

bool _globMatch(String pattern, String value) {
  // Delegate to the pattern module; import is added as a part import below.
  // We inline here to avoid circular imports.
  final escaped = RegExp.escape(
    pattern,
  ).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*');
  final regexStr = '^$escaped\$';
  return RegExp(regexStr).hasMatch(value);
}
