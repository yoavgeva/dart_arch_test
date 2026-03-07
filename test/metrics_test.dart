import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

// In-memory graph mirroring the topology used in the Elixir metrics_test.exs:
//
//   Web.Controller  → [App.Service]
//   App.Service     → [Repo.OrderRepo]
//   Repo.OrderRepo  → []
//   Standalone      → []
DependencyGraph _graph() => {
  'package:app/web/controller.dart': {'package:app/app/service.dart'},
  'package:app/app/service.dart': {'package:app/repo/order_repo.dart'},
  'package:app/repo/order_repo.dart': <String>{},
  'package:app/standalone.dart': <String>{},
};

void main() {
  late DependencyGraph graph;
  setUp(() => graph = _graph());

  // ── coupling (single library) ─────────────────────────────────────────────

  group('coupling — single library metrics', () {
    test(
      'App.Service: Ca=1 (Controller depends on it), Ce=1 (depends on Repo)',
      () {
        final m = Metrics.coupling('package:app/app/service.dart', graph);
        expect(m.afferent, equals(1));
        expect(m.efferent, equals(1));
        expect(m.instability, closeTo(0.5, 0.001));
      },
    );

    test('Repo.OrderRepo: Ca=1 (Service depends on it), Ce=0 (leaf)', () {
      final m = Metrics.coupling('package:app/repo/order_repo.dart', graph);
      expect(m.afferent, equals(1));
      expect(m.efferent, equals(0));
      expect(m.instability, closeTo(0.0, 0.001));
    });

    test('Standalone: Ca=0, Ce=0 (completely isolated)', () {
      final m = Metrics.coupling('package:app/standalone.dart', graph);
      expect(m.afferent, equals(0));
      expect(m.efferent, equals(0));
      expect(m.instability, closeTo(0.0, 0.001));
    });

    test('Web.Controller: Ca=0 (nobody calls it), Ce=1, instability=1.0', () {
      final m = Metrics.coupling('package:app/web/controller.dart', graph);
      expect(m.afferent, equals(0));
      expect(m.efferent, equals(1));
      expect(m.instability, closeTo(1.0, 0.001));
    });

    test('abstractness is always 0.0', () {
      for (final uri in graph.keys) {
        expect(Metrics.coupling(uri, graph).abstractness, closeTo(0.0, 0.001));
      }
    });

    test('distance = |abstractness + instability - 1| for each library', () {
      for (final uri in graph.keys) {
        final m = Metrics.coupling(uri, graph);
        final expected = (m.abstractness + m.instability - 1.0).abs();
        expect(m.distance, closeTo(expected, 0.001));
      }
    });
  });

  // ── instability convenience method ────────────────────────────────────────

  group('instability convenience method', () {
    test('Repo.OrderRepo → 0.0 (stable leaf)', () {
      expect(
        Metrics.instability('package:app/repo/order_repo.dart', graph),
        closeTo(0.0, 0.001),
      );
    });

    test('Web.Controller → 1.0 (fully unstable entry point)', () {
      expect(
        Metrics.instability('package:app/web/controller.dart', graph),
        closeTo(1.0, 0.001),
      );
    });
  });

  // ── martin bulk method ────────────────────────────────────────────────────

  group('martin bulk method', () {
    test('martin("**", graph) returns all 4 libraries', () {
      final result = Metrics.martin('**', graph);
      expect(result, hasLength(4));
    });

    test('each entry has all required fields with correct types', () {
      final result = Metrics.martin('**', graph);
      for (final entry in result.entries) {
        final m = entry.value;
        expect(m.afferent, isA<int>());
        expect(m.efferent, isA<int>());
        expect(m.instability, isA<double>());
        expect(m.abstractness, isA<double>());
        expect(m.distance, isA<double>());
      }
    });

    test('instability is in [0.0, 1.0] for all libraries', () {
      final result = Metrics.martin('**', graph);
      for (final m in result.values) {
        expect(m.instability, greaterThanOrEqualTo(0.0));
        expect(m.instability, lessThanOrEqualTo(1.0));
      }
    });

    test('distance = |abstractness + instability - 1| for all libraries', () {
      final result = Metrics.martin('**', graph);
      for (final m in result.values) {
        final expected = (m.abstractness + m.instability - 1.0).abs();
        expect(m.distance, closeTo(expected, 0.001));
      }
    });

    test('martin("repo/**", graph) returns only Repo.OrderRepo', () {
      final result = Metrics.martin('repo/**', graph);
      expect(result, hasLength(1));
      expect(result.keys.first, equals('package:app/repo/order_repo.dart'));
    });

    test('martin("NoSuch/**", graph) returns empty map', () {
      final result = Metrics.martin('NoSuch/**', graph);
      expect(result, isEmpty);
    });

    test('martin("**", emptyGraph) returns empty map', () {
      final result = Metrics.martin('**', {});
      expect(result, isEmpty);
    });

    test('martin("**", graph) values match per-library coupling() calls', () {
      final result = Metrics.martin('**', graph);
      for (final entry in result.entries) {
        final expected = Metrics.coupling(entry.key, graph);
        final actual = entry.value;
        expect(actual.afferent, equals(expected.afferent));
        expect(actual.efferent, equals(expected.efferent));
        expect(actual.instability, closeTo(expected.instability, 0.001));
        expect(actual.abstractness, closeTo(expected.abstractness, 0.001));
        expect(actual.distance, closeTo(expected.distance, 0.001));
      }
    });
  });

  // ── coupling aggregate (pattern-based) ───────────────────────────────────

  group('coupling with pattern — aggregate package metrics via martin', () {
    test('martin("**", graph) returns non-empty map with required fields', () {
      final result = Metrics.martin('**', graph);
      expect(result, isNotEmpty);
      for (final m in result.values) {
        expect(m.afferent, isA<int>());
        expect(m.efferent, isA<int>());
        expect(m.instability, isA<double>());
        expect(m.abstractness, isA<double>());
        expect(m.distance, isA<double>());
      }
    });
  });
}
