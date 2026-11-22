import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tamaño lógico por defecto de la captura.
const kSnapshotSize = Size(1440, 900);

/// Factor de píxeles fijo: la captura mide tamaño lógico x 1.0, sin depender
/// del devicePixelRatio del monitor.
const kSnapshotPixelRatio = 1.0;

class SnapshotArgs {
  const SnapshotArgs({
    required this.path,
    required this.delay,
    required this.size,
  });

  final String path;
  final double delay;
  final Size size;

  /// null si no hay `--snapshot`.
  static SnapshotArgs? parse(List<String> args) {
    String? opt(String n) {
      final i = args.indexOf(n);
      return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
    }

    final path = opt('--snapshot');
    if (path == null) return null;
    var size = kSnapshotSize;
    final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(opt('--window') ?? '');
    if (m != null) {
      size = Size(double.parse(m[1]!), double.parse(m[2]!));
    }
    return SnapshotArgs(
      path: path,
      delay: double.tryParse(opt('--snapshot-delay') ?? '') ?? 2.0,
      size: size,
    );
  }
}

void runSnapshot(SnapshotArgs a) {
  final key = GlobalKey();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        // La ventana no se puede fijar sin plugin: el contenido tiene tamaño
        // lógico fijo y se escala para verse; la captura usa el tamaño propio.
        child: FittedBox(
          fit: BoxFit.contain,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: a.size.width,
              height: a.size.height,
              child: const ProbeScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(_capture(key, a));
}

Future<void> _capture(GlobalKey key, SnapshotArgs a) async {
  var code = 0;
  try {
    await Future<void>.delayed(Duration(milliseconds: (a.delay * 1000).round()));
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: kSnapshotPixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(a.path).writeAsBytes(data!.buffer.asUint8List(), flush: true);
  } catch (e) {
    stderr.writeln('snapshot failed: $e');
    code = 1;
  }
  exit(code);
}

/// Pantalla de prueba fija, pensada para que se note un render roto.
class ProbeScreen extends StatelessWidget {
  const ProbeScreen({super.key});

  static const _bg = Color(0xFF14161A);
  static const _fg = Color(0xFFE8EAED);
  static const _accent = Color(0xFFFF8A3D);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            color: _fg,
            height: 1.4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ToneForge Afinador 0123',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w700,
                  fontSize: 48,
                ),
              ),
              const SizedBox(height: 16),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: 'Inter regular: el veloz murciélago hindú comía ',
                  ),
                  TextSpan(
                    text: 'feliz cardillo y kiwi, ',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: 'la cigüeña tocaba el saxofón. Wxilmg 0123456789.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _grid()),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF3D5AFE),
                                    _accent,
                                    Color(0xFF00C853),
                                  ],
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Expanded(
                            child: CustomPaint(
                              painter: _LinesPainter(),
                              child: SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid() {
    return Column(
      children: [
        for (var r = 0; r < 4; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < 8; c++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ((r + c) % 2 == 0)
                              ? const Color(0xFF1F2329)
                              : const Color(0xFF262B33),
                          border: Border.all(color: _accent, width: 1),
                          borderRadius: BorderRadius.circular(2.0 + c * 2),
                        ),
                        child: Center(
                          child: Text(
                            '${r * 8 + c}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinesPainter extends CustomPainter {
  const _LinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = const Color(0xFFE8EAED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i <= 12; i++) {
      final y = size.height * i / 12;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thin);
    }
    for (var i = 0; i <= 24; i++) {
      final x = size.width * i / 24;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thin);
    }
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), thin);
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * 0.35,
      Paint()
        ..color = const Color(0xFFFF8A3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * 0.15,
      Paint()..color = const Color(0x99FF8A3D),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
