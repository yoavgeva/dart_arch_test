import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

void main() {
  group('matchesGlob', () {
    group('exact match', () {
      test('matches exact path', () {
        expect(
          matchesGlob(
            'features/home/home_screen.dart',
            'features/home/home_screen.dart',
          ),
          isTrue,
        );
      });

      test('does not match different path', () {
        expect(
          matchesGlob(
            'features/home/home_screen.dart',
            'features/discover/discover_screen.dart',
          ),
          isFalse,
        );
      });
    });

    group('single-segment wildcard *', () {
      test('matches one segment', () {
        expect(
          matchesGlob('features/home/*', 'features/home/home_screen.dart'),
          isTrue,
        );
      });

      test('does not match across segments', () {
        expect(
          matchesGlob('features/home/*', 'features/home/widgets/card.dart'),
          isFalse,
        );
      });

      test('matches suffix pattern *Service.dart', () {
        expect(
          matchesGlob(
            'features/home/*Service.dart',
            'features/home/homeService.dart',
          ),
          isTrue,
        );
      });
    });

    group('double-star wildcard **', () {
      test('matches zero depth', () {
        expect(matchesGlob('features/**', 'features/home_screen.dart'), isTrue);
      });

      test('matches one level deep', () {
        expect(
          matchesGlob('features/**', 'features/home/home_screen.dart'),
          isTrue,
        );
      });

      test('matches many levels deep', () {
        expect(
          matchesGlob('features/**', 'features/home/widgets/media/card.dart'),
          isTrue,
        );
      });

      test('does not match sibling', () {
        expect(
          matchesGlob('features/**', 'domain/home/home_screen.dart'),
          isFalse,
        );
      });

      test('** at end matches everything remaining', () {
        expect(
          matchesGlob(
            'features/home/**',
            'features/home/providers/provider.dart',
          ),
          isTrue,
        );
      });
    });

    group('package URI prefix stripping', () {
      test('strips package:name/ prefix', () {
        expect(
          matchesGlob(
            'features/home/**',
            'package:my_app/features/home/screen.dart',
          ),
          isTrue,
        );
      });

      test('pattern with package prefix also stripped', () {
        expect(
          matchesGlob(
            'package:my_app/features/**',
            'package:my_app/features/home/screen.dart',
          ),
          isTrue,
        );
      });
    });
  });

  group('uriToPath', () {
    test('converts package URI to dot-separated path', () {
      expect(
        uriToPath('package:my_app/features/home/home_screen.dart'),
        'features.home.home_screen',
      );
    });

    test('strips .dart extension', () {
      expect(
        uriToPath('features/home/home_screen.dart'),
        'features.home.home_screen',
      );
    });
  });
}
