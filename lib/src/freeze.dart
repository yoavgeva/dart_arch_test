/// Violation snapshotting — tolerate known violations while catching new ones.
library;

import 'dart:io';

import 'package:dart_arch_test/src/assertions.dart';

/// Thrown when new violations appear that are not in the stored baseline.
class FreezeFailure implements Exception {
  /// Creates a [FreezeFailure] with the given [message].
  const FreezeFailure(this.message);

  /// Human-readable description of the new violations.
  final String message;

  @override
  String toString() => message;
}

/// Violation snapshotting — tolerate known violations while catching new ones.
///
/// ```dart
/// test('no forbidden deps (frozen)', () {
///   freeze('my_rule_id', () {
///     shouldNotDependOn(
///       filesMatching('features/**'),
///       filesMatching('data/**'),
///       graph,
///     );
///   });
/// });
/// ```
///
/// Set env var `DART_ARCH_TEST_UPDATE_FREEZE=1` to write/update the baseline.
class Freeze {
  Freeze._();

  /// Directory where baseline files are stored. Defaults to
  /// `test/arch_test_violations`. Override with env var
  /// `DART_ARCH_TEST_FREEZE_STORE`.
  static String storePath() {
    return Platform.environment['DART_ARCH_TEST_FREEZE_STORE'] ??
        'test/arch_test_violations';
  }

  /// Whether to update the baseline (write violations to disk).
  static bool updateFreeze() {
    final val = Platform.environment['DART_ARCH_TEST_UPDATE_FREEZE'] ?? '';
    return val.isNotEmpty && val != '0';
  }

  /// Runs [assertion] and compares violations against the stored baseline.
  ///
  /// - If assertion passes (no violations) → returns normally.
  /// - If violations exist and match baseline exactly → returns normally.
  /// - If violations exist and baseline is absent/different → throws
  ///   [FreezeFailure] with a message listing NEW violations.
  /// - If [updateFreeze] is true → writes current violations as the new
  ///   baseline and returns normally.
  ///
  /// Pass [storeDir] to override the directory used for baseline files
  /// (useful in tests to avoid touching the real store path).
  static void freeze(
    String ruleId,
    void Function() assertion, {
    String? storeDir,
  }) {
    List<String> currentLines;
    try {
      assertion();
      currentLines = [];
    } on ArchTestFailure catch (e) {
      currentLines = _extractViolationLines(e.toString());
    }

    if (currentLines.isEmpty) return; // no violations → always pass

    final dir = storeDir ?? storePath();
    final baselinePath = '$dir/$ruleId.txt';
    final baselineFile = File(baselinePath);

    if (updateFreeze()) {
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync(currentLines.join('\n'));
      return;
    }

    var baselineLines = <String>[];
    if (baselineFile.existsSync()) {
      baselineLines = baselineFile
          .readAsStringSync()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
    }

    final current = currentLines.where((l) => l.trim().isNotEmpty).toSet();
    final baseline = baselineLines.toSet();
    final newViolations = current.difference(baseline);

    if (newViolations.isEmpty) return; // all known → pass

    throw FreezeFailure(
      'Freeze: NEW violation(s) not in baseline for "$ruleId":\n'
      '${newViolations.join('\n')}',
    );
  }

  static List<String> _extractViolationLines(String message) {
    return message.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }
}

/// Convenience top-level function delegating to [Freeze.freeze].
void freeze(String ruleId, void Function() assertion, {String? storeDir}) =>
    Freeze.freeze(ruleId, assertion, storeDir: storeDir);
