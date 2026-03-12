import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

// In-memory graph for unit tests (no disk I/O needed for collector logic)
DependencyGraph _graph() => {
  'package:app/a.dart': {'package:app/b.dart', 'package:app/c.dart'},
  'package:app/b.dart': {'package:app/c.dart'},
  'package:app/c.dart': {},
};

void main() {
  group('Collector helpers', () {
    late DependencyGraph graph;

    setUp(() => graph = _graph());

    test('allLibraries returns all nodes', () {
      final all = Collector.allLibraries(graph);
      expect(
        all,
        containsAll([
          'package:app/a.dart',
          'package:app/b.dart',
          'package:app/c.dart',
        ]),
      );
    });

    test('dependenciesOf returns direct imports', () {
      expect(
        Collector.dependenciesOf(graph, 'package:app/a.dart'),
        containsAll(['package:app/b.dart', 'package:app/c.dart']),
      );
    });

    test('dependenciesOf returns empty for leaf node', () {
      expect(Collector.dependenciesOf(graph, 'package:app/c.dart'), isEmpty);
    });

    test('dependentsOf returns callers', () {
      expect(
        Collector.dependentsOf(graph, 'package:app/c.dart'),
        containsAll(['package:app/a.dart', 'package:app/b.dart']),
      );
    });

    test('dependentsOf returns empty for module nobody calls', () {
      expect(Collector.dependentsOf(graph, 'package:app/a.dart'), isEmpty);
    });

    test('dependenciesOf returns empty for unknown library', () {
      expect(
        Collector.dependenciesOf(graph, 'package:app/unknown.dart'),
        isEmpty,
      );
    });

    test('transitiveDependenciesOf follows chain', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        'package:app/a.dart',
      );
      expect(
        transitive,
        containsAll(['package:app/b.dart', 'package:app/c.dart']),
      );
      expect(transitive, isNot(contains('package:app/a.dart')));
    });

    test('transitiveDependenciesOf respects maxDepth=1', () {
      // a→b, a→c at depth 1; b→c at depth 2
      // maxDepth=1 from a should return only b and c (direct deps)
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        'package:app/a.dart',
        maxDepth: 1,
      );
      expect(
        transitive,
        containsAll(['package:app/b.dart', 'package:app/c.dart']),
      );
    });

    test('transitiveDependenciesOf maxDepth=0 returns empty', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        'package:app/a.dart',
        maxDepth: 0,
      );
      expect(transitive, isEmpty);
    });

    test('transitiveDependenciesOf excludes start node from result', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        'package:app/a.dart',
      );
      expect(transitive, isNot(contains('package:app/a.dart')));
    });

    test('transitiveDependenciesOf returns empty for unknown library', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        'package:app/nonexistent.dart',
      );
      expect(transitive, isEmpty);
    });

    test('transitiveDependenciesOf handles cycles without infinite loop', () {
      // Add cycle: c → a, making a→b→c→a
      graph['package:app/c.dart'] = {'package:app/a.dart'};
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        'package:app/a.dart',
      );
      expect(transitive, contains('package:app/b.dart'));
      expect(transitive, contains('package:app/c.dart'));
      expect(transitive, isNot(contains('package:app/a.dart')));
    });

    group('cycles', () {
      test('returns empty for acyclic graph', () {
        expect(Collector.cycles(graph), isEmpty);
      });

      test('returns empty for empty graph', () {
        expect(Collector.cycles({}), isEmpty);
      });

      test('returns empty for graph with only isolated nodes', () {
        final g = {
          'package:app/a.dart': <String>{},
          'package:app/b.dart': <String>{},
        };
        expect(Collector.cycles(g), isEmpty);
      });

      test('detects 3-node cycle a→b→c→a', () {
        graph['package:app/c.dart'] = {'package:app/a.dart'};
        final cycles = Collector.cycles(graph);
        expect(cycles, isNotEmpty);
        final cycleUris = cycles.expand((c) => c).toSet();
        expect(
          cycleUris,
          containsAll([
            'package:app/a.dart',
            'package:app/b.dart',
            'package:app/c.dart',
          ]),
        );
        // 3-node cycle should have length 3
        expect(cycles.first.length, equals(3));
      });

      test('detects 2-node cycle a↔b', () {
        final g = {
          'package:app/a.dart': {'package:app/b.dart'},
          'package:app/b.dart': {'package:app/a.dart'},
        };
        final cycles = Collector.cycles(g);
        expect(cycles, hasLength(1));
        expect(cycles.first, hasLength(2));
        expect(
          cycles.first,
          containsAll(['package:app/a.dart', 'package:app/b.dart']),
        );
      });

      test('cycle is not reported twice (deduplication)', () {
        final g = {
          'package:app/a.dart': {'package:app/b.dart'},
          'package:app/b.dart': {'package:app/a.dart'},
        };
        expect(Collector.cycles(g), hasLength(1));
      });

      test('detects self-cycle', () {
        graph['package:app/b.dart'] = {'package:app/b.dart'};
        final cycles = Collector.cycles(graph);
        expect(cycles.any((c) => c.contains('package:app/b.dart')), isTrue);
      });

      test('self-cycle produces single-element cycle', () {
        final g = {
          'package:app/a.dart': {'package:app/a.dart'},
        };
        final cycles = Collector.cycles(g);
        expect(cycles, hasLength(1));
        expect(cycles.first, hasLength(1));
        expect(cycles.first.first, equals('package:app/a.dart'));
      });

      test('detects two disjoint cycles', () {
        final g = {
          'package:app/a.dart': {'package:app/b.dart'},
          'package:app/b.dart': {'package:app/a.dart'},
          'package:app/c.dart': {'package:app/d.dart'},
          'package:app/d.dart': {'package:app/c.dart'},
          'package:app/e.dart': <String>{},
        };
        final cycles = Collector.cycles(g);
        expect(cycles, hasLength(2));
        final allMods = cycles.expand((c) => c).toSet();
        expect(allMods, contains('package:app/a.dart'));
        expect(allMods, contains('package:app/c.dart'));
        expect(allMods, isNot(contains('package:app/e.dart')));
      });

      test('4-node cycle a→b→c→d→a', () {
        final g = {
          'package:app/a.dart': {'package:app/b.dart'},
          'package:app/b.dart': {'package:app/c.dart'},
          'package:app/c.dart': {'package:app/d.dart'},
          'package:app/d.dart': {'package:app/a.dart'},
        };
        final cycles = Collector.cycles(g);
        expect(cycles, hasLength(1));
        expect(cycles.first, hasLength(4));
      });

      test('acyclic nodes are not included in cycle results', () {
        // Add acyclic branch alongside cyclic
        final g = {
          'package:app/a.dart': {'package:app/b.dart'},
          'package:app/b.dart': {'package:app/a.dart'},
          'package:app/c.dart': {'package:app/d.dart'},
          'package:app/d.dart': <String>{},
        };
        final cycles = Collector.cycles(g);
        final allMods = cycles.expand((c) => c).toSet();
        expect(allMods, isNot(contains('package:app/c.dart')));
        expect(allMods, isNot(contains('package:app/d.dart')));
      });

      test(
        'diamond graph (multiple paths to same node) — no spurious cycles',
        () {
          // a→b, a→c, b→d, c→d: diamond shape, no cycles
          final g = {
            'package:app/a.dart': {'package:app/b.dart', 'package:app/c.dart'},
            'package:app/b.dart': {'package:app/d.dart'},
            'package:app/c.dart': {'package:app/d.dart'},
            'package:app/d.dart': <String>{},
          };
          expect(Collector.cycles(g), isEmpty);
        },
      );

      test('diamond graph with back edge detects exactly one cycle', () {
        // a→b, a→c, b→d, c→d, d→a: one cycle a→b→d→a and a→c→d→a
        // but these share the same canonical cycle after normalization
        final g = {
          'package:app/a.dart': {'package:app/b.dart', 'package:app/c.dart'},
          'package:app/b.dart': {'package:app/d.dart'},
          'package:app/c.dart': {'package:app/d.dart'},
          'package:app/d.dart': {'package:app/a.dart'},
        };
        final cycles = Collector.cycles(g);
        // All nodes are part of cycles; at least one cycle must be reported
        expect(cycles, isNotEmpty);
        final allInCycles = cycles.expand((c) => c).toSet();
        expect(allInCycles, contains('package:app/a.dart'));
        expect(allInCycles, contains('package:app/d.dart'));
      });

      test('fan-out graph with shared leaf — completes without timeout', () {
        // Simulate a large fan-out to verify global visited prevents
        // O(n!) work.
        // Root imports 20 intermediates, all importing same leaf.
        const n = 20;
        final g = <String, Set<String>>{};
        const leaf = 'package:app/leaf.dart';
        g[leaf] = {};
        final intermediates = List.generate(n, (i) => 'package:app/m$i.dart');
        for (final m in intermediates) {
          g[m] = {leaf};
        }
        g['package:app/root.dart'] = intermediates.toSet();

        // Without global visited this would explore leaf 20 times (exponential
        // with more levels); with the fix it explores each node exactly once.
        final cycles = Collector.cycles(g);
        expect(cycles, isEmpty);
      });
    });
  });
}
