// Estado de la pantalla Tablatura: métodos `tab.*` (Temp/win/step8-contract.md, «8.7 Tablatura»).
// El transporte (play, posición, velocidad, bucle) es el de Backing: `backing/store.js` (`study.*`). Aquí solo la partitura.
import { signal, computed } from '@preact/signals';
import { call, on, transportName } from '../bridge.js';
import { notify } from '../state.js';
import { openStudy, closeStudy, status as studyStatus, openError as studyError, onPosition, pos, transport } from '../backing/store.js';
import { AlphaFrame } from './frame.js';

/// Nombre del bucle del tramo seleccionado (App TabController.spanLoopName; contrato `tab.span`).
export const SPAN_LOOP_NAME = 'Selección';
/// Espera máxima de `tab.export`: incluye el diálogo «Guardar como» del anfitrión.
const EXPORT_TIMEOUT_MS = 10 * 60 * 1000;

/// Aviso breve del pie que no viene del núcleo (el fallo al exportar; el Mac lo muestra con `showFlash`).
export const localFlash = signal(null);
let localFlashTimer = 0;
const FLASH_MS = 3000;   // Mac: TabController.showFlash
export function flashLocal(text) {
  localFlash.value = text;
  clearTimeout(localFlashTimer);
  localFlashTimer = setTimeout(() => { localFlash.value = null; }, FLASH_MS);
}

export const tab = signal(null);           // TabState
export const opening = signal('idle');     // idle | loading | ready | error (apertura del tema y de la tablatura)
export const openProblem = signal(null);   // { code, message }
export const webError = signal(null);      // error de alphaTab (carga o JS)
export const rendered = signal(false);     // el lienzo ya pintó la partitura
export const dismissed = signal(new Set()); // avisos (`notices`) cerrados por el usuario
export const scoreInfo = signal(null);     // { trackIDs, bars } de la última partitura cargada

export const tracks = computed(() => tab.value?.tracks ?? []);
export const readyTracks = computed(() => tracks.value.filter(t => t.transcription === 'ready'));
export const selectedTrack = computed(() => tracks.value.find(t => t.id === tab.value?.selectedTrack) ?? null);

let frame = null;
let token = 0;
let openId = null;
let scoreSeq = 0;
let cache = null;                          // { key, json, trackIDs }
let loadedTrack = null;
const requested = new Set();               // pistas ya enviadas a `tab.transcribe` en esta apertura

// ---- Lienzo ----------------------------------------------------------------------------------

export function attachFrame(f) {
  frame = f;
  if (cache && f) { loadedTrack = null; pushToFrame(tab.value); }
}
export function detachFrame(f) { if (frame === f) { frame = null; rendered.value = false; } }

let keyHandler = null;
export const setKeyHandler = fn => { keyHandler = fn; };

export function createFrame(container) {
  const f = new AlphaFrame(container, { onEvent: onFrameEvent, onKey: e => keyHandler?.(e) });
  return f;
}

let dragBusy = false, dragNext = null;
function onFrameEvent(m) {
  switch (m.event) {
    case 'rendered': rendered.value = true; webError.value = null; break;
    case 'error': webError.value = m.message ?? 'error de alphaTab'; console.error('alphaTab', m.message); break;
    case 'beatClick':
      act('tab.beatClick', { track: m.track, bar: m.bar, beat: m.beat, shift: !!m.shift }, { quiet: true });
      break;
    case 'noteClick':
      if (m.shift) break;   // el ⇧clic sobre una nota ya lo trata beatClick
      act('tab.noteClick', { track: m.track, bar: m.bar, beat: m.beat, string: m.string, shift: false }, { quiet: true });
      break;
    case 'beatDrag': {
      const p = { track: m.track, bar: m.bar, beat: m.beat };
      if (dragBusy) { dragNext = p; break; }
      dragBusy = true;
      const send = q => act('tab.beatDrag', q, { quiet: true }).finally(() => {
        if (dragNext) { const n = dragNext; dragNext = null; send(n); } else dragBusy = false;
      });
      send(p);
      break;
    }
    default: break;
  }
}

