import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/widgets/tf_web_view.dart';

import 'host_services.dart';
import 'songsterr_hidden_host.dart' show HiddenWebPage;

/// Busca el `Overlay` raíz de la app (el del `Navigator` de `MaterialApp`) sin necesitar un `BuildContext`.
typedef OverlayLocator = OverlayState? Function();

OverlayState? findRootOverlay() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  OverlayState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is OverlayState) {
      found = e.state as OverlayState;
      return;
    }
    e.visitChildElements(visit);
  }

  visit(root);
  return found;
}

/// Página oculta para Windows (WebView2 no tiene sesión sin ventana): monta un [TfWebView] invisible en el
/// `Overlay` raíz y lo retira en [close]. Ocupa [size] (WebView2 necesita tamaño > 0 para navegar; 1200x800 como
/// el anfitrión del Mac) con `Opacity(0)` + `IgnorePointer` + sin semántica, así que no cambia el layout ni
/// recibe eventos. El almacén de WebView2 es el de la app (el plugin solo admite un entorno por proceso).
class OverlayWebPage implements HiddenWebPage {
  OverlayWebPage._(this._overlay, this._factory, this.size);

  final OverlayState _overlay;
  final TfWebViewControllerFactory _factory;
  final Size size;
  TfWebViewController? _controller;
  OverlayEntry? _entry;
  bool _closed = false;

  /// Número de entradas montadas por páginas de este tipo (para tests).
  @visibleForTesting
  static int mounted = 0;

  static Future<HiddenWebPage> create({
    OverlayLocator locate = findRootOverlay,
    TfWebViewControllerFactory? controllerFactory,
    Size size = const Size(1200, 800),
  }) async {
    final overlay = locate();
    if (overlay == null) throw const HostError('unsupported', 'No hay Overlay donde montar la página oculta.');
    final TfWebViewControllerFactory resolved;
    if (controllerFactory != null) {
      resolved = controllerFactory;
    } else {
      resolved = ProviderScope.containerOf(overlay.context, listen: false).read(tfWebViewControllerFactoryProvider);
    }
    return OverlayWebPage._(overlay, resolved, size);
  }

  @override
  Future<int?> navigate(Uri url, {String? userAgent}) {
    if (_closed) return Future.error(const HostError('offline', 'Página cerrada.'));
    final done = Completer<int?>();
    final target = url.toString();
    final c = _controller = _factory(TfWebViewConfig(
      userAgent: userAgent,
      onPageFinished: (_) {
        if (!done.isCompleted) done.complete(null);
      },
      // Sin distinguir documento principal de subrecursos: solo falla si el error nombra la URL pedida.
      // Cualquier otro caso acaba por el tope de la navegación (el anfitrión lo traduce a `offline`).
      onError: (d) {
        if (!done.isCompleted && d.contains(target)) done.completeError(HostError('offline', d));
      },
    ));
    final entry = _entry = OverlayEntry(
      maintainState: true,
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        width: size.width,
        height: size.height,
        child: ExcludeSemantics(
          child: IgnorePointer(child: Opacity(opacity: 0, child: TfWebView(controller: c))),
        ),
      ),
    );
    _overlay.insert(entry);
    mounted++;
    unawaited(c.loadUrl(url).catchError((Object e) {
      if (!done.isCompleted) done.completeError(HostError('offline', '$e'));
    }));
    return done.future;
  }

  @override
  Future<bool> evaluateBool(String js) async {
    final c = _controller;
    if (c == null || _closed) return false;
    try {
      final v = await c.evaluateJavaScript(js);
      if (v is bool) return v;
      final s = '$v'.trim().toLowerCase();
      return s == 'true' || s == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> outerHtml() async {
    final c = _controller;
    if (c == null || _closed) throw const HostError('offline', 'Página cerrada.');
    final v = await c.evaluateJavaScript('document.documentElement.outerHTML');
    return '$v';
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
      mounted--;
    }
    _controller?.dispose();
    _controller = null;
  }
}
