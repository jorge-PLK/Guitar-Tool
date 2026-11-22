// Estado de Montaje: núcleo `montage.*` (contrato W2-M1). Lo que cambia poco (instantánea, exportación, encuadre) va en
// señales de Preact. La posición llega a ≤30 Hz y NO es señal: se guarda en `pos` y se avisa a los suscriptores, que
// pintan directamente (cabezal, deslizador, reloj) sin re-render, como Backing.
import { signal, computed } from '@preact/signals';
import { call, on, transportName } from '../bridge.js';
import { target } from '../backing/store.js';

export { target };

/// Mac (ProgressBarView.scrubInterval): con la vista previa en marcha cada seek reinicia la pasada, se limita al arrastrar.
export const SCRUB_INTERVAL_MS = 120;

export const status = signal('idle');         // idle | loading | ready | error
export const openError = signal(null);        // { code, message }
export const snap = signal(null);             // instantánea completa (montage.snapshot)
export const exportStatus = signal({ phase: 'idle', progress: 0 });
export const framingLive = signal({});        // takeId -> último montage.framing (progreso del análisis)
export const sheetTake = signal(null);        // toma cuya hoja «Encuadre» está abierta
export const cutMenu = signal(null);          // { id, x, y } menú del corte
export const actionError = signal(null);      // aviso de una acción fallida

export const lanes = computed(() => snap.value?.lanes ?? []);
export const isExporting = computed(() => exportStatus.value.phase === 'running');
export const previewReady = computed(() => snap.value?.preview?.phase === 'ready');

/// Posición del tema y reproducción, fuera de las señales.
export const pos = { seconds: 0, videoSeconds: 0, playing: false, at: 0 };
const posSubs = new Set();
export const onPosition = fn => { posSubs.add(fn); return () => posSubs.delete(fn); };
const firePos = () => posSubs.forEach(fn => { try { fn(pos); } catch (e) { console.error('position', e); } });
function setPos(seconds, playing, videoSeconds) {
  pos.seconds = seconds;
  if (videoSeconds != null) pos.videoSeconds = videoSeconds;
  pos.playing = playing;
  pos.at = performance.now();
  firePos();
}

/// Posición mientras se arrastra el deslizador o la línea de tiempo (null = no se arrastra).
let scrubbing = false;
export const setScrubbing = v => { scrubbing = v; };

function applySnapshot(s, { syncPos = true } = {}) {
  if (!s || typeof s !== 'object' || !('layout' in s)) return s;
  snap.value = s;
  exportStatus.value = s.exportStatus ?? { phase: 'idle', progress: 0 };
  framingLive.value = {};
  const t = s.transport;
  if (t && (syncPos && !scrubbing || pos.playing !== !!t.playing)) setPos(t.position ?? pos.seconds, !!t.playing, t.videoPosition);
  return s;
}

let token = 0;
let openId = null;
let offEvents = [];

function subscribe() {
  offEvents.forEach(f => f());
  offEvents = [
    on('montage.state', s => applySnapshot(s)),
    on('montage.position', p => setPos(p.seconds ?? 0, !!p.playing, p.videoSeconds)),
    on('montage.export', e => { exportStatus.value = { ...exportStatus.value, ...e }; }),
    on('montage.framing', f => { framingLive.value = { ...framingLive.value, [f.takeId]: f }; }),
  ];
}

export async function openMontage(id) {
  if (openId === id && status.value !== 'error') return;
  const mine = ++token;
  openId = id;
  status.value = 'loading';
  openError.value = null;
  snap.value = null;
  sheetTake.value = null;
  cutMenu.value = null;
  exportStatus.value = { phase: 'idle', progress: 0 };
  setPos(0, false, 0);
  subscribe();
  try {
    if (transportName() === 'mock') await import('../mock/montage.js');
    const s = await call('montage.open', { projectId: id });
    if (mine !== token) return;
    applySnapshot(s);
    status.value = 'ready';
  } catch (e) {
    if (mine !== token) return;
    openId = null;
    openError.value = { code: e.code ?? 'internal', message: e.message };
    status.value = 'error';
  }
}

