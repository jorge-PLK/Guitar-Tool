import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:toneforge/widgets/tf_web_view.dart';

/// Controlador falso: registra las llamadas y deja simular mensajes JS->Dart. No usa el plugin.
class FakeWebViewController implements TfWebViewController {
  FakeWebViewController(this.config);

  final TfWebViewConfig config;

  /// Llamadas en orden: `loadFile:<ruta>`, `loadUrl:<url>`, `run:<js>`, `eval:<js>`, `reclaim`, `dispose`.
  final List<String> calls = <String>[];

  /// Resultado de `evaluateJavaScript` por JS exacto.
  final Map<String, Object?> evalResults = <String, Object?>{};

  final ValueNotifier<bool> _ready = ValueNotifier<bool>(true);

  @override
  ValueListenable<bool> get ready => _ready;

  void setReady(bool value) => _ready.value = value;

  /// Simula `tf.postMessage(JSON.stringify(json))` desde la página.
  void simulateMessage(Object? json) => simulateRawMessage(jsonEncode(json));

  /// Simula un mensaje en bruto (si no es JSON, va a `onError` como en el controlador real).
  void simulateRawMessage(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      config.onError?.call('mensaje no JSON: $raw');
      return;
    }
    config.onMessage?.call(json);
  }

  void simulatePageFinished(String url) => config.onPageFinished?.call(url);

  @override
  Future<void> loadFile(String absolutePath) async => calls.add('loadFile:$absolutePath');

  @override
  Future<void> loadUrl(Uri url) async => calls.add('loadUrl:$url');

  @override
  Future<void> runJavaScript(String js) async => calls.add('run:$js');

  @override
  Future<Object?> evaluateJavaScript(String js) async {
    calls.add('eval:$js');
    return evalResults[js];
  }

  @override
  Future<void> reclaimFocus() async => calls.add('reclaim');

  @override
  Widget buildView(BuildContext context) => const SizedBox.expand(key: ValueKey<String>('fake-web-view'));

  @override
  void dispose() {
    calls.add('dispose');
    _ready.dispose();
  }
}

/// Override para tests: cada controlador creado por la fábrica queda en [created].
class FakeWebViewFactory {
  final List<FakeWebViewController> created = <FakeWebViewController>[];

  TfWebViewController call(TfWebViewConfig config) {
    final c = FakeWebViewController(config);
    created.add(c);
    return c;
  }

  /// `ProviderScope(overrides: [factory.override])`.
  Override get override => tfWebViewControllerFactoryProvider.overrideWithValue(call);
}
