# Changelog

## 0.3.0

**New features:**

- **Variadic `union()`** — now accepts 2–5 selectors instead of exactly 2, eliminating the need for deep nesting:
  ```dart
  // Before (0.2.x)
  union(a, union(b, union(c, d)))
  // Now
  union(a, b, c, d)
  ```

- **`difference(a, b)`** — new top-level set operation returning libraries in `a` but not in `b`:
  ```dart
  // All feature files except generated code
  difference(filesMatching('features/**'), filesMatching('features/**/*.g.dart'))
  ```

- **`except:` parameter on all assertion functions** — exclude a subset of subjects from a rule without splitting it into two tests:
  ```dart
  shouldNotDependOn(
    filesMatching('shared/**'),
    filesMatching('features/**'),
    graph,
    except: filesMatching('shared/guards/**'),   // guards are a bridge by design
  );
  shouldNotTransitivelyDependOn(subject, object, graph, except: filesMatching('...'));
  shouldOnlyDependOn(subject, allowed, graph, except: filesMatching('...'));
  shouldNotBeCalledBy(object, callers, graph, except: filesMatching('...'));
  shouldOnlyBeCalledBy(object, allowed, graph, except: filesMatching('...'));
  ```

- **Content-based selectors** (`extending`, `implementing`, `withAnnotation`) — select libraries by what their classes declare, not just by file path:
  ```dart
  // Every ChangeNotifier subclass must live in a providers/ folder
  shouldHaveUriMatching(extending('ChangeNotifier'), '**/providers/**', graph);

  // UnreadCountSource implementations must stay in shared/
  shouldNotDependOn(implementing('UnreadCountSource'), filesMatching('features/**'), graph);

  // @immutable models must not import services
  shouldNotTransitivelyDependOn(withAnnotation('immutable'), filesMatching('**/services/**'), graph);
  ```
  Root path is inferred from the nearest `pubspec.yaml` walking up from CWD, or overridden via the `DART_ARCH_TEST_ROOT` environment variable.

**Exports:** `difference`, `extending`, `implementing`, `withAnnotation` are now exported from `package:dart_arch_test/dart_arch_test.dart`.

## 0.2.2

**Bug fix:**

- Fixed `Collector.buildGraph` crashing under `flutter test` with
  `PathNotFoundException` on `artifacts/engine/version` and
  `lib/_internal/libraries.dart`. Under `flutter test`,
  `Platform.resolvedExecutable` is `flutter_tester` (not `dart`), so the
  `analyzer` package's `getSdkPath()` resolved to the wrong directory.
  `Collector` now walks up the directory tree to find the real Dart SDK
  (`bin/cache/dart-sdk/`) before falling back to the previous behaviour.

## 0.2.1

**Bug fix:**

- `Collector.buildGraph` now compiles against analyzer ≥9.0.0: switched from
  `result.element2` (experimental in 7.x, removed in 9.x) to `result.element`
  (deprecated in 7.x, stable in 9.x). The `// ignore: deprecated_member_use`
  suppression keeps the code clean on both analyzer ranges.

## 0.2.0

**New features:**

- **`Metrics`** — Robert C. Martin coupling metrics from the import graph:
  - `Metrics.coupling(uri, graph)` — afferent coupling (Ca), efferent coupling (Ce), instability, abstractness, distance for a single library
  - `Metrics.instability(uri, graph)` — convenience shorthand for `Ce / (Ca + Ce)`
  - `Metrics.martin(pattern, graph)` — bulk report for all libraries matching a glob pattern
  - `CouplingMetrics` — immutable data class holding all five metric fields

- **`Freeze`** — violation baseline / snapshot support:
  - `freeze(ruleId, () { ... })` — top-level convenience function; passes if violations match the baseline, fails with `FreezeFailure` on new violations
  - `Freeze.freeze(ruleId, assertion, {storeDir})` — class-based API with optional custom store directory
  - `Freeze.updateFreeze()` — returns `true` when `DART_ARCH_TEST_UPDATE_FREEZE=1` is set
  - `Freeze.storePath()` — returns the baseline directory (env `DART_ARCH_TEST_FREEZE_STORE` or `test/arch_test_violations/`)
  - `FreezeFailure` — exception type thrown when new violations are detected

- **`Slices` additions:**
  - `allLibrariesCoveredBy(scope, graph, {except})` — asserts every library in `scope` belongs to at least one declared slice; `except` accepts glob patterns to skip
  - `sliceCycles(graph)` — returns all dependency cycles at the slice level
  - `shouldBeFreeOfSliceCycles(graph)` — throws `ArchTestFailure` if any slice-level cycle exists

**Exports:** `CouplingMetrics`, `Metrics`, `Freeze`, `FreezeFailure`, `freeze` are now exported from `package:dart_arch_test/dart_arch_test.dart`.

## 0.1.0

Initial release.

**Core features:**
- `Collector.buildGraph` — builds an import-graph from Dart source using the `analyzer` package; cached after first call
- `filesMatching(pattern)` / `allFiles()` — glob selectors for library URIs
- `shouldNotDependOn` / `shouldOnlyDependOn` — direct import rules
- `shouldNotTransitivelyDependOn` — transitive import rules
- `shouldNotBeCalledBy` / `shouldOnlyBeCalledBy` — caller-side rules
- `shouldNotExist` — forbid libraries matching a pattern
- `shouldBeFreeOfCycles` — DFS-based cycle detection
- `shouldHaveUriMatching` — URI naming conventions
- `defineLayers` + `enforceDirection` — layered architecture
- `defineOnion` + `enforceOnionRules` — onion/hexagonal architecture
- `defineSlices` + `allowDependency` + `enforceIsolation` + `shouldNotDependOnEachOther` — bounded-context / modulith isolation
- `ArchTestFailure` — collects all violations before throwing
