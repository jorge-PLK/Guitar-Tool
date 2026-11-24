import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:webview_all/webview_all.dart' as wv;
import 'package:webview_all_windows/webview_all_windows.dart' show WindowsWebViewController;

/// Opciones de un WebView (ver `docs/flutter/arquitectura.md`, «WebView»).
class TfWebViewConfig {
  const TfWebViewConfig({
    this.channelName = 'tf',
    this.userAgent,
    this.onMessage,
    this.onPageFinished,
    this.onError,
    this.onConsole,
  });

  /// Nombre del manejador JS->Dart: la página llama a `<channelName>.postMessage(JSON.stringify(...))`.
  final String channelName;

  /// User agent fijo (Songsterr); nulo = el del motor.
  final String? userAgent;

  /// Mensaje JS->Dart ya decodificado (JSON). Un texto que no es JSON llega por [onError].
  final void Function(Object? json)? onMessage;
  final void Function(String url)? onPageFinished;
  final void Function(String description)? onError;
  final void Function(String level, String message)? onConsole;
}

/// Controlador del WebView que ven las pantallas: oculta `webview_all` y se sustituye por un falso en tests.
/// Todas las operaciones esperan a que el motor esté listo, así que se pueden llamar nada más crearlo.
abstract class TfWebViewController {
  /// `true` cuando el motor está creado y la vista se puede montar.
  ValueListenable<bool> get ready;

  /// Carga un fichero local (alphaTab: `tab.html`; el motor da lectura a su carpeta).
  Future<void> loadFile(String absolutePath);

  /// Carga una URL remota (vista previa de Songsterr).
  Future<void> loadUrl(Uri url);

  /// Dart->JS sin resultado.
  Future<void> runJavaScript(String js);

  /// Dart->JS con resultado: devuelve el valor decodificado (JSON si lo es; si no, el texto).
  Future<Object?> evaluateJavaScript(String js);

  /// Devuelve el foco de teclado a la vista de Flutter (tras un clic en la página).
  Future<void> reclaimFocus();

  /// La vista nativa (transparente). No pedir foco: lo evita [TfWebView].
  Widget buildView(BuildContext context);

  void dispose();
}

/// Crea controladores. Los tests lo sobrescriben con el falso de `test/support/fake_web_view.dart`.
typedef TfWebViewControllerFactory = TfWebViewController Function(TfWebViewConfig config);

/// Fábrica real: `webview_all`. En Windows la carpeta de datos de WebView2 cuelga de `--support-dir`.
final tfWebViewControllerFactoryProvider = Provider<TfWebViewControllerFactory>((ref) {
  final support = ref.watch(launchOptionsProvider).supportDir;
  final dir = support == null ? null : '$support${Platform.pathSeparator}WebView2';
  return (config) => PluginWebViewController(config, userDataDir: dir);
});

/// Superficie del WebView. Nunca toma el foco de teclado: queda excluido del árbol de foco y, al soltar el
/// puntero sobre la página, se devuelve el primer respondedor a Flutter (P9 prueba 4).
class TfWebView extends StatelessWidget {
  const TfWebView({super.key, required this.controller});

  final TfWebViewController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.expand();
        return ExcludeFocus(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerUp: (_) => unawaited(controller.reclaimFocus()),
            child: controller.buildView(context),
          ),
        );
      },
    );
  }
}

/// Implementación con `webview_all` (única capa que conoce el paquete).
class PluginWebViewController implements TfWebViewController {
  PluginWebViewController(this.config, {this.userDataDir}) {
    _ready = _init();
  }

  final TfWebViewConfig config;
  final String? userDataDir;

  static const MethodChannel _focusChannel = MethodChannel('tf/focus');
  static Future<void>? _environment;

  late final Future<void> _ready;
  late final wv.WebViewController _c;
  final ValueNotifier<bool> _isReady = ValueNotifier<bool>(false);
  bool _disposed = false;

  @override
  ValueListenable<bool> get ready => _isReady;

  /// Una vez por proceso y antes del primer controlador (solo Windows).
  Future<void> _ensureEnvironment() {
    final dir = userDataDir;
    if (!Platform.isWindows || dir == null) return Future<void>.value();
    return _environment ??= () async {
      try {
        await Directory(dir).create(recursive: true);
        await WindowsWebViewController.ensureEnvironment(userDataPath: dir);
      } catch (e) {
        config.onError?.call('WebView2 userDataPath: $e');
      }
    }();
  }

  Future<void> _init() async {
    await _ensureEnvironment();
    final c = _c = wv.WebViewController();
    await c.setJavaScriptMode(wv.JavaScriptMode.unrestricted);
    try {
      await c.setBackgroundColor(TfColors.bg.withValues(alpha: 0));
    } catch (e) {
      config.onError?.call('setBackgroundColor: $e');
    }
    await c.setNavigationDelegate(wv.NavigationDelegate(
      onPageFinished: (url) => config.onPageFinished?.call(url),
      onWebResourceError: (e) => config.onError?.call('${e.errorCode} ${e.description} ${e.url}'),
    ));
    await c.setOnConsoleMessage((m) => config.onConsole?.call(m.level.name, m.message));
    await c.addJavaScriptChannel(config.channelName, onMessageReceived: (m) {
      final Object? json;
      try {
        json = jsonDecode(m.message);
      } catch (_) {
        config.onError?.call('mensaje no JSON: ${m.message}');
        return;
      }
      config.onMessage?.call(json);
    });
    final ua = config.userAgent;
    if (ua != null) await c.setUserAgent(ua);
    if (!_disposed) _isReady.value = true;
  }

  @override
  Future<void> loadFile(String absolutePath) async {
    await _ready;
    await _c.loadFile(absolutePath);
  }

  @override
  Future<void> loadUrl(Uri url) async {
    await _ready;
    await _c.loadRequest(url);
  }

  @override
  Future<void> runJavaScript(String js) async {
    await _ready;
    await _c.runJavaScript(js);
  }

  @override
  Future<Object?> evaluateJavaScript(String js) async {
    await _ready;
    return decodeJsResult((await _c.runJavaScriptReturningResult(js)).toString());
  }

  /// Windows entrega el resultado ya decodificado una vez; Mac, como JSON. Se decodifica mientras sea JSON válido.
  @visibleForTesting
  static Object? decodeJsResult(String raw) {
    Object? v = raw;
    for (var i = 0; i < 3 && v is String; i++) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        break;
      }
    }
    return v;
  }

  @override
  Future<void> reclaimFocus() async {
    if (!Platform.isMacOS) return;
    try {
      await _focusChannel.invokeMethod<bool>('reclaim');
    } on MissingPluginException {
      // el runner aún no tiene el canal: sin efecto
    }
  }

  @override
  Widget buildView(BuildContext context) => wv.WebViewWidget(controller: _c);

  @override
  void dispose() {
    _disposed = true;
    _isReady.dispose();
  }
}
