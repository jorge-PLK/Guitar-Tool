// P9.4: el plugin entrega message.body.toString(): se envia siempre JSON.stringify(obj).
(function () {
  try {
    var h = window.webkit.messageHandlers.tf;
    var orig = h.postMessage.bind(h);
    h.postMessage = function (o) { return orig(typeof o === 'string' ? o : JSON.stringify(o)); };
    window.__shimOk = (window.webkit.messageHandlers.tf.postMessage !== orig);
  } catch (e) { window.__shimOk = false; window.__shimErr = String(e); }
})();
