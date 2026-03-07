/// Martin coupling and stability metrics for Dart library dependency graphs.
///
/// Mirrors the `ArchTest.Metrics` module from the Elixir arch_test library.
library;

import 'package:dart_arch_test/src/collector.dart';
import 'package:dart_arch_test/src/library_set.dart';

/// Coupling metrics for a single library, following Robert C. Martin's
/// stability/abstractness model.
class CouplingMetrics {
  /// Creates a [CouplingMetrics] with the given coupling values.
  const CouplingMetrics({
    required this.afferent,
    required this.efferent,
    required this.instability,
    required this.abstractness,
    required this.distance,
  });

  /// Afferent coupling (Ca): number of libraries in the graph that depend ON
  /// this library.
  final int afferent;

  /// Efferent coupling (Ce): number of in-graph libraries that this library
  /// depends ON.
  final int efferent;

  /// Instability: Ce / (Ca + Ce).  0.0 when Ca + Ce == 0.
  final double instability;

  /// Abstractness: always 0.0 for Dart (no BEAM-level abstract type
  /// detection available at static-analysis time).
  final double abstractness;

  /// Distance from the main sequence: |abstractness + instability - 1|.
  final double distance;

  @override
  String toString() =>
      'CouplingMetrics(Ca=$afferent, Ce=$efferent, '
      'I=${instability.toStringAsFixed(3)}, '
      'A=${abstractness.toStringAsFixed(3)}, '
      'D=${distance.toStringAsFixed(3)})';
}

/// Static helpers for computing Martin coupling metrics over a
/// [DependencyGraph].
class Metrics {
  Metrics._();

  // ── public API ────────────────────────────────────────────────────────────

  /// Returns [CouplingMetrics] for the single library identified by
  /// [libraryUri].
  ///
  /// - **Ca (afferent)**: how many graph keys have [libraryUri] in their
  ///   dependency set.
  /// - **Ce (efferent)**: how many of [libraryUri]'s own dependencies are
  ///   themselves graph keys (i.e., in-project libraries).
  static CouplingMetrics coupling(String libraryUri, DependencyGraph graph) {
    final ca = _afferent(libraryUri, graph);
    final ce = _efferent(libraryUri, graph);
    return _build(ca, ce);
  }

  /// Convenience shorthand — returns only the instability value for
  /// [libraryUri].
  static double instability(String libraryUri, DependencyGraph graph) =>
      coupling(libraryUri, graph).instability;

  /// Returns a `Map<String, CouplingMetrics>` for every library whose URI
  /// matches [pattern] (resolved against [graph]).
  ///
  /// Uses [filesMatching] → `resolve(graph)` to select the target libraries,
  /// then computes [coupling] for each one using the **full** [graph] as the
  /// universe (so Ca/Ce counts are relative to all libraries, not just the
  /// subset).
  ///
  /// An empty [graph] or a [pattern] that matches nothing returns `{}`.
  static Map<String, CouplingMetrics> martin(
    String pattern,
    DependencyGraph graph,
  ) {
    if (graph.isEmpty) return {};
    final selected = filesMatching(pattern).resolve(graph);
    return {for (final uri in selected) uri: coupling(uri, graph)};
  }

  // ── private helpers ───────────────────────────────────────────────────────

  static int _afferent(String libraryUri, DependencyGraph graph) {
    var count = 0;
    for (final deps in graph.values) {
      if (deps.contains(libraryUri)) count++;
    }
    return count;
  }

  static int _efferent(String libraryUri, DependencyGraph graph) {
    final deps = graph[libraryUri];
    if (deps == null) return 0;
    // Only count deps that are themselves graph keys (in-project).
    return deps.where(graph.containsKey).length;
  }

  static CouplingMetrics _build(int ca, int ce) {
    final total = ca + ce;
    final i = total == 0 ? 0.0 : ce / total;
    const a = 0.0; // Dart has no BEAM abstract type detection
    final d = (a + i - 1.0).abs();
    return CouplingMetrics(
      afferent: ca,
      efferent: ce,
      instability: i,
      abstractness: a,
      distance: d,
    );
  }
}