// ---- Estado ----------------------------------------------------------------------------------

function apply(st) {
  if (!st || (openId && st.projectId && st.projectId !== openId)) return;
  tab.value = st;
  maybeTranscribe(st);
  syncScore(st);
}

/// A diferencia del Mac, abrir no transcribe: las pistas `queued` se lanzan aquí (una vez por pista y apertura).
function maybeTranscribe(st) {
  if (st.phase !== 'working' && st.phase !== 'ready') return;
  const todo = st.tracks.filter(t => t.transcription === 'queued' && !requested.has(t.id));
  if (!todo.length) return;
  todo.forEach(t => requested.add(t.id));
  call('tab.transcribe', {}).catch(e => {
    todo.forEach(t => requested.delete(t.id));
    notify('error', `No se pudo transcribir: ${e.message}`);
  });
}

function scoreKey(st, ready) { return `${st.revision}|${ready.map(t => t.id).join(',')}`; }

/// Lleva la partitura al lienzo cuando cambia (revisión o pistas listas) o cambia la pista visible.
async function syncScore(st) {
  if (st.phase !== 'working' && st.phase !== 'ready') return;
  const ready = st.tracks.filter(t => t.transcription === 'ready');
  if (!ready.length) return;
  const sel = ready.find(t => t.id === st.selectedTrack)?.id ?? null;
  if (!sel && st.selectedTrack !== ready[0].id) { act('tab.selectTrack', { track: ready[0].id }, { quiet: true }); return; }
  const key = scoreKey(st, ready);
  if (cache?.key === key) { pushToFrame(st); return; }
  const mine = ++scoreSeq;
  try {
    const r = await call('tab.score', sel ? { track: sel } : {});
    if (mine !== scoreSeq) return;
    const bars = (() => { try { return JSON.parse(r.json).bars ?? []; } catch { return []; } })();
    cache = { key, json: r.json, trackIDs: r.trackIDs ?? [] };
    scoreInfo.value = { trackIDs: cache.trackIDs, bars };
    loadedTrack = null;
    pushToFrame(tab.value ?? st);
  } catch (e) {
    if (mine !== scoreSeq) return;
    webError.value = e.message;
  }
}

function pushToFrame(st) {
  if (!frame || !cache || !st) return;
  const id = st.selectedTrack && cache.trackIDs.includes(st.selectedTrack) ? st.selectedTrack : cache.trackIDs[0];
  if (id === loadedTrack) return;
  loadedTrack = id;
  rendered.value = false;
  frame.load(cache.json, Math.max(0, cache.trackIDs.indexOf(id)));
}

// ---- Apertura y cierre -----------------------------------------------------------------------

export async function openTab(id) {
  const mine = ++token;
  openId = id;
  opening.value = 'loading';
  openProblem.value = null;
  webError.value = null;
  tab.value = null;
  cache = null; loadedTrack = null; scoreInfo.value = null;
  requested.clear();
  dismissed.value = new Set();
  try {
    if (transportName() === 'mock') await import('./mock-tab.js');
    await openStudy(id);   // study.open (Backing) si no es el abierto: transporte compartido
    if (mine !== token) return;
    if (studyStatus.value === 'error') throw Object.assign(new Error(studyError.value?.message ?? 'No se pudo abrir el tema'), { code: studyError.value?.code });
    const st = await call('tab.open', { projectId: id });
    if (mine !== token) return;
    opening.value = 'ready';
    apply(st);
  } catch (e) {
    if (mine !== token) return;
    openProblem.value = { code: e.code ?? 'internal', message: e.message };
    opening.value = 'error';
  }
}

/// Al salir de la pantalla: guarda lo editado (`tab.close`) y, si no se va a Backing, suelta el estudio.
export async function closeTab({ keepStudy = false } = {}) {
  token++;
  const had = openId != null;
  openId = null;
  opening.value = 'idle';
  tab.value = null;
  cache = null; loadedTrack = null; scoreInfo.value = null;
  if (had) { try { await call('tab.close'); } catch (e) { console.error('tab.close', e.code, e.message); } }
  if (!keepStudy) await closeStudy();
}

