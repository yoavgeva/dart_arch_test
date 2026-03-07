/// Glob pattern matching for Dart library URIs and class names.
///
/// Pattern syntax (mirrors the Elixir arch_test semantics):
///
/// | Pattern              | Matches                                      |
/// |----------------------|----------------------------------------------|
/// | `features/home/*`    | Direct children only                         |
/// | `features/home/**`   | All descendants at any depth                 |
/// | `features/home`      | Exact match only                             |
/// | `**/*Service`        | Last segment ends with `Service`             |
/// | `**/*Service*`       | Last segment contains `Service`              |
library;

import 'package:path/path.dart' as p;

/// Returns `true` if [value] matches the glob [pattern].
///
/// Both [value] and [pattern] use forward slashes as segment separators
/// (matching Dart package URI convention, e.g. `package:my_app/features/home/home_screen.dart`).
bool matchesGlob(String pattern, String value) {
  // Strip package URI prefix for matching — callers may pass
  // 'package:foo/bar/baz.dart' or just 'bar/baz.dart'.
  final normValue = _normalize(value);
  final normPattern = _normalize(pattern);
  return _match(normPattern, normValue);
}

String _normalize(String s) {
  // Remove 'package:name/' prefix
  final pkgPrefix = RegExp('^package:[^/]+/');
  return s.replaceFirst(pkgPrefix, '');
}

/// Recursive glob matching supporting `*` (single segment)
/// and `**` (any depth).
bool _match(String pattern, String value) {
  if (pattern.isEmpty && value.isEmpty) return true;
  if (pattern.isEmpty) return false;

  final patternSegments = pattern.split('/');
  final valueSegments = value.split('/');

  return _matchSegments(patternSegments, 0, valueSegments, 0);
}

bool _matchSegments(List<String> pattern, int pi, List<String> value, int vi) {
  var patIdx = pi;
  var valIdx = vi;

  while (patIdx < pattern.length) {
    final seg = pattern[patIdx];

    if (seg == '**') {
      // '**' matches zero or more path segments
      // trailing ** matches everything remaining
      if (patIdx == pattern.length - 1) return true;
      // Try consuming 0, 1, 2, ... value segments for the '**'
      for (var skip = valIdx; skip <= value.length; skip++) {
        if (_matchSegments(pattern, patIdx + 1, value, skip)) return true;
      }
      return false;
    }

    if (valIdx >= value.length) return false;
    if (!_matchSegment(seg, value[valIdx])) return false;

    patIdx++;
    valIdx++;
  }

  return valIdx == value.length;
}

/// Matches a single path segment with `*` wildcards (not spanning `/`).
bool _matchSegment(String pattern, String value) {
  if (pattern == '*') return true;
  if (!pattern.contains('*')) return pattern == value;

  // Build a simple regex from segment-level wildcards
  final regex = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$');
  return regex.hasMatch(value);
}

/// Converts a Dart file URI like `package:foo/bar/baz.dart` to a
/// dot-separated class path like `bar.baz` (dropping the `.dart` suffix
/// and the package prefix).
///
/// Used for pattern matching that mirrors Elixir module notation.
String uriToPath(String uri) {
  final norm = _normalize(uri);
  return p.withoutExtension(norm).replaceAll('/', '.');
}
