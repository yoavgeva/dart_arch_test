/// ArchUnit-inspired architecture testing library for Dart/Flutter.
///
/// Write `test(...)` blocks that enforce architectural rules — dependency
/// direction, layer boundaries, bounded-context isolation, and naming
/// conventions — using a fluent DSL.
///
/// ## Quick start
///
/// ```dart
/// import 'package:dart_arch_test/dart_arch_test.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   late DependencyGraph graph;
///
///   setUpAll(() async {
///     graph = await Collector.buildGraph('/path/to/my_app');
///   });
///
///   test('home feature must not import discover feature', () {
///     shouldNotDependOn(
///       filesMatching('features/home/**'),
///       filesMatching('features/discover/**'),
///       graph,
///     );
///   });
///
///   test('no circular dependencies in domain layer', () {
///     shouldBeFreeOfCycles(filesMatching('domain/**'), graph);
///   });
///
///   test('feature slices are isolated', () {
///     defineSlices({
///       'home':     'features/home/**',
///       'discover': 'features/discover/**',
///       'auth':     'features/auth/**',
///     })
///     .allowDependency('home', 'auth')
///     .allowDependency('discover', 'auth')
///     .enforceIsolation(graph);
///   });
///
///   test('layers only depend downward', () {
///     defineLayers({
///       'presentation': 'features/**',
///       'domain':       'domain/**',
///       'data':         'data/**',
///     }).enforceDirection(graph);
///   });
/// }
/// ```
library;

export 'src/assertions.dart'
    show
        ArchTestFailure,
        shouldBeFreeOfCycles,
        shouldHaveUriMatching,
        shouldNotBeCalledBy,
        shouldNotDependOn,
        shouldNotExist,
        shouldNotTransitivelyDependOn,
        shouldOnlyBeCalledBy,
        shouldOnlyDependOn;
export 'src/class_matcher.dart'
    show
        clearContentMatcherCache,
        extending,
        implementing,
        withAnnotation;
export 'src/collector.dart' show Collector, DependencyGraph;
export 'src/freeze.dart' show Freeze, FreezeFailure, freeze;
export 'src/layers.dart' show Layers, defineLayers, defineOnion;
export 'src/library_set.dart'
    show
        LibrarySelector,
        LibrarySet,
        allFiles,
        difference,
        filesMatching,
        intersection,
        union;
export 'src/metrics.dart' show CouplingMetrics, Metrics;
export 'src/pattern.dart' show matchesGlob, uriToPath;
export 'src/slices.dart' show Slices, defineSlices;
export 'src/violation.dart' show Violation;
