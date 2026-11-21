// Lienzo alphaTab en un <iframe> del mismo origen. Reproduce en JS el puente Swift <-> JS del Mac (App/Sources/TabWebHost.swift):
//  - `tf-bridge.js` (compartido, intacto) envía eventos con `window.webkit.messageHandlers.tf.postMessage(...)`: aquí se define
//    ese objeto falso en el `contentWindow` ANTES de cargar `alphaTab/tab.html` y se reenvía a `onEvent`.
//  - Donde el Mac hacía `evaluateJavaScript("TF.x(...)")`, aquí se llama a `contentWindow.TF.x(...)`.
// Para definir el objeto antes de que corran los scripts de tab.html, la página se descarga y se escribe con document.open/write
// sobre el documento inicial del iframe (la misma Window; con `src` la navegación la sustituiría). `<base>` hace que sus rutas
// relativas (alphaTab.min.js, tf-bridge.js, font/) cuelguen de `alphaTab/`.

const TAB_HTML = 'alphaTab/tab.html';

/// Define `webkit.messageHandlers.tf` en la ventana del iframe. En WebView2 no existe `window.webkit`; en el WKWebView del Mac
/// de desarrollo (tf-webdev) sí, con propiedades no configurables: allí se sustituye `postMessage` del manejador `tf` real.
function installHandler(win, handler) {
  try {
    Object.defineProperty(win, 'webkit', { value: { messageHandlers: { tf: handler } }, configurable: true, writable: true });
    return;
  } catch { /* WKWebView: sigue abajo */ }
  const mh = win.webkit?.messageHandlers;
  const tf = mh?.tf;
  if (!tf) throw new Error('No se pudo definir webkit.messageHandlers en el iframe');
  // Las envolturas de WebKit se recrean si nadie las retiene: se guardan para que `postMessage` sustituido sobreviva.
  handler.keep = [win.webkit, mh, tf];
  try { tf.postMessage = handler.postMessage; } catch { /* sigue */ }
  if (tf.postMessage !== handler.postMessage) {
    Object.defineProperty(Object.getPrototypeOf(tf), 'postMessage', { value: handler.postMessage, configurable: true, writable: true });
  }
}

export class AlphaFrame {
  /// `onEvent({event: 'ready'|'rendered'|'beatClick'|'beatDrag'|'noteClick'|'error'|'cursor', ...})`, `onKey(KeyboardEvent)`.
  constructor(container, { onEvent, onKey }) {
    this.onEvent = onEvent;
    this.onKey = onKey;
    this.ready = false;
    this.rendered = false;
    this.pendingLoad = null;
    this.lastCursor = null;
    this.lastSelection = null;
    this.lastRange = null;
    this.dead = false;
    this.iframe = document.createElement('iframe');
    this.iframe.className = 'tab-frame';
    this.iframe.title = 'Partitura';
    container.appendChild(this.iframe);
    this.mounted = this.mount();
  }

  async mount() {
    try {
      const handler = this.handler = { postMessage: m => this.receive(m) };   // retenido: ver installHandler
      const res = await fetch(TAB_HTML);
      if (!res.ok) throw new Error(`${TAB_HTML}: HTTP ${res.status}`);
      const text = await res.text();
      if (this.dead) return;
      const base = new URL('alphaTab/', location.href).href;
      const doc = this.iframe.contentDocument;
      doc.open();
      installHandler(this.iframe.contentWindow, handler);   // después de open(): WebKit reinicia `webkit` al abrir el documento
      doc.write(text.replace(/<head>/i, `<head><base href="${base}">`));
      doc.close();
      this.iframe.contentWindow.addEventListener('keydown', e => this.onKey?.(e));
    } catch (e) {
      this.onEvent({ event: 'error', message: String(e?.message ?? e) });
    }
  }

  receive(m) {
    if (this.dead || !m || typeof m !== 'object') return;
    if (m.event === 'ready') { this.ready = true; this.flushLoad(); }
    else if (m.event === 'rendered') {
      this.rendered = true;
      if (this.lastCursor) this.run('setCursorTime', ...this.lastCursor);
      if (this.lastSelection) this.run('setSelection', ...this.lastSelection);
      if (this.lastRange) this.run('setRange', ...this.lastRange);
    }
    this.onEvent(m);
  }

  run(name, ...args) {
    try {
      const TF = this.iframe.contentWindow?.TF;
      if (!TF) return undefined;
      return TF[name](...args);
    } catch (e) {
      this.onEvent({ event: 'error', message: `TF.${name}: ${e?.message ?? e}` });
      return undefined;
    }
  }

  flushLoad() {
    if (!this.ready || !this.pendingLoad) return;
    const [json, track] = this.pendingLoad;
    this.pendingLoad = null;
    this.rendered = false;
    this.run('load', json, track);
  }

  /// `TF.load(json, trackIndex)`: construye la partitura entera y pinta la pista `track` (espera a `ready`).
  load(json, track) { this.pendingLoad = [json, track]; this.flushLoad(); }

  setCursorTime(seconds, follow = true) {
    this.lastCursor = [seconds, follow];
    if (this.rendered) this.run('setCursorTime', seconds, follow);
  }

  /// Marcador de selección en `bar` a `fraction` del compás; `bar < 0` lo oculta.
  setSelection(bar, fraction) {
    this.lastSelection = [bar, fraction];
    if (this.rendered) this.run('setSelection', bar, fraction);
  }

  setRange(sb, sf, eb, ef) {
    this.lastRange = [sb, sf, eb, ef];
    if (this.rendered) this.run('setRange', sb, sf, eb, ef);
  }

  /// `.gp` de todas las pistas de la última partitura cargada, en base64.
  async exportGpBase64() {
    const b64 = await this.run('exportGpBase64', {});
    if (typeof b64 !== 'string' || !b64) throw new Error('alphaTab no devolvió el fichero');
    return b64;
  }

  focus() { try { this.iframe.contentWindow?.focus(); } catch { /* sin foco */ } }

  destroy() {
    this.dead = true;
    this.iframe.remove();
  }
}
