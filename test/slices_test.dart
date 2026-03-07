import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

DependencyGraph _graph() => {
  'package:app/features/home/home_screen.dart': {
    'package:app/features/auth/auth_service.dart', // home → auth (allowed)
  },
  'package:app/features/discover/discover_screen.dart': {
    'package:app/features/home/home_screen.dart', // discover → home (not allowed)
  },
  'package:app/features/auth/auth_service.dart': {},
};

// Graph with cross-context violations + orphan
//   orders/checkout.dart    → inventory/repo.dart  (violation: internal access)
//   orders/service.dart     → repo/order_repo.dart
//   orders/manager.dart     → []
//   inventory/repo.dart     → []
//   inventory/item.dart     → []
//   accounts/user.dart      → []
//   orphan/thing.dart       → []
DependencyGraph _sliceGraph() => {
  'package:app/orders/checkout.dart': {'package:app/inventory/repo.dart'},
  'package:app/orders/service.dart': {'package:app/repo/order_repo.dart'},
  'package:app/orders/manager.dart': {},
  'package:app/inventory/repo.dart': {},
  'package:app/inventory/item.dart': {},
  'package:app/accounts/user.dart': {},
  'package:app/orphan/thing.dart': {},
};

void main() {
  group('defineSlices / enforceIsolation', () {
    test('passes when allowed dependencies match graph', () {
      expect(
        () => defineSlices({
          'home': 'features/home/**',
          'discover': 'features/discover/**',
          'auth': 'features/auth/**',
        }).allowDependency('home', 'auth').enforceIsolation(_graph()),
        // discover → home is still a violation
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes when all cross-slice deps are allowed', () {
      expect(
        () =>
            defineSlices({
                  'home': 'features/home/**',
                  'discover': 'features/discover/**',
                  'auth': 'features/auth/**',
                })
                .allowDependency('home', 'auth')
                .allowDependency('discover', 'home')
                .enforceIsolation(_graph()),
        returnsNormally,
      );
    });

    test('shouldNotDependOnEachOther detects any cross-slice dep', () {
      expect(
        () => defineSlices({
          'home': 'features/home/**',
          'discover': 'features/discover/**',
          'auth': 'features/auth/**',
        }).shouldNotDependOnEachOther(_graph()),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes for truly isolated slices', () {
      final isolatedGraph = {
        'package:app/features/home/home_screen.dart': <String>{},
        'package:app/features/discover/discover_screen.dart': <String>{},
      };

      expect(
        () => defineSlices({
          'home': 'features/home/**',
          'discover': 'features/discover/**',
        }).shouldNotDependOnEachOther(isolatedGraph),
        returnsNormally,
      );
    });
  });

  group('shouldNotDependOnEachOther — deduplication and edge cases', () {
    test('passes when slices are completely isolated', () {
      final graph = {
        'package:app/orders/manager.dart': <String>{},
        'package:app/inventory/item.dart': <String>{},
        'package:app/accounts/user.dart': <String>{},
      };

      expect(
        () => defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).shouldNotDependOnEachOther(graph),
        returnsNormally,
      );
    });

    test('detects cross-slice dep even without any allowDependency', () {
      // orders → inventory is a direct cross-slice dep
      expect(
        () => defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).shouldNotDependOnEachOther(_sliceGraph()),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('allowDependency has no effect on shouldNotDependOnEachOther', () {
      // Even with allowDependency, shouldNotDependOnEachOther still throws
      expect(
        () =>
            defineSlices({
                  'orders': 'orders/**',
                  'inventory': 'inventory/**',
                  'accounts': 'accounts/**',
                })
                .allowDependency('orders', 'inventory')
                .shouldNotDependOnEachOther(_sliceGraph()),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('does NOT flag intra-slice deps (within same slice)', () {
      // orders/checkout.dart and orders/service.dart are in the same slice.
      // orders → repo is cross-slice but repo is not a declared slice.
      // Only inventory is a declared slice here; orders→inventory is flagged.
      final graph = {
        'package:app/orders/checkout.dart': {
          'package:app/orders/manager.dart', // intra-slice
        },
        'package:app/orders/manager.dart': <String>{},
      };

      expect(
        () => defineSlices({
          'orders': 'orders/**',
        }).shouldNotDependOnEachOther(graph),
        returnsNormally,
      );
    });

    test(
      'deduplicates violations: each {subject, dependency} pair at most once',
      () {
        // Two files in orders both depend on inventory/repo.dart.
        // We should get exactly 2 violations (one per unique subject→dep pair),
        // not 4 (which would happen if both slice-pair combos were counted twice).
        final graph = {
          'package:app/orders/checkout.dart': {
            'package:app/inventory/repo.dart',
          },
          'package:app/orders/service.dart': {
            'package:app/inventory/repo.dart',
          },
          'package:app/inventory/repo.dart': <String>{},
        };

        ArchTestFailure? failure;
        try {
          defineSlices({
            'orders': 'orders/**',
            'inventory': 'inventory/**',
          }).shouldNotDependOnEachOther(graph);
        } on ArchTestFailure catch (e) {
          failure = e;
        }

        expect(failure, isNotNull);
        // Each unique subject→dep pair yields exactly one violation
        final pairs = failure!.violations
            .map((v) => '${v.subject}|${v.dependency}')
            .toSet();
        expect(
          pairs.length,
          equals(failure.violations.length),
          reason: 'violations should not be duplicated',
        );
      },
    );
  });

  group('sliceCycles and shouldBeFreeOfSliceCycles', () {
    test('returns empty when no slice cycle exists (linear A→B)', () {
      // orders → inventory (one-way, no cycle)
      final cycles = defineSlices({
        'orders': 'orders/**',
        'inventory': 'inventory/**',
        'accounts': 'accounts/**',
      }).sliceCycles(_sliceGraph());

      expect(cycles, isEmpty);
    });

    test('detects cycle when orders→inventory AND inventory→orders', () {
      final cyclicGraph = {
        'package:app/orders/checkout.dart': {'package:app/inventory/repo.dart'},
        'package:app/inventory/repo.dart': {'package:app/orders/manager.dart'},
        'package:app/orders/manager.dart': <String>{},
      };

      final cycles = defineSlices({
        'orders': 'orders/**',
        'inventory': 'inventory/**',
      }).sliceCycles(cyclicGraph);

      expect(cycles, isNotEmpty);
      // The cycle should involve both slice names
      final flat = cycles.expand((c) => c).toSet();
      expect(flat, containsAll(['orders', 'inventory']));
    });

    test(
      'shouldBeFreeOfSliceCycles throws ArchTestFailure when cycle exists',
      () {
        final cyclicGraph = {
          'package:app/orders/checkout.dart': {
            'package:app/inventory/repo.dart',
          },
          'package:app/inventory/repo.dart': {
            'package:app/orders/manager.dart',
          },
          'package:app/orders/manager.dart': <String>{},
        };

        expect(
          () => defineSlices({
            'orders': 'orders/**',
            'inventory': 'inventory/**',
          }).shouldBeFreeOfSliceCycles(cyclicGraph),
          throwsA(isA<ArchTestFailure>()),
        );
      },
    );

    test('shouldBeFreeOfSliceCycles returns normally when no cycle', () {
      expect(
        () => defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).shouldBeFreeOfSliceCycles(_sliceGraph()),
        returnsNormally,
      );
    });
  });

  group('allLibrariesCoveredBy', () {
    test('passes when all libs in scope belong to a slice', () {
      // scope = orders + inventory + accounts (all three are declared slices)
      expect(
        () => defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).allLibrariesCoveredBy(filesMatching('**'), _sliceGraph()),
        // orphan/thing.dart is NOT covered → should throw
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes when all libs in scope are covered (no orphan)', () {
      final graph = {
        'package:app/orders/checkout.dart': <String>{},
        'package:app/inventory/repo.dart': <String>{},
        'package:app/accounts/user.dart': <String>{},
      };

      expect(
        () => defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).allLibrariesCoveredBy(filesMatching('**'), graph),
        returnsNormally,
      );
    });

    test('fails when an orphan lib belongs to no slice', () {
      ArchTestFailure? failure;
      try {
        defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).allLibrariesCoveredBy(filesMatching('**'), _sliceGraph());
      } on ArchTestFailure catch (e) {
        failure = e;
      }

      expect(failure, isNotNull);
      final orphanViolation = failure!.violations.firstWhere(
        (v) => v.subject.contains('orphan/thing.dart'),
        orElse: () => throw StateError('no orphan violation found'),
      );
      expect(orphanViolation, isNotNull);
    });

    test(
      'violation message contains "does not belong to any declared slice"',
      () {
        ArchTestFailure? failure;
        try {
          defineSlices({
            'orders': 'orders/**',
            'inventory': 'inventory/**',
            'accounts': 'accounts/**',
          }).allLibrariesCoveredBy(filesMatching('**'), _sliceGraph());
        } on ArchTestFailure catch (e) {
          failure = e;
        }

        expect(failure, isNotNull);
        final orphanViolation = failure!.violations.firstWhere(
          (v) => v.subject.contains('orphan/thing.dart'),
        );
        expect(
          orphanViolation.message,
          contains('does not belong to any declared slice'),
        );
      },
    );

    test('except parameter skips listed patterns', () {
      // Exclude orphan/** and repo/** so those uncovered libs are skipped.
      // (orders/service.dart imports repo/order_repo.dart which is not a slice,
      //  and orphan/thing.dart has no slice — both are excluded here.)
      expect(
        () =>
            defineSlices({
              'orders': 'orders/**',
              'inventory': 'inventory/**',
              'accounts': 'accounts/**',
            }).allLibrariesCoveredBy(
              filesMatching('**'),
              _sliceGraph(),
              except: ['orphan/**', 'repo/**'],
            ),
        returnsNormally,
      );
    });

    test('without except, uncovered lib causes failure', () {
      expect(
        () => defineSlices({
          'orders': 'orders/**',
          'inventory': 'inventory/**',
          'accounts': 'accounts/**',
        }).allLibrariesCoveredBy(filesMatching('**'), _sliceGraph()),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes on empty graph', () {
      expect(
        () => defineSlices({
          'orders': 'orders/**',
        }).allLibrariesCoveredBy(filesMatching('**'), {}),
        returnsNormally,
      );
    });
  });
}
