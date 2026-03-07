// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dart_arch_test/dart_arch_test.dart';

/// Example showing how to use dart_arch_test in a real project.
///
/// In a real project you would put these inside `test/architecture_test.dart`
/// and run with `dart test` or `flutter test`.
///
/// This file is a standalone script that demonstrates all major rules
/// using an in-memory graph — no real source files needed.
Future<void> main() async {
  // ─── In-memory graph mimicking a Flutter feature-first project ─────────────
  //
  //   features/home/   → features/auth/      (allowed: home uses auth)
  //   features/home/   → domain/             (allowed: home uses domain)
  //   domain/          → data/               (VIOLATION in onion: inner → outer)
  //   features/auth/   → (no deps)
  //   data/            → (no deps)
  //
  final graph = <String, Set<String>>{
    'package:my_app/features/home/home_screen.dart': {
      'package:my_app/features/home/home_provider.dart',
    },
    'package:my_app/features/home/home_provider.dart': {
      'package:my_app/features/auth/auth_service.dart',
      'package:my_app/domain/home_model.dart',
    },
    'package:my_app/features/auth/auth_screen.dart': {},
    'package:my_app/features/auth/auth_service.dart': {},
    'package:my_app/domain/home_model.dart': {
      'package:my_app/data/home_repository.dart', // inner→outer: onion violation
    },
    'package:my_app/data/home_repository.dart': {},
  };

  // ─── 1. Feature slices must not cross-import each other ────────────────────
  print('--- slice isolation ---');
  try {
    defineSlices({
          'home': 'features/home/**',
          'auth': 'features/auth/**',
          'domain': 'domain/**',
          'data': 'data/**',
        })
        .allowDependency('home', 'auth')
        .allowDependency('home', 'domain')
        .enforceIsolation(graph);
    print('✓ Slices are isolated');
  } on ArchTestFailure catch (e) {
    print('✗ $e');
  }

  // ─── 2. Dependency direction (layered architecture) ─────────────────────────
  print('\n--- layer direction ---');
  try {
    defineLayers({
      'presentation': 'features/**',
      'domain': 'domain/**',
      'data': 'data/**',
    }).enforceDirection(graph);
    print('✓ Layers respect direction');
  } on ArchTestFailure catch (e) {
    print('✗ $e');
  }

  // ─── 3. Onion / hexagonal rules ─────────────────────────────────────────────
  print('\n--- onion rules (expects violation) ---');
  try {
    defineOnion({
      'domain': 'domain/**', // innermost
      'presentation': 'features/**', // outer
      'data': 'data/**', // outermost
    }).enforceOnionRules(graph);
    print('✓ Onion rules satisfied');
  } on ArchTestFailure catch (e) {
    // domain → data is a violation (inner importing outer)
    print('✗ Expected violation: ${e.violations.first}');
  }

  // ─── 4. No cycles ────────────────────────────────────────────────────────────
  print('\n--- cycle detection ---');
  try {
    shouldBeFreeOfCycles(allFiles(), graph);
    print('✓ No cycles found');
  } on ArchTestFailure catch (e) {
    print('✗ $e');
  }

  // ─── 5. Transitive isolation ─────────────────────────────────────────────────
  print('\n--- transitive dependency ---');
  try {
    shouldNotTransitivelyDependOn(
      filesMatching('features/**'),
      filesMatching('data/**'),
      graph,
    );
    print('✓ Features do not transitively reach data layer');
  } on ArchTestFailure catch (e) {
    print('✗ ${e.violations.length} transitive violation(s)');
  }

  // ─── 6. shouldOnlyBeCalledBy ─────────────────────────────────────────────────
  print('\n--- caller control ---');
  try {
    shouldOnlyBeCalledBy(
      filesMatching('features/auth/**'),
      filesMatching('features/home/**'),
      graph,
    );
    print('✓ auth is only imported by home');
  } on ArchTestFailure catch (e) {
    print('✗ $e');
  }

  print(
    '\nDone. In a real test suite every rule above lives in test() blocks.',
  );
  exit(0);
}
