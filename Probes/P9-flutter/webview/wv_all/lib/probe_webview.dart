// P9.4: unica capa que conoce el paquete WebView. El resto de lib/ es identico en wv_all y wv_flutter.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_all/webview_all.dart';

class ProbeWebView {
  ProbeWebView({
    required this.onMessage,
    required this.onConsole,
    required this.onPageFinished,
    required this.onError,
  });

  static const candidate = 'wv_all';
  static const channelName = 'tf';

  final void Function(String raw) onMessage;
  final void Function(String level, String message) onConsole;
  final void Function(String url) onPageFinished;
  final void Function(String description) onError;

  late final WebViewController _c;
  String serving = '';

  Future<void> init({String? userAgent}) async {
    _c = WebViewController();
    await _c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _c.setNavigationDelegate(NavigationDelegate(
      onPageFinished: onPageFinished,
      onWebResourceError: (e) => onError('${e.errorCode} ${e.description} ${e.url}'),
    ));
    await _c.setOnConsoleMessage((m) => onConsole(m.level.name, m.message));
    await _c.addJavaScriptChannel(channelName, onMessageReceived: (m) => onMessage(m.message));
    if (userAgent != null) await _c.setUserAgent(userAgent);
  }

  /// Carga un asset de Flutter; si el paquete no lo resuelve, cae a loadFile sobre flutter_assets del .app.
  Future<void> loadAsset(String key) async {
    try {
      await _c.loadFlutterAsset(key);
      serving = 'loadFlutterAsset (file://, lectura concedida a la carpeta del asset)';
    } catch (e) {
      final root = File(Platform.resolvedExecutable).parent.parent.path;
      await _c.loadFile('$root/Frameworks/App.framework/Resources/flutter_assets/$key');
      serving = 'loadFile en flutter_assets (loadFlutterAsset fallo: $e)';
    }
  }

  Future<void> loadHtml(String html) => _c.loadHtmlString(html);
  Future<void> loadUrl(String url) => _c.loadRequest(Uri.parse(url));
  Future<void> run(String js) => _c.runJavaScript(js);
  Future<String> eval(String js) async => (await _c.runJavaScriptReturningResult(js)).toString();
  Future<String> userAgentFromPlugin() async => '${await _c.getUserAgent()}';

  /// Sesion fuera de arbol que ofrece el paquete (si la ofrece).
  Future<String> offscreenSupport() async => 'isOffscreenWebViewSupported=${await _c.isOffscreenWebViewSupported()}';

  Widget widget() => WebViewWidget(controller: _c);
}
