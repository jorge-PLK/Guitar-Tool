// Banco: Player de fvp (API mdk directa) + Texture + tira de código + muestreador por toImage.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart';
import 'clock.dart';
import 'stats.dart';

const int kStripBits = 12;
const double kBlock = 32; // 64 px del vídeo a escala 0.5
const double kScale = 0.5;

class Rig {
  final Player player = Player();
  final ExtClock clock = ExtClock();
  final GlobalKey stripKey = GlobalKey();
  final ValueNotifier<Size?> texSize = ValueNotifier(null);
  final List<Sample> samples = [];
  Timer? _hb;
  bool _sampling = false;
  bool strip = true;
  int seekFlags = SeekFlag.fromStart | SeekFlag.frame;
  String log = '';

  Future<Map<String, Object?>> open(String path) async {
    clock.emit(seconds: 0, playing: false);
    clock.attach(player);
    player.mute = true;
    player.media = path;
    final r = await player.prepare(flags: SeekFlag(seekFlags));
    final mi = player.mediaInfo;
    final v = mi.video?.isNotEmpty == true ? mi.video![0] : null;
    await player.updateTexture();
    texSize.value = await player.textureSize;
    _hb = Timer.periodic(const Duration(milliseconds: 33), (_) => clock.heartbeat());
    return {
      'prepare': r,
      'textureId': player.textureId.value,
      'textureSize': [texSize.value?.width, texSize.value?.height],
      'codec': v?.codec.codec,
      'codecSize': [v?.codec.width, v?.codec.height],
      'rotation': v?.rotation,
      'videoStartMs': v?.startTime,
      'mediaStartMs': mi.startTime,
      'durationMs': mi.duration,
      'fps': v?.codec.frameRate,
    };
  }

  void play() {
    player.state = PlaybackState.playing;
    clock.emit(playing: true);
  }

  Future<int> jump(double s) {
    clock.emit(seconds: s, jump: true);
    return player.seek(position: (s * 1000).round(), flags: SeekFlag(seekFlags));
  }

  void setRate(double r) => clock.emit(rate: r);

  /// Decodifica la tira. -1 si la referencia blanca/negra no contrasta.
  int _decode(ByteData bd, int w) {
    int g(int bx) {
      var sum = 0;
      for (var dy = -2; dy < 2; dy++) {
        for (var dx = -2; dx < 2; dx++) {
          final x = (kBlock * bx + kBlock / 2).round() + dx, y = (kBlock / 2).round() + dy;
          sum += bd.getUint8((y * w + x) * 4 + 1);
        }
      }
      return sum ~/ 16;
    }

    final white = g(12), black = g(13);
    if (white - black < 100) return -1;
    final thr = (white + black) / 2;
    var n = 0;
    for (var k = 0; k < kStripBits; k++) {
      if (g(k) > thr) n |= 1 << k;
    }
    return n;
  }

  void startSampling() {
    _sampling = true;
    () async {
      while (_sampling) {
        final ro = stripKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (ro != null && !ro.debugNeedsPaint) {
          final t0 = nowS();
          final img = await ro.toImage(pixelRatio: 1.0);
          final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          final t1 = nowS();
          if (bd != null) {
            final n = _decode(bd, img.width);
            final tm = (t0 + t1) / 2;
            samples.add(Sample(tm, n, t1 - t0, clock.pos(tm)));
          }
          img.dispose();
        }
        SchedulerBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame;
      }
    }();
  }

  void stopSampling() => _sampling = false;

  Future<void> dispose() async {
    _sampling = false;
    _hb?.cancel();
    player.dispose();
  }

  Widget view({bool showStrip = true}) {
    return ValueListenableBuilder<int?>(
      valueListenable: player.textureId,
      builder: (context, id, _) {
        final sz = texSize.value;
        if (id == null || sz == null) return const SizedBox.shrink();
        final tex = Texture(textureId: id);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showStrip)
            RepaintBoundary(
              key: stripKey,
              child: SizedBox(
                width: kBlock * 14,
                height: kBlock,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: sz.width * kScale,
                    maxHeight: sz.height * kScale,
                    child: SizedBox(width: sz.width * kScale, height: sz.height * kScale, child: tex),
                  ),
                ),
              ),
            ),
          Expanded(child: Center(child: AspectRatio(aspectRatio: sz.width / sz.height, child: Texture(textureId: id)))),
        ]);
      },
    );
  }
}
