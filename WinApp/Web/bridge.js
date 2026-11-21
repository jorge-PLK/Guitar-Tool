// Puente página <-> núcleo. Protocolo JSON (Temp/win/step8-contract.md):
//   petición {"id":int,"method":"ns.nombre","params":{}}
//   respuesta {"id":int,"result":{}} | {"id":int,"error":{"code","message"}}
//   evento    {"event":"ns.nombre","payload":{}}
// Transportes: WebView2 (chrome.webview), WKWebView del Mac de desarrollo (webkit.messageHandlers.tf) y simulado.

export const CALL_TIMEOUT_MS = 15000;

export class BridgeError extends Error {
  constructor(code, message) {
    super(message || code);
    this.name = 'BridgeError';
    this.code = code;
  }
}

const listeners = new Map();
const pending = new Map();
let nextId = 1;
let transport = null;

function emit(event, payload) {
  for (const fn of listeners.get(event) ?? []) {
    try { fn(payload); } catch (e) { console.error('bridge listener', event, e); }
  }
}

function receive(raw) {
  let msg;
  try { msg = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch { console.error('bridge: JSON no válido', raw); return; }
  if (msg == null || typeof msg !== 'object') return;
  if (typeof msg.event === 'string') { emit(msg.event, msg.payload ?? {}); return; }
  if (typeof msg.id !== 'number') return;
  const p = pending.get(msg.id);
  if (!p) return;
  pending.delete(msg.id);
  clearTimeout(p.timer);
  if (msg.error) p.reject(new BridgeError(msg.error.code ?? 'internal', msg.error.message));
  else p.resolve(msg.result ?? {});
}

function pickTransport() {
  const params = new URLSearchParams(location.search);
  if (params.get('mock') === '1') return mockTransport();
  if (window.chrome?.webview) {
    window.chrome.webview.addEventListener('message', e => receive(e.data));
    return { name: 'webview2', send: s => window.chrome.webview.postMessage(s) };
  }
  if (window.webkit?.messageHandlers?.tf) {
    window.__tfReceive = receive;
    return { name: 'webkit', send: s => window.webkit.messageHandlers.tf.postMessage(s) };
  }
  return mockTransport();
}

// Simulados con estado (p. ej. Backing: backing/mock-study.js): `fn(method, params)` devuelve el resultado, una promesa
// o lanza BridgeError; `undefined` = sin manejar (cae a los fixtures). `mockEmit` entrega un evento a la página.
const mockHandlers = [];
export function setMockHandler(fn) { mockHandlers.push(fn); }
export function mockEmit(event, payload) { receive({ event, payload }); }

// Simulado: el simulador de mock/sim.js (biblioteca en memoria con fixtures y cola de trabajos).
function mockTransport() {
  let sim = null;
  return {
    name: 'mock',
    send(s) {
      const req = JSON.parse(s);
      for (const fn of mockHandlers) {   // simuladores con estado de otras pantallas (Backing)
        let out;
        try { out = fn(req.method, req.params ?? {}); } catch (e) {
          setTimeout(() => receive({ id: req.id, error: { code: e.code ?? 'internal', message: e.message } }), 10);
          return;
        }
        if (out !== undefined) {
          Promise.resolve(out).then(
            r => setTimeout(() => receive({ id: req.id, result: r }), 10),
            e => setTimeout(() => receive({ id: req.id, error: { code: e.code ?? 'internal', message: e.message } }), 10));
          return;
        }
      }
      sim ??= import('./mock/sim.js').then(m => new m.MockSim((event, payload) => setTimeout(() => receive({ event, payload }), 0), new URLSearchParams(location.search)));
      sim.then(x => x.handle(req.method, req.params))
        .then(result => setTimeout(() => receive({ id: req.id, result }), 20))
        .catch(e => setTimeout(() => receive({ id: req.id, error: { code: e.code ?? 'internal', message: e.message } }), 20));
    },
  };
}

export function transportName() {
  transport ??= pickTransport();
  return transport.name;
}

export function call(method, params = {}, { timeout = CALL_TIMEOUT_MS } = {}) {
  transport ??= pickTransport();
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new BridgeError('timeout', `${method}: sin respuesta en ${timeout} ms`));
    }, timeout);
    pending.set(id, { resolve, reject, timer });
    try { transport.send(JSON.stringify({ id, method, params })); }
    catch (e) { pending.delete(id); clearTimeout(timer); reject(new BridgeError('internal', String(e))); }
  });
}

/// Suscribe `fn` al evento; devuelve la función para darse de baja.
export function on(event, fn) {
  if (!listeners.has(event)) listeners.set(event, new Set());
  listeners.get(event).add(fn);
  return () => listeners.get(event)?.delete(fn);
}

// Opción de desarrollo --eval-file del anfitrión Windows: el evento `dev.eval` trae código JS que se ejecuta como cuerpo
// de una función async con (bridge, log); `log` y el resultado vuelven al log del anfitrión como petición `dev.log`.
// El anfitrión solo manda `dev.eval` si se arrancó con --eval-file.
const DEV_LOG_MAX = 2000;
const devBridge = { call, on, transportName, BridgeError, CALL_TIMEOUT_MS };
function devLog(text) {
  const s = String(text);
  call("dev.log", { text: s.length > DEV_LOG_MAX ? s.slice(0, DEV_LOG_MAX) + "…" : s }).catch(() => {});
}
on("dev.eval", async payload => {
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  try {
    const value = await new AsyncFunction("bridge", "log", String(payload?.code ?? ""))(devBridge, devLog);
    let out; try { out = JSON.stringify(value); } catch (e) { out = String(value); }
    devLog(`eval: fin -> ${out}`);
  } catch (e) {
    devLog(`eval: excepción -> ${e?.message ?? e}`);
  }
});
// Registra el transporte ya, para no perder un evento que llegue antes de la primera llamada.
transportName();
