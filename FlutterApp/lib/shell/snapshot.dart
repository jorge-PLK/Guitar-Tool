import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_providers.dart';

import 'shell_providers.dart';

/// Retardo por defecto de `--snapshot` (`LaunchOptions.defaultSnapshotDelay` de AppCore).
const double defaultSnapshotDelay = 2.0;

/// Vuelca [boundary] a PNG al tamaño lógico × [pixelRatio] y lo escribe en [path].
Future<void> writeBoundaryPng(RenderRepaintBoundary boundary, double pixelRatio, String path) async {
  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('toByteData devolvió null');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
  } finally {
    image.dispose();
  }
}

/// Raíz de la app: `RepaintBoundary` y, con `--snapshot <png>`, captura tras el primer fotograma y el retardo
/// y sale (cerrando el núcleo con [appExitProvider]).
class SnapshotHost extends ConsumerStatefulWidget {
  const SnapshotHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SnapshotHost> createState() => _SnapshotHostState();
}

class _SnapshotHostState extends ConsumerState<SnapshotHost> {
  final GlobalKey _key = GlobalKey(debugLabel: 'snapshotBoundary');

  @override
  void initState() {
    super.initState();
    final o = ref.read(launchOptionsProvider);
    final path = o.snapshot;
    if (path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture(path, o.snapshotDelay ?? defaultSnapshotDelay));
    }
  }

  Future<void> _capture(String path, double delaySeconds) async {
    final exit = ref.read(appExitProvider);
    try {
      await Future<void>.delayed(Duration(milliseconds: (delaySeconds * 1000).round()));
      if (!mounted) return;
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('sin RepaintBoundary raíz');
      await writeBoundaryPng(boundary, View.of(context).devicePixelRatio, path);
      debugPrint('tf: captura $path');
    } catch (e, st) {
      debugPrint('tf: la captura falló: $e\n$st');
    } finally {
      await exit();
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(key: _key, child: widget.child);
}
