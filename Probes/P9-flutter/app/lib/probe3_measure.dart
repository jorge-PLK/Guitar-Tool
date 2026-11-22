import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'ffi/tf_core.dart';
import 'probe2_util.dart';

double rssMb() =>
    double.parse((ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1));

/// Superficie de vídeo: textura externa o imagen decodificada, a su tamaño lógico.
class Probe3Surface {
  Probe3Surface(this.width, this.height);
  final int width;
  final int height;
  final textureId = ValueNotifier<int?>(null);
  final image = ValueNotifier<ui.Image?>(null);
}

class Probe3View extends StatelessWidget {
  const Probe3View({super.key, required this.surface});
  final Probe3Surface surface;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Center(
          child: FittedBox(
            child: SizedBox(
              width: surface.width.toDouble(),
              height: surface.height.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<int?>(
                    valueListenable: surface.textureId,
                    builder: (_, id, _) =>
                        id == null ? const SizedBox.shrink() : Texture(textureId: id),
                  ),
                  ValueListenableBuilder<ui.Image?>(
                    valueListenable: surface.image,
                    builder: (_, img, _) =>
                        img == null ? const SizedBox.shrink() : RawImage(image: img),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// FrameTiming de Flutter (lotes con retraso): solo acumula mientras `active`.
class FrameTimings {
  bool active = false;
  final _build = <double>[];
  final _raster = <double>[];
  final _total = <double>[];

  void start() => SchedulerBinding.instance.addTimingsCallback((ts) {
        if (!active) return;
        for (final t in ts) {
          _build.add(t.buildDuration.inMicroseconds / 1000);
          _raster.add(t.rasterDuration.inMicroseconds / 1000);
          _total.add(t.totalSpan.inMicroseconds / 1000);
        }
      });

  Map<String, Object?> toJson() => {
        'frames': _total.length,
        'over16_7ms': _total.where((x) => x > 16.7).length,
        'buildMs': stats(_build),
        'rasterMs': stats(_raster),
        'totalMs': stats(_total),
      };
}

final _getrusage = Platform.isMacOS
    ? DynamicLibrary.process().lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)>('getrusage')
    : null;

/// CPU (usuario + sistema) acumulada del proceso, en segundos. NaN si no hay getrusage.
double cpuSeconds() {
  final f = _getrusage;
  if (f == null) return double.nan;
  final p = nativeCalloc(256);
  try {
    f(0, p); // RUSAGE_SELF; timeval macOS = {int64 sec, int32 usec, pad}
    final b = ByteData.sublistView(p.asTypedList(256));
    double tv(int o) =>
        b.getInt64(o, Endian.little) + b.getInt32(o + 8, Endian.little) / 1e6;
    return tv(0) + tv(16);
  } finally {
    nativeFree(p);
  }
}
