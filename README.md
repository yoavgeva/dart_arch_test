# dart_arch_test

[![CI](https://github.com/yoavgeva/dart_arch_test/actions/workflows/ci.yaml/badge.svg)](https://github.com/yoavgeva/dart_arch_test/actions/workflows/ci.yaml)
[![pub package](https://img.shields.io/pub/v/dart_arch_test.svg)](https://pub.dev/packages/dart_arch_test)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

**ArchUnit-inspired architecture testing for Dart & Flutter.**

Write plain `test()` blocks that enforce architectural rules — dependency direction, layer boundaries, bounded-context isolation, cycle detection, coupling metrics, and violation baselines — directly from your import graph. No annotations, no code generation, no config files.

```dart
test('feature slices must not cross-import each other', () {
  defineSlices({
    'home':     'features/home/**',
    'discover': 'features/discover/**',
    'auth':     'features/auth/**',
  })
  .allowDependency('home', 'auth')
  .allowDependency('discover', 'auth')
  .enforceIsolation(graph);
});
```

---

## Why?

Large Flutter projects rot in a predictable way: a `HomeProvider` quietly imports a `DiscoverRepository`, a `data` layer starts depending on `domain`, and six months later every feature touches every other feature. Code review misses it. Lint rules can't catch it. Architecture diagrams go stale.

`dart_arch_test` makes these rules machine-checkable and keeps them right next to your tests — where they get run in CI.

---

## Features

- **Dependency rules** — `shouldNotDependOn`, `shouldOnlyDependOn`, `shouldNotTransitivelyDependOn`
- **Cycle detection** — `shouldBeFreeOfCycles` using DFS over the import graph
- **Layer enforcement** — `defineLayers` + `enforceDirection` (each layer may only depend downward)
- **Onion / hexagonal** — `defineOnion` + `enforceOnionRules` (dependencies point only inward)
- **Slice isolation** — `defineSlices` + `allowDependency` + `enforceIsolation` (modulith boundaries)
- **Slice coverage** — `allLibrariesCoveredBy` (every lib must belong to a declared slice)
- **Slice cycles** — `sliceCycles` + `shouldBeFreeOfSliceCycles` (detect cycles between slices)
- **Caller control** — `shouldOnlyBeCalledBy`, `shouldNotBeCalledBy`
- **Existence rules** — `shouldNotExist`, `shouldHaveUriMatching`
- **Coupling metrics** — `Metrics.coupling`, `Metrics.instability`, `Metrics.martin` (Robert C. Martin's Ca/Ce/instability/distance)
- **Violation freeze** — `freeze(ruleId, () { ... })` baselines known violations so new ones cause failures in CI
- **Glob patterns** — `**` for any depth, `*` for single segment, works with `package:` URIs
- **Fast** — caches the analyzer graph; subsequent assertions in the same test run are free

---

## Install

```yaml
dev_dependencies:
  dart_arch_test: ^0.2.0
```

```sh
dart pub get
# or
flutter pub get
```

---

## Quick start

### 1. Build the graph once per test suite

```dart
import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:test/test.dart';

void main() {
  late DependencyGraph graph;

  setUpAll(() async {
    // Point to your package root (where pubspec.yaml lives)
    graph = await Collector.buildGraph('/path/to/my_app');
  });

  // ... your rules below
}
```

> **Tip:** Use `path.dirname(Platform.script.toFilePath())` or a relative path like `'../'` to avoid hardcoding absolute paths.

### 2. Write rules

```dart
test('home must not import discover', () {
  shouldNotDependOn(
    filesMatching('features/home/**'),
    filesMatching('features/discover/**'),
    graph,
  );
});

test('no cycles anywhere', () {
  shouldBeFreeOfCycles(allFiles(), graph);
});

test('layers only depend downward', () {
  defineLayers({
    'presentation': 'features/**',
    'domain':       'domain/**',
    'data':         'data/**',
  }).enforceDirection(graph);
});
```

---

## Rule reference

### Dependency rules

| Function | Description |
|---|---|
| `shouldNotDependOn(subject, object, graph)` | No library in `subject` may directly import any library in `object` |
| `shouldOnlyDependOn(subject, allowed, graph)` | Libraries in `subject` may only import libraries in `allowed` (plus SDK) |
| `shouldNotTransitivelyDependOn(subject, object, graph)` | No transitive path from `subject` to `object` |
| `shouldNotBeCalledBy(object, callers, graph)` | No library in `callers` may import any library in `object` |
| `shouldOnlyBeCalledBy(object, allowed, graph)` | Only libraries in `allowed` may import libraries in `object` |

### Existence rules

| Function | Description |
|---|---|
| `shouldNotExist(subject, graph)` | Fails if any library matching `subject` exists in the graph |
| `shouldBeFreeOfCycles(subject, graph)` | Fails if any import cycle exists among matched libraries |
| `shouldHaveUriMatching(subject, pattern, graph)` | All matched libraries must have a URI matching `pattern` |

### Layer rules

```dart
// Top-to-bottom: higher layers may not import lower ones
defineLayers({
  'presentation': 'features/**',
  'domain':       'domain/**',
  'data':         'data/**',
}).enforceDirection(graph);

// Onion / hexagonal: innermost layer listed first
// Inner layers must not import outer layers
defineOnion({
  'domain':      'domain/**',
  'application': 'application/**',
  'adapters':    'features/**',
}).enforceOnionRules(graph);
```

### Slice isolation (modulith)

```dart
defineSlices({
  'home':     'features/home/**',
  'discover': 'features/discover/**',
  'auth':     'features/auth/**',
})
.allowDependency('home', 'auth')      // home → auth is explicitly allowed
.allowDependency('discover', 'auth')
.enforceIsolation(graph);             // everything else is forbidden

// Strict mode — no cross-slice deps at all
defineSlices({...}).shouldNotDependOnEachOther(graph);

// Every library in scope must belong to a declared slice
defineSlices({...}).allLibrariesCoveredBy(
  filesMatching('features/**'),
  graph,
  except: ['features/generated/**'],
);

// No cycles between slices
defineSlices({...}).shouldBeFreeOfSliceCycles(graph);
```

### Coupling metrics

`Metrics` computes [Robert C. Martin's](https://en.wikipedia.org/wiki/Robert_C._Martin) package-level coupling metrics from the import graph.

| Metric | Meaning |
|---|---|
| **Ca** (afferent) | How many other libraries depend on this one |
| **Ce** (efferent) | How many libraries this one depends on |
| **Instability** | `Ce / (Ca + Ce)` — 0.0 = stable, 1.0 = unstable |
| **Abstractness** | Always 0.0 in Dart (no BEAM introspection) |
| **Distance** | `\|abstractness + instability − 1\|` — distance from the main sequence |

```dart
// Single-library metrics
final m = Metrics.coupling('package:my_app/data/user_repo.dart', graph);
print('Ca=${m.afferent}  Ce=${m.efferent}  I=${m.instability.toStringAsFixed(2)}');

// Instability shorthand
final i = Metrics.instability('package:my_app/data/user_repo.dart', graph);

// Bulk report for all libraries matching a pattern
final report = Metrics.martin('features/**', graph);
for (final entry in report.entries) {
  print('${entry.key}: I=${entry.value.instability.toStringAsFixed(2)}');
}
```

### Violation freeze

`freeze` lets you acknowledge existing violations so CI only fails on *new* ones — useful when adopting architecture rules on a legacy codebase.

```dart
test('home dependencies — freeze known violations', () {
  freeze('home_deps', () {
    shouldNotDependOn(
      filesMatching('features/home/**'),
      filesMatching('data/**'),
      graph,
    );
  });
});
```

On first run with no baseline the test passes and records known violations. On subsequent runs, any violation *not* in the baseline causes a `FreezeFailure`.

To update the baseline (e.g. after fixing some violations):

```sh
DART_ARCH_TEST_UPDATE_FREEZE=1 dart test
```

Baseline files are stored in `test/arch_test_violations/` by default. Override with the `DART_ARCH_TEST_FREEZE_STORE` environment variable or the `storeDir` parameter:

```dart
freeze('home_deps', () { ... }, storeDir: 'test/baselines');
```

---

## Selectors

Use `filesMatching(pattern)` to select libraries by glob pattern:

| Pattern | Matches |
|---|---|
| `'features/home/**'` | Everything under `features/home/` at any depth |
| `'features/home/*'` | Direct children of `features/home/` only |
| `'features/home/home_screen.dart'` | Exact file |
| `'**/*Repository.dart'` | Any file ending in `Repository.dart` |
| `'**/*_bloc.dart'` | Any BLoC file anywhere |

Patterns match against the part of the URI after `package:my_app/`, so you never need to include the package prefix.

**Composition:**

```dart
// Union
final uiLibs = filesMatching('features/**').unionWith(filesMatching('widgets/**'));

// Exclusion
filesMatching('features/**').excluding('features/auth/**')

// Top-level helpers
union(filesMatching('features/**'), filesMatching('widgets/**'))
intersection(filesMatching('features/**'), filesMatching('**/*Screen.dart'))
```

---

## Failure output

When a rule is violated, `dart_arch_test` throws an `ArchTestFailure` with a clear message:

```
Architecture violations (2):
  [shouldNotDependOn] package:my_app/features/home/home_provider.dart → package:my_app/features/discover/discover_repository.dart: must not import package:my_app/features/discover/discover_repository.dart
  [shouldNotDependOn] package:my_app/features/home/home_screen.dart → package:my_app/features/discover/discover_screen.dart: must not import package:my_app/features/discover/discover_screen.dart
```

All violations are collected before throwing — you see every problem at once, not just the first one.

---

## Performance

`Collector.buildGraph` runs the Dart `analyzer` over your source tree once and caches the result. A typical medium-sized Flutter app (200–500 files) builds the graph in 2–5 seconds. All subsequent rule assertions in the same test run use the cached graph and complete in microseconds.

```dart
// Cache is shared across all tests in the same process
setUpAll(() async {
  graph = await Collector.buildGraph(packageRoot);
});
```

---

## Comparison

| | dart_arch_test | import_lint | custom_lint |
|---|---|---|---|
| Dependency rules | ✅ | ✅ (config only) | ❌ |
| Cycle detection | ✅ | ❌ | ❌ |
| Layer enforcement | ✅ | ❌ | ❌ |
| Slice isolation | ✅ | ❌ | ❌ |
| Coupling metrics | ✅ | ❌ | ❌ |
| Violation freeze | ✅ | ❌ | ❌ |
| Plain Dart tests | ✅ | ❌ | ❌ |
| Programmatic DSL | ✅ | ❌ | ❌ |
| Works in CI `dart test` | ✅ | ✅ | ✅ |

---

## License

MIT — see [LICENSE](LICENSE).

---

*Inspired by [ArchUnit](https://www.archunit.org/) (Java) and [arch_test](https://hex.pm/packages/arch_test) (Elixir).*
