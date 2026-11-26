import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Los goldens se generan y comparan solo en macOS (docs/flutter/orquestador.md,
/// «Riesgos que vigilar»): el rasterizado de texto difiere en Windows. En otras
/// plataformas `matchesGoldenFile` da por buena la comparación y el resto de
/// aserciones del test siguen corriendo. En macOS no cambia nada.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!Platform.isMacOS && goldenFileComparator is LocalFileComparator) {
    goldenFileComparator = _SkipGoldenComparator(
      goldenFileComparator as LocalFileComparator,
    );
  }
  await testMain();
}

class _SkipGoldenComparator extends LocalFileComparator {
  _SkipGoldenComparator(LocalFileComparator base)
    : super(Uri.parse('${base.basedir}placeholder_test.dart'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}
