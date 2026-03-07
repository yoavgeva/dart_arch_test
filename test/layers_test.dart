import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

DependencyGraph _goodGraph() => {
  'package:app/features/home/home_screen.dart': {
    'package:app/domain/home_model.dart',
  },
  'package:app/domain/home_model.dart': {
    'package:app/data/home_repo.dart',
  },
  'package:app/data/home_repo.dart': {},
};

DependencyGraph _badGraph() => {
  // data imports domain — upward dependency (violation)
  'package:app/data/home_repo.dart': {
    'package:app/features/home/home_screen.dart',
  },
  'package:app/features/home/home_screen.dart': {},
  'package:app/domain/home_model.dart': {},
};

void main() {
  group('defineLayers / enforceDirection', () {
    test('passes for valid layered graph', () {
      expect(
        () => defineLayers({
          'presentation': 'features/**',
          'domain': 'domain/**',
          'data': 'data/**',
        }).enforceDirection(_goodGraph()),
        returnsNormally,
      );
    });

    test('fails when lower layer imports upper layer', () {
      expect(
        () => defineLayers({
          'presentation': 'features/**',
          'domain': 'domain/**',
          'data': 'data/**',
        }).enforceDirection(_badGraph()),
        throwsA(isA<ArchTestFailure>()),
      );
    });
  });

  group('defineLayers / enforceDirection — edge cases', () {
    test('single-layer architecture never has violations', () {
      final g = {
        'package:app/features/home.dart': {
          'package:app/features/auth.dart',
        },
        'package:app/features/auth.dart': <String>{},
      };
      expect(
        () => defineLayers({'features': 'features/**'}).enforceDirection(g),
        returnsNormally,
      );
    });

    test('no violations when layers have no cross-deps', () {
      final g = {
        'package:app/features/home.dart': <String>{},
        'package:app/data/repo.dart': <String>{},
      };
      expect(
        () => defineLayers({
          'presentation': 'features/**',
          'data': 'data/**',
        }).enforceDirection(g),
        returnsNormally,
      );
    });

    test('multiple upward violations are all reported', () {
      final g = {
        'package:app/features/home.dart': <String>{},
        'package:app/data/repo_a.dart': {
          'package:app/features/home.dart',
        },
        'package:app/data/repo_b.dart': {
          'package:app/features/home.dart',
        },
      };
      try {
        defineLayers({
          'presentation': 'features/**',
          'data': 'data/**',
        }).enforceDirection(g);
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(e.violations.length, equals(2));
      }
    });

    test('4-layer architecture catches all upward violations', () {
      final g = {
        'package:app/web/controller.dart': {
          'package:app/context/orders.dart',
        },
        'package:app/context/orders.dart': {
          'package:app/service/order_service.dart',
        },
        'package:app/service/order_service.dart': {
          'package:app/repo/order_repo.dart',
        },
        // repo → web (3 layers up) and repo → context (2 layers up)
        'package:app/repo/order_repo.dart': {
          'package:app/web/controller.dart',
          'package:app/context/orders.dart',
        },
      };
      try {
        defineLayers({
          'web': 'web/**',
          'context': 'context/**',
          'service': 'service/**',
          'repo': 'repo/**',
        }).enforceDirection(g);
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        // repo → web and repo → context are both violations
        expect(
          e.violations.any(
            (v) =>
                v.subject.contains('repo') && v.dependency!.contains('web'),
          ),
          isTrue,
        );
        expect(
          e.violations.any(
            (v) =>
                v.subject.contains('repo') &&
                v.dependency!.contains('context'),
          ),
          isTrue,
        );
        // downward deps should NOT be violations
        expect(
          e.violations.any((v) => v.subject.contains('web')),
          isFalse,
        );
      }
    });

    test('empty graph produces no violations', () {
      expect(
        () => defineLayers({
          'presentation': 'features/**',
          'data': 'data/**',
        }).enforceDirection({}),
        returnsNormally,
      );
    });

    test('violation message contains layer names', () {
      try {
        defineLayers({
          'presentation': 'features/**',
          'data': 'data/**',
        }).enforceDirection(_badGraph());
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(
          e.violations.any(
            (v) =>
                v.message.contains('data') ||
                v.message.contains('presentation'),
          ),
          isTrue,
        );
      }
    });
  });

  group('defineOnion / enforceOnionRules', () {
    test('passes when inner layer does not import outer', () {
      final g = {
        'package:app/domain/home_model.dart': <String>{},
        'package:app/features/home/home_screen.dart': {
          'package:app/domain/home_model.dart',
        },
      };

      expect(
        () => defineOnion({
          'domain': 'domain/**',
          'presentation': 'features/**',
        }).enforceOnionRules(g),
        returnsNormally,
      );
    });

    test('fails when inner layer imports outer', () {
      final g = {
        'package:app/domain/home_model.dart': {
          'package:app/features/home/home_screen.dart',
        },
        'package:app/features/home/home_screen.dart': <String>{},
      };

      expect(
        () => defineOnion({
          'domain': 'domain/**',
          'presentation': 'features/**',
        }).enforceOnionRules(g),
        throwsA(isA<ArchTestFailure>()),
      );
    });

    test('outer calling inner is allowed (adapters → domain)', () {
      final g = {
        'package:app/domain/entity.dart': <String>{},
        'package:app/app/service.dart': {
          'package:app/domain/entity.dart',
        },
        'package:app/adapters/db.dart': {
          'package:app/app/service.dart',
          'package:app/domain/entity.dart',
        },
      };
      expect(
        () => defineOnion({
          'domain': 'domain/**',
          'application': 'app/**',
          'adapters': 'adapters/**',
        }).enforceOnionRules(g),
        returnsNormally,
      );
    });

    test('3-ring onion: only the outward violation is reported', () {
      final g = {
        'package:app/domain/entity.dart': <String>{},
        'package:app/domain/value_object.dart': <String>{},
        'package:app/app/use_case.dart': {
          'package:app/domain/entity.dart',
        },
        'package:app/adapters/http.dart': {
          'package:app/app/use_case.dart',
        },
        'package:app/adapters/repo.dart': {
          'package:app/domain/entity.dart',
        },
        // violation: domain depends on adapters
        'package:app/domain/bad_dep.dart': {
          'package:app/adapters/http.dart',
        },
      };
      try {
        defineOnion({
          'domain': 'domain/**',
          'application': 'app/**',
          'adapters': 'adapters/**',
        }).enforceOnionRules(g);
        fail('should have thrown');
      } on ArchTestFailure catch (e) {
        expect(e.violations.length, equals(1));
        expect(e.violations.first.subject, contains('bad_dep'));
      }
    });

    test('innermost cannot depend on outermost (onion direction test)', () {
      final g = {
        'package:app/domain/core.dart': {
          'package:app/adapters/api.dart',
        },
        'package:app/adapters/api.dart': <String>{},
      };
      expect(
        () => defineOnion({
          'domain': 'domain/**',
          'adapters': 'adapters/**',
        }).enforceOnionRules(g),
        throwsA(isA<ArchTestFailure>()),
      );

      // reverse: adapters → domain is allowed
      final g2 = {
        'package:app/domain/core.dart': <String>{},
        'package:app/adapters/api.dart': {
          'package:app/domain/core.dart',
        },
      };
      expect(
        () => defineOnion({
          'domain': 'domain/**',
          'adapters': 'adapters/**',
        }).enforceOnionRules(g2),
        returnsNormally,
      );
    });

    test('no violations in clean onion graph', () {
      final g = {
        'package:app/domain/core.dart': <String>{},
        'package:app/application/service.dart': {
          'package:app/domain/core.dart',
        },
        'package:app/adapters/controller.dart': {
          'package:app/application/service.dart',
        },
      };
      expect(
        () => defineOnion({
          'domain': 'domain/**',
          'application': 'application/**',
          'adapters': 'adapters/**',
        }).enforceOnionRules(g),
        returnsNormally,
      );
    });
  });
}
