/// Layered architecture enforcement.
///
/// Analogous to `ArchTest.Layers` in the Elixir library.
///
/// ```dart
/// final layers = defineLayers({
///   'presentation': 'features/**',
///   'domain':       'domain/**',
///   'data':         'data/**',
/// });
///
/// // Each layer may only import layers below it (later in the map)
/// await layers.enforceDirection(graph);
/// ```
library;

import 'package:dart_arch_test/src/assertions.dart';
import 'package:dart_arch_test/src/collector.dart';
import 'package:dart_arch_test/src/library_set.dart';
import 'package:dart_arch_test/src/violation.dart';

/// An ordered list of named architecture layers.
///
/// Order matters: layers listed first are "higher" (e.g. presentation) and
/// must not import layers listed later *above* them. In other words, layer N
/// may only depend on layers N+1, N+2, … (layers below it).
class Layers {
  Layers._(this._layers);

  /// `[(name, pattern), ...]` in top-to-bottom order.
  final List<(String, String)> _layers;

  /// Asserts that each layer only depends on layers below it.
  ///
  /// Throws [ArchTestFailure] on violation.
  void enforceDirection(DependencyGraph graph) {
    final violations = <Violation>[];

    for (var i = 0; i < _layers.length; i++) {
      final (layerName, layerPattern) = _layers[i];
      final layerLibs = filesMatching(layerPattern).resolve(graph);

      // Patterns for layers above the current one (forbidden dependencies)
      final higherLayers = _layers.sublist(0, i);

      for (final higherPattern in higherLayers.map((l) => l.$2)) {
        final higherLibs = filesMatching(higherPattern).resolve(graph);

        for (final lib in layerLibs) {
          for (final dep in Collector.dependenciesOf(graph, lib)) {
            if (higherLibs.contains(dep)) {
              final higherName = higherLayers
                  .firstWhere((l) => l.$2 == higherPattern)
                  .$1;
              violations.add(
                Violation(
                  rule: 'enforceDirection',
                  subject: lib,
                  dependency: dep,
                  message:
                      'layer "$layerName" must not import'
                      ' layer "$higherName" (above it)',
                ),
              );
            }
          }
        }
      }
    }

    if (violations.isNotEmpty) throw ArchTestFailure(violations);
  }

  /// Asserts onion/hexagonal rules: inner layers must not depend on outer layers.
  ///
  /// The first layer in the list is the innermost (domain/core); each
  /// subsequent layer may import layers before it but not after it.
  void enforceOnionRules(DependencyGraph graph) {
    // In onion architecture, layers are listed innermost first.
    // Inner layers must NOT depend on outer layers (= layers after them).
    final violations = <Violation>[];

    for (var i = 0; i < _layers.length; i++) {
      final (layerName, layerPattern) = _layers[i];
      final layerLibs = filesMatching(layerPattern).resolve(graph);
      final outerLayers = _layers.sublist(i + 1);

      for (final (outerName, outerPattern) in outerLayers) {
        final outerLibs = filesMatching(outerPattern).resolve(graph);

        for (final lib in layerLibs) {
          for (final dep in Collector.dependenciesOf(graph, lib)) {
            if (outerLibs.contains(dep)) {
              violations.add(
                Violation(
                  rule: 'enforceOnionRules',
                  subject: lib,
                  dependency: dep,
                  message:
                      'inner layer "$layerName" must not import'
                      ' outer layer "$outerName"',
                ),
              );
            }
          }
        }
      }
    }

    if (violations.isNotEmpty) throw ArchTestFailure(violations);
  }
}

/// Defines an ordered list of layers (top-to-bottom / higher-to-lower).
///
/// ```dart
/// final layers = defineLayers({
///   'presentation': 'features/**',
///   'domain':       'domain/**',
///   'data':         'data/**',
/// });
/// layers.enforceDirection(graph);
/// ```
Layers defineLayers(Map<String, String> layerDefs) =>
    Layers._(layerDefs.entries.map((e) => (e.key, e.value)).toList());

/// Defines an onion/hexagonal architecture (innermost layer first).
///
/// ```dart
/// final onion = defineOnion({
///   'domain':      'domain/**',
///   'application': 'application/**',
///   'adapters':    'features/**',
/// });
/// onion.enforceOnionRules(graph);
/// ```
Layers defineOnion(Map<String, String> layerDefs) =>
    Layers._(layerDefs.entries.map((e) => (e.key, e.value)).toList());
