import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

//
// Graph layout:
//
//   home_screen      → home_provider
//   home_provider    → home_repo (data layer)
//   discover_screen  → discover_provider
//   discover_provider→ home_repo  (cross-feature dep — violation)
//   auth_screen      → (no deps)
//   home_repo        → (no deps)
//
DependencyGraph _buildGraph() => {
  'package:app/features/home/home_screen.dart': {
    'package:app/features/home/home_provider.dart',
  },
  'package:app/features/home/home_provider.dart': {
    'package:app/data/home_repo.dart',
  },
  'package:app/features/discover/discover_screen.dart': {
    'package:app/features/discover/discover_provider.dart',
  },
  'package:app/features/discover/discover_provider.dart': {
    'package:app/data/home_repo.dart',
  },
  'package:app/features/auth/auth_screen.dart': <String>{},
  'package:app/data/home_repo.dart': <String>{},
};

void main() {
  late DependencyGraph graph;
  setUp(() => graph = _buildGraph());

  // ── shouldNotDependOn ────────────────────────────────────────────────────

  group('shouldNotDependOn', () {
    test('passes when there is no dependency', () {
      expect(
        () => shouldNotDependOn(
          filesMatching('features/auth/**'),
          filesMatching('features/home/**'),
          graph,
        ),
        returnsNormally,
      );
    });

    test('fails when direct dependency exists', () {
      expect(
        () => shouldNotDependOn(
          filesMatching('features/home/**'),
          filesMatching('data/**'),
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('collects all violations before throwing', () {
      try {
        shouldNotDependOn(
          filesMatching('features/**'),
          filesMatching('data/**'),
          graph,
        );
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        // Both home_provider and discover_provider import home_repo
        expect(e.violations.length, greaterThanOrEqualTo(2));
      }
    });

    test('violation names the forbidden dependency', () {
      try {
        shouldNotDependOn(
          filesMatching('features/home/**'),
          filesMatching('data/**'),
          graph,
        );
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(
          e.violations.any(
            (v) => v.dependency == 'package:app/data/home_repo.dart',
          ),
          isTrue,
        );
        expect(
          e.violations.every((v) => v.rule == 'shouldNotDependOn'),
          isTrue,
        );
      }
    });

    test('passes on empty graph', () {
      expect(
        () => shouldNotDependOn(
          filesMatching('features/**'),
          filesMatching('data/**'),
          {},
        ),
        returnsNormally,
      );
    });

    test('passes when subject pattern matches nothing', () {
      expect(
        () => shouldNotDependOn(
          filesMatching('legacy/**'),
          filesMatching('data/**'),
          graph,
        ),
        returnsNormally,
      );
    });
  });

  // ── shouldOnlyDependOn ───────────────────────────────────────────────────

  group('shouldOnlyDependOn', () {
    test('passes when all deps are in allowed set', () {
      // home_screen only imports home_provider — both in features/home/**
      expect(
        () => shouldOnlyDependOn(
          filesMatching('features/home/home_screen.dart'),
          filesMatching('features/home/**'),
          graph,
        ),
        returnsNormally,
      );
    });

    test('fails when a dep is outside the allowed set', () {
      // home_provider imports data/home_repo which is not in features/home/**
      expect(
        () => shouldOnlyDependOn(
          filesMatching('features/home/**'),
          filesMatching('features/home/**'),
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('out-of-graph (SDK) imports are not flagged', () {
      // Deps that don't appear as graph keys are treated as external (SDK etc.)
      final g = {
        'package:app/a.dart': {'dart:async'},
      };
      expect(
        () => shouldOnlyDependOn(
          filesMatching('**'),
          filesMatching('data/**'), // dart:async is not in data/**
          g,
        ),
        returnsNormally,
      );
    });
  });

  // ── shouldNotTransitivelyDependOn ────────────────────────────────────────

  group('shouldNotTransitivelyDependOn', () {
    test('detects transitive dep through two hops', () {
      // home_screen → home_provider → home_repo
      expect(
        () => shouldNotTransitivelyDependOn(
          filesMatching('features/home/home_screen.dart'),
          filesMatching('data/**'),
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes when no transitive path exists', () {
      expect(
        () => shouldNotTransitivelyDependOn(
          filesMatching('features/auth/**'),
          filesMatching('data/**'),
          graph,
        ),
        returnsNormally,
      );
    });

    test('passes on empty graph', () {
      expect(
        () => shouldNotTransitivelyDependOn(
          filesMatching('features/**'),
          filesMatching('data/**'),
          {},
        ),
        returnsNormally,
      );
    });
  });

  // ── shouldNotBeCalledBy ──────────────────────────────────────────────────

  group('shouldNotBeCalledBy', () {
    test('fails when forbidden caller imports the object', () {
      // home_provider imports home_repo — so home_provider is a caller
      expect(
        () => shouldNotBeCalledBy(
          filesMatching('data/**'),
          filesMatching('features/home/**'),
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes when no forbidden callers exist', () {
      expect(
        () => shouldNotBeCalledBy(
          filesMatching('data/**'),
          filesMatching('features/auth/**'),
          graph,
        ),
        returnsNormally,
      );
    });
  });

  // ── shouldOnlyBeCalledBy ─────────────────────────────────────────────────

  group('shouldOnlyBeCalledBy', () {
    test('passes when all callers are in the allowed set', () {
      // home_repo is only called by home_provider and discover_provider
      expect(
        () => shouldOnlyBeCalledBy(
          filesMatching('data/**'),
          filesMatching('features/**'),
          graph,
        ),
        returnsNormally,
      );
    });

    test('fails when an unlisted caller imports the object', () {
      // Allow only home — but discover also calls home_repo
      expect(
        () => shouldOnlyBeCalledBy(
          filesMatching('data/**'),
          filesMatching('features/home/**'),
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('violation identifies the unexpected caller', () {
      try {
        shouldOnlyBeCalledBy(
          filesMatching('data/**'),
          filesMatching('features/home/**'),
          graph,
        );
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(
          e.violations.any(
            (v) =>
                v.dependency ==
                'package:app/features/discover/discover_provider.dart',
          ),
          isTrue,
        );
      }
    });

    test('passes when object has no callers', () {
      expect(
        () => shouldOnlyBeCalledBy(
          filesMatching('features/auth/**'),
          filesMatching('features/home/**'),
          graph,
        ),
        returnsNormally,
      );
    });
  });

  // ── shouldNotExist ───────────────────────────────────────────────────────

  group('shouldNotExist', () {
    test('fails when matching libraries exist', () {
      expect(
        () => shouldNotExist(filesMatching('data/**'), graph),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes when pattern matches nothing', () {
      expect(
        () => shouldNotExist(filesMatching('legacy/**'), graph),
        returnsNormally,
      );
    });

    test('violation identifies the forbidden library', () {
      try {
        shouldNotExist(filesMatching('data/**'), graph);
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(
          e.violations.any(
            (v) => v.subject == 'package:app/data/home_repo.dart',
          ),
          isTrue,
        );
        expect(e.violations.every((v) => v.rule == 'shouldNotExist'), isTrue);
      }
    });
  });

  // ── shouldBeFreeOfCycles ─────────────────────────────────────────────────

  group('shouldBeFreeOfCycles', () {
    test('passes on acyclic graph', () {
      expect(() => shouldBeFreeOfCycles(allFiles(), graph), returnsNormally);
    });

    test('fails when a 2-node cycle exists', () {
      graph['package:app/data/home_repo.dart'] = {
        'package:app/features/home/home_screen.dart',
      };
      expect(
        () => shouldBeFreeOfCycles(allFiles(), graph),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('violation message contains the cycle path', () {
      graph['package:app/data/home_repo.dart'] = {
        'package:app/features/home/home_screen.dart',
      };
      try {
        shouldBeFreeOfCycles(allFiles(), graph);
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(e.violations.first.message, contains('→'));
        expect(e.violations.first.rule, 'shouldBeFreeOfCycles');
      }
    });

    test('only considers libraries matched by subject selector', () {
      // Add a cycle only in data/
      graph['package:app/data/home_repo.dart'] = {
        'package:app/data/other_repo.dart',
      };
      graph['package:app/data/other_repo.dart'] = {
        'package:app/data/home_repo.dart',
      };
      // Checking only features/ should not see the data/ cycle
      expect(
        () => shouldBeFreeOfCycles(filesMatching('features/**'), graph),
        returnsNormally,
      );
      // Checking all files should catch it
      expect(
        () => shouldBeFreeOfCycles(allFiles(), graph),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('passes on empty graph', () {
      expect(() => shouldBeFreeOfCycles(allFiles(), {}), returnsNormally);
    });
  });

  // ── shouldHaveUriMatching ────────────────────────────────────────────────

  group('shouldHaveUriMatching', () {
    test('passes when all URIs match pattern', () {
      expect(
        () => shouldHaveUriMatching(
          filesMatching('features/**'),
          'package:app/features/**',
          graph,
        ),
        returnsNormally,
      );
    });

    test('fails when a URI does not match pattern', () {
      // data/ is not under features/
      expect(
        () => shouldHaveUriMatching(
          allFiles(),
          'package:app/features/**',
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test(
      'pattern without package prefix is normalized and matches correctly',
      () {
        // Real usage: enforce _screen.dart naming without specifying package
        // name
        expect(
          () => shouldHaveUriMatching(
            filesMatching('features/**/*_screen.dart'),
            '**/*_screen.dart',
            graph,
          ),
          returnsNormally,
        );
      },
    );

    test('pattern without package prefix rejects non-matching URI', () {
      // auth_screen.dart exists; home_provider.dart does NOT end in
      // _screen.dart
      expect(
        () => shouldHaveUriMatching(
          filesMatching('features/**'),
          '**/*_screen.dart',
          graph,
        ),
        throwsA(isA<ArchTestFailure>()),
      );
    });
  });
}
