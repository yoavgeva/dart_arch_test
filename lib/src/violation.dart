/// Represents a single architecture rule violation.
library;

/// A rule violation with a human-readable description.
class Violation {
  /// Creates a [Violation].
  const Violation({
    required this.rule,
    required this.subject,
    required this.message,
    this.dependency,
  });

  /// The name of the rule that was violated.
  final String rule;

  /// The library URI that violated the rule.
  final String subject;

  /// Human-readable description.
  final String message;

  /// The dependency that caused the violation (if applicable).
  final String? dependency;

  @override
  String toString() {
    final dep = dependency != null ? ' → $dependency' : '';
    return '[$rule] $subject$dep: $message';
  }
}
