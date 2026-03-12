/// Builds a library dependency graph from Dart source files using the
/// `analyzer` package.
///
/// The graph is a `Map<String, Set<String>>` where keys are library URIs
/// (e.g. `package:my_app/features/home/home_screen.dart`) and values are the
/// set of library URIs that the key directly imports.
///
/// Results are cached after the first call to `Collector.buildGraph`.
library;

import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

/// A dependency graph: `{ libUri -> { importedLibUri, ... } }`.
typedef DependencyGraph = Map<String, Set<String>>;

/// Builds (and caches) the dependency graph for all Dart files under
/// a given root path.
///
/// The root must be an absolute path (typically the package root, i.e. the
/// directory containing `pubspec.yaml`).
///
/// Pass `force: true` to bypass the in-memory cache and rebuild from disk.
/// Set `includeSdk: true` to include `dart:*` library edges (default false).
class Collector {
  Collector._();

  static DependencyGraph? _cache;

  /// Returns the dependency graph for all Dart source files under [rootPath].
  static Future<DependencyGraph> buildGraph(
    String rootPath, {
    bool includeSdk = false,
    bool force = false,
  }) async {
    if (!force && _cache != null) return _cache!;

    final graph = await _build(rootPath, includeSdk: includeSdk);
    _cache = graph;
    return graph;
  }

  /// Clears the in-memory cache.
  static void clearCache() => _cache = null;

  /// Returns all library URIs in [graph] (both importers and importees).
  static Set<String> allLibraries(DependencyGraph graph) {
    final all = <String>{};
    for (final entry in graph.entries) {
      all
        ..add(entry.key)
        ..addAll(entry.value);
    }
    return all;
  }

  /// Direct imports of [libraryUri].
  static Set<String> dependenciesOf(DependencyGraph graph, String libraryUri) =>
      graph[libraryUri] ?? {};

  /// Libraries that import [libraryUri].
  static Set<String> dependentsOf(DependencyGraph graph, String libraryUri) {
    return {
      for (final entry in graph.entries)
        if (entry.value.contains(libraryUri)) entry.key,
    };
  }

  /// Transitive dependencies of [libraryUri] up to [maxDepth] hops.
  ///
  /// [maxDepth] defaults to a very large integer (unlimited).
  static Set<String> transitiveDependenciesOf(
    DependencyGraph graph,
    String libraryUri, {
    int maxDepth = 1 << 30,
  }) {
    final visited = <String>{libraryUri};
    var frontier = <String>{libraryUri};
    var depth = 0;

    while (frontier.isNotEmpty && depth < maxDepth) {
      final next = <String>{};
      for (final lib in frontier) {
        for (final dep in graph[lib] ?? <String>{}) {
          if (visited.add(dep)) next.add(dep);
        }
      }
      frontier = next;
      depth++;
    }

    visited.remove(libraryUri);
    return visited;
  }

  /// Returns all dependency cycles in [graph].
  ///
  /// Each cycle is a list of library URIs forming a closed loop, normalized
  /// so the lexicographically smallest URI comes first.
  ///
  /// Uses recursive DFS with a global visited set to avoid O(n!) re-exploration
  /// of already-completed subtrees. Once a node's full subtree is explored,
  /// it is marked done and skipped on all future visits.
  static List<List<String>> cycles(DependencyGraph graph) {
    final foundKeys = <String>{};
    final result = <List<String>>[];
    // Nodes whose entire subtree has been fully explored from any root.
    // Re-visiting these cannot uncover new cycles.
    final done = <String>{};

    void dfs(String node, List<String> path, Set<String> onStack) {
      if (onStack.contains(node)) {
        // Back edge: cycle detected.
        final idx = path.indexOf(node);
        if (idx >= 0) {
          final cycle = _normalizeCycle(path.sublist(idx));
          final key = cycle.join('\x00');
          if (foundKeys.add(key)) result.add(cycle);
        }
        return;
      }

      if (done.contains(node)) return; // subtree already fully explored

      final newOnStack = {...onStack, node};
      final newPath = [...path, node];

      for (final dep in graph[node] ?? <String>{}) {
        dfs(dep, newPath, newOnStack);
      }

      // All descendants explored — mark as done so we never revisit.
      done.add(node);
    }

    for (final lib in graph.keys) {
      dfs(lib, [], {});
    }

    return result;
  }