export async function closeMontage() {
  token++;
  const had = openId != null;
  openId = null;
  offEvents.forEach(f => f());
  offEvents = [];
  status.value = 'idle';
  snap.value = null;
  sheetTake.value = null;
  cutMenu.value = null;
  setPos(0, false, 0);
  if (had) { try { await call('montage.close'); } catch (e) { console.error('montage.close', e.code, e.message); } }
}

/// Acción del núcleo: aplica la instantánea que devuelve. Los errores de audio quedan como aviso.
async function act(method, params = {}, { syncPos = true } = {}) {
  try {
    const r = await call(method, params);
    applySnapshot(r.snapshot ?? r, { syncPos });
    return r;
  } catch (e) {
    if (e.code === 'audio-unavailable') actionError.value = e.message;
    else if (e.code === 'not-open') { /* tema cerrado mientras tanto */ }
    else { actionError.value = e.message; console.error(method, e.code, e.message); }
    return null;
  }
}

// Ajustes
export const setLayout = layout => act('montage.setLayout', { layout });
export const setSingleRhythm = partId => act('montage.setSingleRhythm', { partId: partId ?? null });
export const setCutGaps = on_ => act('montage.setCutGaps', { on: on_ });
export const setCaption = on_ => act('montage.setCaption', { on: on_ });
export const setShowPartLabels = on_ => act('montage.setShowPartLabels', { on: on_ });
export const setKeepVideoAspect = on_ => act('montage.setKeepVideoAspect', { on: on_ });
export const moveLane = (id, to) => act('montage.moveLane', { id, to });
export const setExport = patch => act('montage.setExport', patch, { syncPos: false });

// Cortes del plano único
export async function addCut(time) {
  const r = await act('montage.addCut', { time });
  return r?.cutId ?? null;
}
export const moveCut = (id, time) => act('montage.moveCut', { id, time });
export const setCutPart = (id, partId) => act('montage.setCutPart', { id, partId: partId ?? null });
export const removeCut = id => act('montage.removeCut', { id });
export const clearCuts = () => act('montage.clearCuts');

// Exportación
export const startExport = () => act('montage.startExport', {}, { syncPos: false });
export const cancelExport = () => act('montage.cancelExport', {}, { syncPos: false });
export const dismissExport = () => act('montage.dismissExport', {}, { syncPos: false });
export async function reveal() {
  try { return await call('montage.reveal'); } catch (e) { actionError.value = e.message; return null; }
}

// Encuadre
export const setFraming = (takeId, patch) => act('montage.setFraming', { takeId, ...patch }, { syncPos: false });
export const resetFraming = takeId => act('montage.resetFraming', { takeId }, { syncPos: false });
export const reanalyze = takeId => act('montage.reanalyze', { takeId }, { syncPos: false });
export const rotateTake = takeId => act('montage.rotateTake', { takeId }, { syncPos: false });
export const framingFrame = (takeId, time) => call('montage.framingFrame', { takeId, time });

// Vista previa
export const play = () => act('montage.play');
export const pause = () => act('montage.pause');
export const togglePlay = () => (pos.playing ? pause() : play());
let lastSeek = 0, seekTimer = 0;
export function seek(seconds, { final = true } = {}) {
  setPos(seconds, pos.playing);
  clearTimeout(seekTimer);
  const send = () => { lastSeek = performance.now(); call('montage.seek', { seconds }).catch(() => {}); };
  const wait = SCRUB_INTERVAL_MS - (performance.now() - lastSeek);
  if (final || wait <= 0) send();
  else seekTimer = setTimeout(send, wait);
}

/// Estado del encuadre de una toma: instantánea + último evento de progreso.
export function framingOf(takeId) {
  const base = snap.value?.framing?.find(f => f.takeId === takeId) ?? { takeId, status: 'pending', progress: 0 };
  const live = framingLive.value[takeId];
  return live ? { ...base, ...live } : base;
}
