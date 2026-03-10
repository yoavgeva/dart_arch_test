import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

void main() {
  group('Violation', () {
    test('toString includes rule, subject and message', () {
      const v = Violation(
        rule: 'shouldNotDependOn',
        subject: 'package:app/a.dart',
        message: 'must not import b',
      );
      expect(v.toString(), contains('shouldNotDependOn'));
      expect(v.toString(), contains('package:app/a.dart'));
      expect(v.toString(), contains('must not import b'));
    });

    test('toString includes dependency when present', () {
      const v = Violation(
        rule: 'shouldNotDependOn',
        subject: 'package:app/a.dart',
        dependency: 'package:app/b.dart',
        message: 'must not import b',
      );
      expect(v.toString(), contains('→ package:app/b.dart'));
    });

    test('toString omits arrow when dependency is null', () {
      const v = Violation(
        rule: 'shouldNotExist',
        subject: 'package:app/a.dart',
        message: 'should not exist',
      );
      expect(v.toString(), isNot(contains('→')));
    });
  });

  group('ArchTestFailure', () {
    test('toString includes violation count', () {
      const violations = [
        Violation(
          rule: 'r',
          subject: 'package:app/a.dart',
          message: 'm',
        ),
        Violation(
          rule: 'r',
          subject: 'package:app/b.dart',
          message: 'm',
        ),
      ];
      const e = ArchTestFailure(violations);
      expect(e.toString(), contains('2'));
      expect(e.toString(), contains('Architecture violations'));
    });

    test('exposes violations list', () {
      const v = Violation(
        rule: 'r',
        subject: 'package:app/a.dart',
        message: 'm',
      );
      const e = ArchTestFailure([v]);
      expect(e.violations, hasLength(1));
      expect(e.violations.first, same(v));
    });

    test('is an Exception', () {
      expect(const ArchTestFailure([]), isA<Exception>());
    });
  });
}
