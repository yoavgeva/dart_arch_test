import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

// Shared graph for all tests in this file.
DependencyGraph _graph() => {
  'package:app/features/home/home_screen.dart': {
    'package:app/features/home/home_provider.dart',
  },
  'package:app/features/home/home_provider.dart': {
    'package:app/data/home_repo.dart',
  },
  'package:app/features/discover/discover_screen.dart': {
    'package:app/features/discover/discover_provider.dart',
  },
  'package:app/features/discover/discover_provider.dart': <String>{},
  'package:app/features/auth/auth_service.dart': <String>{},
  'package:app/data/home_repo.dart': <String>{},
};

void main() {
  late DependencyGraph graph;
  setUp(() => graph = _graph());

  group('filesMatching', () {
    test('matches exact file', () {
      final resolved = filesMatching(
        'features/home/home_screen.dart',
      ).resolve(graph);
      expect(
        resolved,
        contains('package:app/features/home/home_screen.dart'),
      );
      expect(resolved, hasLength(1));
    });

    test('matches direct children with *', () {
      final resolved = filesMatching('features/home/*').resolve(graph);
      expect(
        resolved,
        containsAll([
          'package:app/features/home/home_screen.dart',
          'package:app/features/home/home_provider.dart',
        ]),
      );
      // data/ files are not matched
      expect(
        resolved,
        isNot(contains('package:app/data/home_repo.dart')),
      );
    });

    test('matches all descendants with **', () {
      final resolved = filesMatching('features/**').resolve(graph);
      expect(resolved, hasLength(5)); // all 5 features files
      expect(resolved, isNot(contains('package:app/data/home_repo.dart')));
    });

    test('returns empty set for pattern with no matches', () {
      expect(filesMatching('legacy/**').resolve(graph), isEmpty);
    });

    test('allFiles matches every library', () {
      expect(allFiles().resolve(graph), hasLength(6));
    });
  });

  group('LibrarySet.excluding', () {
    test('removes matching files from result', () {
      final resolved = filesMatching(
        'features/**',
      ).excluding('features/auth/**').resolve(graph);
      expect(
        resolved,
        isNot(contains('package:app/features/auth/auth_service.dart')),
      );
      expect(
        resolved,
        contains('package:app/features/home/home_screen.dart'),
      );
    });

    test('chaining two excludes', () {
      final resolved = filesMatching('features/**')
          .excluding('features/auth/**')
          .excluding('features/home/**')
          .resolve(graph);
      expect(resolved, hasLength(2)); // only discover files remain
    });

    test('excluding non-matching pattern is a no-op', () {
      final a = filesMatching('features/**').resolve(graph);
      final b = filesMatching(
        'features/**',
      ).excluding('legacy/**').resolve(graph);
      expect(a, equals(b));
    });
  });

  group('union', () {
    test('combines two disjoint selectors', () {
      final result = union(
        filesMatching('features/auth/**'),
        filesMatching('data/**'),
      ).resolve(graph);
      expect(
        result,
        containsAll([
          'package:app/features/auth/auth_service.dart',
          'package:app/data/home_repo.dart',
        ]),
      );
      expect(result, hasLength(2));
    });

    test('deduplicates overlapping selectors', () {
      final result = union(
        filesMatching('features/home/**'),
        filesMatching('features/home/home_screen.dart'),
      ).resolve(graph);
      // home_screen matches both — should appear only once
      expect(result.where((u) => u.endsWith('home_screen.dart')), hasLength(1));
    });
  });

  group('intersection', () {
    test('returns only common libraries', () {
      final result = intersection(
        filesMatching('features/**'),
        filesMatching('**/*screen.dart'),
      ).resolve(graph);
      // Only the screen files that are also under features/
      expect(
        result,
        containsAll([
          'package:app/features/home/home_screen.dart',
          'package:app/features/discover/discover_screen.dart',
        ]),
      );
      // provider files are not *screen.dart
      expect(
        result,
        isNot(contains('package:app/features/home/home_provider.dart')),
      );
    });

    test('returns empty set when no overlap', () {
      final result = intersection(
        filesMatching('features/auth/**'),
        filesMatching('data/**'),
      ).resolve(graph);
      expect(result, isEmpty);
    });
  });
}
