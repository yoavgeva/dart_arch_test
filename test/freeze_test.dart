import 'dart:io';

import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

// Builds a simple failing assertion that throws [ArchTestFailure].
void Function() failingAssertion(String msg) {
  return () {
    throw ArchTestFailure([
      Violation(rule: 'test', subject: 'a', message: msg),
    ]);
  };
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('dart_arch_test_freeze_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  // ── storePath ────────────────────────────────────────────────────────────

  group('storePath', () {
    test('returns default when env var is not set', () {
      // The env var DART_ARCH_TEST_FREEZE_STORE is not set in this process,
      // so the default should be returned.
      expect(Freeze.storePath(), equals('test/arch_test_violations'));
    });
  });

  // ── updateFreeze ─────────────────────────────────────────────────────────

  group('updateFreeze', () {
    test('returns false when env var is not set', () {
      // DART_ARCH_TEST_UPDATE_FREEZE is not set in the test environment.
      expect(Freeze.updateFreeze(), isFalse);
    });
  });

  // ── freeze — core behaviour ───────────────────────────────────────────────

  group('freeze', () {
    test('passes when assertion has no violations', () {
      // Assertion that never throws — should always pass.
      expect(
        () => freeze('clean_rule', () {}, storeDir: tmpDir.path),
        returnsNormally,
      );
    });

    test('throws FreezeFailure containing "NEW" when no baseline exists', () {
      expect(
        () => freeze(
          'new_rule',
          failingAssertion('must not import data'),
          storeDir: tmpDir.path,
        ),
        throwsA(
          isA<FreezeFailure>().having(
            (e) => e.toString(),
            'message',
            contains('NEW'),
          ),
        ),
      );
    });

    test('passes when violations match baseline exactly', () {
      // Write the baseline manually first.
      const violation = Violation(
        rule: 'test',
        subject: 'a',
        message: 'must not import data',
      );
      const failure = ArchTestFailure([violation]);
      final lines = failure
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      File('${tmpDir.path}/known_rule.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(lines.join('\n'));

      expect(
        () => freeze(
          'known_rule',
          failingAssertion('must not import data'),
          storeDir: tmpDir.path,
        ),
        returnsNormally,
      );
    });

    test('fails with "NEW" when new violations appear beyond baseline', () {
      // Baseline only contains violation A; assertion now produces A + B.
      const violationA = Violation(
        rule: 'test',
        subject: 'a',
        message: 'must not import data',
      );
      const baselineFailure = ArchTestFailure([violationA]);
      final baselineLines = baselineFailure
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      File('${tmpDir.path}/partial_rule.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(baselineLines.join('\n'));

      // Assertion that produces two violations.
      void twoViolations() {
        throw const ArchTestFailure([
          violationA,
          Violation(
            rule: 'test',
            subject: 'b',
            message: 'must not import lib',
          ),
        ]);
      }

      expect(
        () => freeze('partial_rule', twoViolations, storeDir: tmpDir.path),
        throwsA(
          isA<FreezeFailure>().having(
            (e) => e.toString(),
            'message',
            contains('NEW'),
          ),
        ),
      );
    });

    test('passes with zero violations even when a baseline file exists', () {
      // Baseline has content, but the assertion now passes cleanly.
      File('${tmpDir.path}/stale_rule.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('some old violation line');

      expect(
        () => freeze('stale_rule', () {}, storeDir: tmpDir.path),
        returnsNormally,
      );
    });

    test('captures dependency violations (message contains →)', () {
      void depViolation() {
        throw const ArchTestFailure([
          Violation(
            rule: 'shouldNotDependOn',
            subject: 'lib/features/home/home.dart',
            dependency: 'lib/data/repo.dart',
            message: 'must not import lib/data/repo.dart',
          ),
        ]);
      }

      // No baseline — should throw with NEW and the → arrow in the message.
      expect(
        () => freeze('dep_rule', depViolation, storeDir: tmpDir.path),
        throwsA(
          isA<FreezeFailure>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('NEW'), contains('→')),
          ),
        ),
      );
    });

    test('captures existence violations (no → in message)', () {
      void existViolation() {
        throw const ArchTestFailure([
          Violation(
            rule: 'shouldNotExist',
            subject: 'lib/legacy/old.dart',
            message: 'this library should not exist',
          ),
        ]);
      }

      expect(
        () => freeze('exist_rule', existViolation, storeDir: tmpDir.path),
        throwsA(
          isA<FreezeFailure>().having(
            (e) => e.toString(),
            'message',
            contains('NEW'),
          ),
        ),
      );
    });

    test('passes when all violations are in baseline (full coverage)', () {
      const violations = [
        Violation(
          rule: 'shouldNotDependOn',
          subject: 'lib/a.dart',
          dependency: 'lib/b.dart',
          message: 'must not import lib/b.dart',
        ),
        Violation(
          rule: 'shouldNotDependOn',
          subject: 'lib/c.dart',
          dependency: 'lib/d.dart',
          message: 'must not import lib/d.dart',
        ),
      ];

      const failure = ArchTestFailure(violations);
      final lines = failure
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      File('${tmpDir.path}/multi_rule.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(lines.join('\n'));

      void multiViolation() => throw const ArchTestFailure(violations);

      expect(
        () => freeze('multi_rule', multiViolation, storeDir: tmpDir.path),
        returnsNormally,
      );
    });
  });
}
