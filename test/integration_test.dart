// @Tags(['integration'])
import 'dart:io';

import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late DependencyGraph graph;

  setUpAll(() async {
    // dart test runs from the package root (directory containing pubspec.yaml).
    // Platform.script under dart test points to a generated runner, not the
    // test file itself, so we use Directory.current (= package root) instead.
    final fixturePath = p.join(Directory.current.path, 'test', 'fixture_app');
    graph = await Collector.buildGraph(fixturePath, force: true);
    Collector.clearCache();
  });

  // Convenience helpers
  String uri(String path) => 'package:fixture_app/$path';

  // ── Group 1: Collector.buildGraph against real files ─────────────────────

  group('Collector.buildGraph against real files', () {
    test('graph is not empty', () {
      expect(graph, isNotEmpty);
    });

    test('all 8 expected fixture libraries are present as graph keys', () {
      final expected = [
        uri('features/home/home_screen.dart'),
        uri('features/home/home_provider.dart'),
        uri('features/auth/auth_screen.dart'),
        uri('features/auth/auth_service.dart'),
        uri('domain/home_model.dart'),
        uri('data/home_repository.dart'),
        uri('domain/cycle_a.dart'),
        uri('domain/cycle_b.dart'),
      ];
      for (final lib in expected) {
        expect(graph.keys, contains(lib), reason: '$lib should be in graph');
      }
    });

    test('home_provider depends on auth_service (direct)', () {
      final deps = Collector.dependenciesOf(
        graph,
        uri('features/home/home_provider.dart'),
      );
      expect(deps, contains(uri('features/auth/auth_service.dart')));
    });

    test('home_provider depends on domain/home_model (direct)', () {
      final deps = Collector.dependenciesOf(
        graph,
        uri('features/home/home_provider.dart'),
      );
      expect(deps, contains(uri('domain/home_model.dart')));
    });

    test(
      'domain/home_model depends on data/home_repository (onion violation)',
      () {
        final deps = Collector.dependenciesOf(
          graph,
          uri('domain/home_model.dart'),
        );
        expect(deps, contains(uri('data/home_repository.dart')));
      },
    );

    test('domain/cycle_a depends on domain/cycle_b', () {
      final deps = Collector.dependenciesOf(graph, uri('domain/cycle_a.dart'));
      expect(deps, contains(uri('domain/cycle_b.dart')));
    });

    test('domain/cycle_b depends on domain/cycle_a', () {
      final deps = Collector.dependenciesOf(graph, uri('domain/cycle_b.dart'));
      expect(deps, contains(uri('domain/cycle_a.dart')));
    });

    test('data/home_repository has no fixture deps (leaf node)', () {
      final deps = Collector.dependenciesOf(
        graph,
        uri('data/home_repository.dart'),
      );
      final fixtureDeps = deps.where(
        (d) => d.startsWith('package:fixture_app/'),
      );
      expect(fixtureDeps, isEmpty);
    });

    test('dependentsOf finds home_provider as caller of auth_service', () {
      final callers = Collector.dependentsOf(
        graph,
        uri('features/auth/auth_service.dart'),
      );
      expect(callers, contains(uri('features/home/home_provider.dart')));
    });
  });

  // ── Group 2: Collector.transitiveDependenciesOf ───────────────────────────

  group('Collector.transitiveDependenciesOf on real graph', () {
    test('home_screen transitively reaches auth_service', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        uri('features/home/home_screen.dart'),
      );
      expect(transitive, contains(uri('features/auth/auth_service.dart')));
    });

    test('home_screen transitively reaches data/home_repository', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        uri('features/home/home_screen.dart'),
      );
      expect(transitive, contains(uri('data/home_repository.dart')));
    });

    test('data/home_repository has no transitive fixture deps', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        uri('data/home_repository.dart'),
      );
      final fixtureDeps = transitive.where(
        (d) => d.startsWith('package:fixture_app/'),
      );
      expect(fixtureDeps, isEmpty);
    });

    test('cycle_a transitively reaches cycle_b (does not hang)', () {
      final transitive = Collector.transitiveDependenciesOf(
        graph,
        uri('domain/cycle_a.dart'),
      );
      expect(transitive, contains(uri('domain/cycle_b.dart')));
    });
  });

  // ── Group 3: Collector.cycles on real graph ───────────────────────────────

  group('Collector.cycles on real graph', () {
    test('detects cycle_a ↔ cycle_b cycle', () {
      final allCycles = Collector.cycles(graph);
      expect(allCycles, isNotEmpty);
    });

    test('cycle nodes include cycle_a or cycle_b', () {
      final allCycles = Collector.cycles(graph);
      final cycleNodes = allCycles.expand((c) => c).toSet();
      final hasCycleNode =
          cycleNodes.contains(uri('domain/cycle_a.dart')) ||
          cycleNodes.contains(uri('domain/cycle_b.dart'));
      expect(hasCycleNode, isTrue);
    });

    test('acyclic subset (features/**) has no cycles', () {
      final featureUris = filesMatching('features/**').resolve(graph);
      final subGraph = <String, Set<String>>{
        for (final lib in featureUris)
          lib: (graph[lib] ?? {}).where(featureUris.contains).toSet(),
      };
      final featureCycles = Collector.cycles(subGraph);
      expect(featureCycles, isEmpty);
    });
  });

  // ── Group 4: LibrarySet resolution against real graph ────────────────────

  group('LibrarySet resolution against real graph', () {
    test(
      "filesMatching('features/home/**') matches home_screen and home_provider",
      () {
        final matched = filesMatching('features/home/**').resolve(graph);
        expect(matched, contains(uri('features/home/home_screen.dart')));
        expect(matched, contains(uri('features/home/home_provider.dart')));
        expect(matched.length, equals(2));
      },
    );

    test("filesMatching('features/**') matches all 4 feature files", () {
      final matched = filesMatching('features/**').resolve(graph);
      expect(matched, contains(uri('features/home/home_screen.dart')));
      expect(matched, contains(uri('features/home/home_provider.dart')));
      expect(matched, contains(uri('features/auth/auth_screen.dart')));
      expect(matched, contains(uri('features/auth/auth_service.dart')));
      expect(matched.length, equals(4));
    });

    test("filesMatching('data/**') matches home_repository", () {
      final matched = filesMatching('data/**').resolve(graph);
      expect(matched, contains(uri('data/home_repository.dart')));
    });

    test(
      "filesMatching('**/*_screen.dart') matches home_screen and auth_screen",
      () {
        final matched = filesMatching('**/*_screen.dart').resolve(graph);
        expect(matched, contains(uri('features/home/home_screen.dart')));
        expect(matched, contains(uri('features/auth/auth_screen.dart')));
      },
    );

    test(
      "filesMatching('features/**').excluding('features/auth/**') excludes auth files",
      () {
        final matched = filesMatching(
          'features/**',
        ).excluding('features/auth/**').resolve(graph);
        expect(matched, contains(uri('features/home/home_screen.dart')));
        expect(matched, contains(uri('features/home/home_provider.dart')));
        expect(matched, isNot(contains(uri('features/auth/auth_screen.dart'))));
        expect(
          matched,
          isNot(contains(uri('features/auth/auth_service.dart'))),
        );
      },
    );

    test(
      "union(filesMatching('features/auth/**'), filesMatching('data/**')) combines both",
      () {
        final combined = union(
          filesMatching('features/auth/**'),
          filesMatching('data/**'),
        ).resolve(graph);
        expect(combined, contains(uri('features/auth/auth_screen.dart')));
        expect(combined, contains(uri('features/auth/auth_service.dart')));
        expect(combined, contains(uri('data/home_repository.dart')));
      },
    );
  });

  // ── Group 5: assertions that PASS on real graph ───────────────────────────

  group('assertions that PASS on real graph', () {
    test('auth does not import home', () {
      expect(
        () => shouldNotDependOn(
          filesMatching('features/auth/**'),
          filesMatching('features/home/**'),
          graph,
        ),
        returnsNormally,
      );
    });

    test('data does not import features', () {
      expect(
        () => shouldNotDependOn(
          filesMatching('data/**'),
          filesMatching('features/**'),
          graph,
        ),
        returnsNormally,
      );
    });

    test('features are acyclic', () {
      expect(
        () => shouldBeFreeOfCycles(filesMatching('features/**'), graph),
        returnsNormally,
      );
    });

    test('auth does not transitively reach data', () {
      expect(
        () => shouldNotTransitivelyDependOn(
          filesMatching('features/auth/**'),
          filesMatching('data/**'),
          graph,
        ),
        returnsNormally,
      );
    });
  });

  // ── Group 6: assertions that FAIL (catching intentional violations) ────────

  group(
    'assertions that FAIL on real graph (catching intentional violations)',
    () {
      test('home imports auth_service — shouldNotDependOn throws', () {
        expect(
          () => shouldNotDependOn(
            filesMatching('features/home/**'),
            filesMatching('features/auth/**'),
            graph,
          ),
          throwsA(isA<ArchTestFailure>()),
        );
      });

      test('domain imports data — shouldNotDependOn throws', () {
        expect(
          () => shouldNotDependOn(
            filesMatching('domain/**'),
            filesMatching('data/**'),
            graph,
          ),
          throwsA(isA<ArchTestFailure>()),
        );
      });

      test('shouldBeFreeOfCycles on allFiles detects cycle_a ↔ cycle_b', () {
        expect(
          () => shouldBeFreeOfCycles(allFiles(), graph),
          throwsA(isA<ArchTestFailure>()),
        );
      });

      test(
        'home transitively reaches data — shouldNotTransitivelyDependOn throws',
        () {
          expect(
            () => shouldNotTransitivelyDependOn(
              filesMatching('features/home/**'),
              filesMatching('data/**'),
              graph,
            ),
            throwsA(isA<ArchTestFailure>()),
          );
        },
      );

      test(
        'shouldOnlyDependOn home/home — home_provider imports outside — throws',
        () {
          expect(
            () => shouldOnlyDependOn(
              filesMatching('features/home/**'),
              filesMatching('features/home/**'),
              graph,
            ),
            throwsA(isA<ArchTestFailure>()),
          );
        },
      );

      test('violation message contains actual library URIs', () {
        try {
          shouldNotDependOn(
            filesMatching('features/home/**'),
            filesMatching('features/auth/**'),
            graph,
          );
          fail('Expected ArchTestFailure');
        } on ArchTestFailure catch (e) {
          final msg = e.toString();
          expect(msg, contains('fixture_app'));
        }
      });

      test('violation count > 0 for multi-violation rules', () {
        try {
          shouldBeFreeOfCycles(allFiles(), graph);
          fail('Expected ArchTestFailure');
        } on ArchTestFailure catch (e) {
          expect(e.violations.length, greaterThan(0));
        }
      });
    },
  );

  // ── Group 7: Slices on real graph ─────────────────────────────────────────

  group('Slices on real graph', () {
    test(
      'enforceIsolation without allowDependency throws (home imports auth)',
      () {
        expect(
          () => defineSlices({
            'home': 'features/home/**',
            'auth': 'features/auth/**',
          }).enforceIsolation(graph),
          throwsA(isA<ArchTestFailure>()),
        );
      },
    );

    test('enforceIsolation with allowDependency home→auth passes', () {
      expect(
        () => defineSlices({
          'home': 'features/home/**',
          'auth': 'features/auth/**',
        }).allowDependency('home', 'auth').enforceIsolation(graph),
        returnsNormally,
      );
    });

    test('shouldBeFreeOfSliceCycles on acyclic slices passes', () {
      // home → auth (one direction only), no cycle at slice level
      expect(
        () => defineSlices({
          'home': 'features/home/**',
          'auth': 'features/auth/**',
        }).shouldBeFreeOfSliceCycles(graph),
        returnsNormally,
      );
    });
  });

  // ── Group 8: Layers on real graph ─────────────────────────────────────────

  group('Layers on real graph', () {
    test(
      'enforceDirection detects domain→data violation (inner imports outer)',
      () {
        // In top-to-bottom layered order: presentation > domain > data
        // domain is layer index 1; data is layer index 2 (below domain)
        // So domain importing data is ALLOWED by enforceDirection (downward)
        // Use enforceOnionRules to detect domain→data as inner-to-outer.
        expect(
          () => defineOnion({
            'domain': 'domain/**',
            'data': 'data/**',
          }).enforceOnionRules(graph),
          throwsA(isA<ArchTestFailure>()),
        );
      },
    );

    test(
      'features-only: home→auth same-layer cross-feature, direction passes',
      () {
        // Two layers: presentation and domain. home→auth within presentation.
        // domain→data is caught by onion (separate).
        // Presentation does not import domain here (no violation).
        // home_provider imports domain/home_model — layer below, allowed.
        expect(
          () => defineLayers({
            'presentation': 'features/**',
            'domain': 'domain/**',
          }).enforceDirection(graph),
          returnsNormally,
        );
      },
    );
  });

  // ── Group 9: Pattern matching edge cases on real URIs ─────────────────────

  group('Pattern matching edge cases on real URIs', () {
    test("matchesGlob('features/**', home_screen uri) → true", () {
      expect(
        matchesGlob(
          'features/**',
          uri('features/home/home_screen.dart'),
        ),
        isTrue,
      );
    });

    test("matchesGlob('features/home/**', home_provider uri) → true", () {
      expect(
        matchesGlob(
          'features/home/**',
          uri('features/home/home_provider.dart'),
        ),
        isTrue,
      );
    });

    test("matchesGlob('features/**', data uri) → false", () {
      expect(
        matchesGlob(
          'features/**',
          uri('data/home_repository.dart'),
        ),
        isFalse,
      );
    });

    test("matchesGlob('**/*_screen.dart', home_screen uri) → true", () {
      expect(
        matchesGlob(
          '**/*_screen.dart',
          uri('features/home/home_screen.dart'),
        ),
        isTrue,
      );
    });

    test("matchesGlob('**/*_screen.dart', home_provider uri) → false", () {
      expect(
        matchesGlob(
          '**/*_screen.dart',
          uri('features/home/home_provider.dart'),
        ),
        isFalse,
      );
    });
  });
}