  // ── private ──────────────────────────────────────────────────────────────

  /// Returns the Dart SDK path, correctly handling the `flutter test` scenario
  /// where [Platform.resolvedExecutable] is `flutter_tester` rather than
  /// `dart`, causing the analyzer's default `getSdkPath()` to return the
  /// wrong directory.
  ///
  /// Resolution order:
  ///   1. `DART_SDK` environment variable (explicit override).
  ///   2. `dart` on PATH (resolves symlinks).
  ///   3. Flutter SDK dart-sdk: walk up from `flutter_tester` to find
  ///      `bin/cache/dart-sdk` by looking for a `lib/_internal` sibling.
  ///   4. Fall back to the default `getSdkPath()` behaviour.
  /// Public so that other components (e.g. content-based selectors) can reuse
  /// the same SDK resolution logic.
  static String resolveDartSdkPath() => _resolveDartSdkPath();

  static String _resolveDartSdkPath() {
    // 1. Explicit override.
    final envSdk = Platform.environment['DART_SDK'];
    if (envSdk != null && Directory('$envSdk/lib/_internal').existsSync()) {
      return envSdk;
    }

    // 2. `dart` on PATH.
    final pathDirs = (Platform.environment['PATH'] ?? '').split(':');
    for (final dir in pathDirs) {
      final candidate = p.join(dir, 'dart');
      if (File(candidate).existsSync()) {
        final sdkPath = p.dirname(
          p.dirname(
            File(candidate).resolveSymbolicLinksSync(),
          ),
        );
        if (Directory('$sdkPath/lib/_internal').existsSync()) {
          return sdkPath;
        }
      }
    }

    // 3. Walk up from Platform.resolvedExecutable to find dart-sdk.
    //    Under `flutter test`, the executable is flutter_tester inside
    //    .../bin/cache/artifacts/engine/<platform>/flutter_tester.
    //    The dart-sdk lives at .../bin/cache/dart-sdk.
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final candidate = p.join(dir.path, 'dart-sdk');
      if (Directory('$candidate/lib/_internal').existsSync()) {
        return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    // 4. Default (works when running with `dart test` directly).
    return p.dirname(p.dirname(Platform.resolvedExecutable));
  }

  static Future<DependencyGraph> _build(
    String rootPath, {
    required bool includeSdk,
  }) async {
    final absRoot = p.canonicalize(rootPath);
    final dartFiles = _dartFiles(absRoot);

    if (dartFiles.isEmpty) return {};

    final collection = AnalysisContextCollection(
      includedPaths: [absRoot],
      sdkPath: _resolveDartSdkPath(),
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final graph = <String, Set<String>>{};

    for (final context in collection.contexts) {
      for (final filePath in dartFiles) {
        final result = await context.currentSession.getResolvedLibrary(
          filePath,
        );

        if (result is! ResolvedLibraryResult) continue;

        // analyzer ≥9.0: element is the stable API (element2 removed in 9.x).
        // LibraryElement.uri holds the canonical package: URI.
        // importedLibraries lives on LibraryFragment (each compilation unit);
        // collect imports across all fragments to handle part files.
        final lib = result.element;

        final callerUri = lib.uri.toString();

        // Only track files under rootPath (skip generated / pub cache files)
        if (!filePath.startsWith(absRoot)) continue;

        graph.putIfAbsent(callerUri, LinkedHashSet.new);

        for (final fragment in lib.fragments) {
          for (final imported in fragment.importedLibraries) {
            if (!includeSdk && imported.isInSdk) continue;
            final importedUri = imported.uri.toString();
            if (importedUri == callerUri) continue;
            graph[callerUri]!.add(importedUri);
          }
        }
      }
    }

    return graph;
  }

  static List<String> _dartFiles(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];

    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.contains('${p.separator}.dart_tool${p.separator}') &&
              !f.path.contains('${p.separator}.pub-cache${p.separator}') &&
              !f.path.contains('${p.separator}build${p.separator}'),
        )
        .map((f) => p.canonicalize(f.path))
        .toList();
  }

  static List<String> _normalizeCycle(List<String> cycle) {
    if (cycle.isEmpty) return cycle;
    final minVal = cycle.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    final minIdx = cycle.indexOf(minVal);
    return [...cycle.sublist(minIdx), ...cycle.sublist(0, minIdx)];
  }
}