/// Repite `tab.open` (p. ej. tras analizar el tema, o al reintentar).
export async function reopenTab() {
  if (!openId) return;
  try { apply(await call('tab.open', { projectId: openId })); }
  catch (e) { notify('error', e.message); }
}

// ---- Acciones --------------------------------------------------------------------------------

/// Llama a un método que devuelve TabState y lo aplica. `quiet`: no avisa de los errores (clics del lienzo).
export async function act(method, params = {}, { quiet = false } = {}) {
  try {
    const st = await call(method, params);
    apply(st);
    return st;
  } catch (e) {
    if (e.code === 'not-open') return null;
    if (quiet) console.error(method, e.code, e.message); else notify('error', e.message);
    return null;
  }
}

export const selectTrack = id => act('tab.selectTrack', { track: id });
export const toggleMute = id => act('tab.toggleMute', { track: id });
export const toggleSolo = id => act('tab.toggleSolo', { track: id });
export const setListening = (id, on) => act('tab.setListening', { track: id, on });
export const setAllListening = on => act('tab.setAllListening', { on });
export const setSource = source => act('tab.setSource', { source });
export const edit = (op, params = {}, opts) => act('tab.edit', { op, ...params }, opts);
export const setEditMode = on => edit('editMode', { on });
export const setTuning = (track, preset) => edit('tuning', { track, preset });
export const spanAction = action => act('tab.span', { action });

export async function transcribe(track) {
  if (track) requested.add(track);
  try { await call('tab.transcribe', track ? { track } : {}); }
  catch (e) { if (track) requested.delete(track); notify('error', e.message); }
}

export async function cancelTranscription() {
  try { await call('tab.cancel'); } catch (e) { notify('error', e.message); }
  // Lo que no se transcribió queda `queued`: no se relanza solo hasta reabrir.
  tab.value?.tracks.forEach(t => { if (t.transcription === 'queued' || t.transcription === 'transcribing') requested.add(t.id); });
}

/// «Exportar a Guitar Pro»: bytes de alphaTab -> `tab.export` (el núcleo abre «Guardar como» por el anfitrión).
export async function exportGp() {
  if (!frame) return;
  try {
    const data = await frame.exportGpBase64();
    await call('tab.export', { data }, { timeout: EXPORT_TIMEOUT_MS });   // el «Guardado X.gp.» llega como `flash` del núcleo
  } catch (e) { flashLocal(`No se pudo exportar: ${e.message}`); }
}

// ---- Eventos del núcleo ----------------------------------------------------------------------

on('tab.state', st => { if (openId) apply(st); });
on('tab.progress', p => {
  const st = tab.value;
  if (!st || !openId) return;
  const map = { transcribing: 'transcribing', done: 'ready', failed: 'failed', cancelled: 'queued' };
  tab.value = { ...st, tracks: st.tracks.map(t => (t.id !== p.track ? t : {
    ...t, transcription: map[p.state] ?? t.transcription,
    progress: p.state === 'transcribing' ? (p.fraction ?? null) : null,
    error: p.state === 'failed' ? (p.error ?? 'error desconocido') : null,
  })) };
});
on('tab.selection', p => frame?.setSelection(p.bar, p.fraction ?? 0));
on('tab.range', p => frame?.setRange(p.startBar, p.startFraction ?? 0, p.endBar, p.endFraction ?? 0));

/// El cursor de reproducción del lienzo sigue a `study.position` (no hay `tab.cursor`); solo con el lienzo montado.
let offPos = null;
export function followPosition(on_) {
  offPos?.(); offPos = null;
  if (!on_) return;
  frame?.setCursorTime(pos.seconds, true);
  offPos = onPosition(p => frame?.setCursorTime(p.seconds, true));
}

/// Un bucle activo que no es el del tramo quita el resaltado del tramo (TabController.loopChanged).
let lastLoopName;
export function watchLoop() {
  const loop = transport.value?.loop ?? null;
  const name = loop?.name ?? null;
  if (name !== lastLoopName) {
    lastLoopName = name;
    if (tab.value?.span && name !== SPAN_LOOP_NAME) spanAction('clear');
  }
}
