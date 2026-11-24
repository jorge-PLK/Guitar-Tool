import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/tab/tab_store.dart';

const projectId = '00000000-0000-0000-0000-000000000001';

late DirectoryFixtureSource fixtures;

Future<void> findFixtures() async {
  final f = await DirectoryFixtureSource.find();
  if (f == null) throw StateError('Sin Contract/fixtures');
  fixtures = f;
}

/// Fixture `tab/<nombre>` entero (también las variantes, que MockCore no carga).
Map<String, Object?> fixture(String name) {
  final text = File('${fixtures.root.path}/tab/$name').readAsStringSync();
  return (json.decode(text) as Map).cast<String, Object?>();
}

Future<MockCore> loadCore() => MockCore.load(fixtures);

/// Proyecto con estudio abierto, escribible desde el test.
final studyProjectProbe = NotifierProvider<StudyProjectProbe, String?>(StudyProjectProbe.new);

class StudyProjectProbe extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

ProviderContainer makeContainer(MockCore core, {String? project = projectId}) {
  final c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    tabStudyProjectProvider.overrideWith((ref) => ref.watch(studyProjectProbe)),
  ]);
  addTearDown(c.dispose);
  if (project != null) c.read(studyProjectProbe.notifier).set(project);
  return c;
}

Future<void> settle() => pumpEventQueue();

/// Atajos de lectura del store de Tablatura sobre un contenedor.
class ProviderContainerHandle {
  ProviderContainerHandle(this.container);
  final ProviderContainer container;
  TabStoreState get state => container.read(tabStoreProvider);
  TabStore get notifier => container.read(tabStoreProvider.notifier);
}
