// P9.4/P9.7h: un unico punto de salida JS->Dart para los tres canales. probe.js y las paginas siempre llaman a
// window.webkit.messageHandlers.tf.postMessage(obj); aqui se encamina segun la plataforma y siempre se entrega un string JSON:
//  - macOS (WKWebView): el plugin entrega message.body.toString(), asi que se envuelve postMessage con JSON.stringify.
//  - Windows webview_all: addJavaScriptChannel('tf') inyecta window.tf.postMessage(String) (usa chrome.webview por debajo).
//  - Windows webview_flutter_windows: no hay canal con nombre; el stream webMessage recoge window.chrome.webview.postMessage.
(function () {
  function str(o) { return typeof o === 'string' ? o : JSON.stringify(o); }
  try {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tf) {
      var h = window.webkit.messageHandlers.tf;
      var orig = h.postMessage.bind(h);
      h.postMessage = function (o) { return orig(str(o)); };
      window.__shimOk = (window.webkit.messageHandlers.tf.postMessage !== orig);
      window.__shimVia = 'webkit';
      return;
    }
    window.webkit = window.webkit || {};
    window.webkit.messageHandlers = window.webkit.messageHandlers || {};
    window.webkit.messageHandlers.tf = {
      postMessage: function (o) {
        var s = str(o);
        if (window.tf && typeof window.tf.postMessage === 'function') return window.tf.postMessage(s);
        if (window.chrome && window.chrome.webview) return window.chrome.webview.postMessage(s);
        throw new Error('sin canal JS->Dart (ni window.tf ni chrome.webview)');
      }
    };
    window.__shimVia = (window.tf && typeof window.tf.postMessage === 'function') ? 'window.tf' : 'chrome.webview';
    window.__shimOk = true;
  } catch (e) { window.__shimOk = false; window.__shimErr = String(e); }

  // Teclado (solo Flutter). En SwiftUI un monitor local de NSEvent ve cada keyDown antes que el WKWebView; aqui, si el
  // WebView tiene el foco, la tecla no llega a Flutter y el navegador haria su accion (Espacio = desplazar). Se reenvia
  // a Dart como {event:'key'} y se cancela la accion por defecto (salvo en campos de texto y con solo modificadores).
  var MODS = { Shift: 1, Control: 1, Alt: 1, Meta: 1, CapsLock: 1, Fn: 1, AltGraph: 1 };
  window.addEventListener('keydown', function (e) {
    try {
      if (MODS[e.key]) return;
      var t = e.target, tag = t && t.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || (t && t.isContentEditable)) return;
      e.preventDefault();
      if (e.repeat && e.key === ' ') return;
      window.webkit.messageHandlers.tf.postMessage({ event: 'key', key: e.key, code: e.code,
        shift: e.shiftKey, ctrl: e.ctrlKey, meta: e.metaKey, alt: e.altKey });
    } catch (x) { /* sin canal */ }
  }, true);
})();
