import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/tab/tab_canvas_controller.dart';
import 'package:toneforge/widgets/tf_web_view.dart';

/// Lienzo alphaTab: monta el WebView del [tabCanvasProvider]. Lo coloca el escenario de la pantalla.
class TabCanvas extends ConsumerWidget {
  const TabCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(tabCanvasProvider.notifier).web;
    return TfWebView(controller: controller);
  }
}
