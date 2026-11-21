// Estado de Backing: núcleo de estudio (study.*, contrato «Backing: núcleo de estudio»).
// Lo que cambia poco (tema, transporte, mezcla) va en señales de Preact. Lo que llega a 30 Hz (posición y niveles) NO:
// se guarda en `pos` / `levels` y se avisa a los suscriptores, que pintan canvas y estilos directamente sin re-render.
import { signal, computed } from '@preact/signals';
import { call, on, transportName } from '../bridge.js';

/// Mac (ProgressBarView.scrubInterval): con el reproductor en marcha cada seek reinicia la pasada, se limita al arrastrar.
export const SCRUB_INTERVAL_MS = 120;
/// Mac (BackingController.faderRange): fader de -60 a +6 dB; imán a 0 dB (Fader.snapDB).
export const FADER_MIN_DB = -60;
export const FADER_MAX_DB = 6;
export const FADER_SNAP_DB = 1.5;
/// Mac (BackingController.meterFloorDB): suelo del vúmetro.
export const METER_FLOOR_DB = -60;
/// Rango de velocidad (contrato study.setRate) y paso del Mac (`(v/5).rounded()*0.05`).
export const RATE_MIN = 0.5;
export const RATE_MAX = 2.0;
export const RATE_STEP = 0.05;

export const target = signal(null);            // id del tema de Backing (último abierto)
export const status = signal('idle');          // idle | loading | ready | error
export const openError = signal(null);         // { code, message } si study.open falla
export const study = signal(null);             // resultado de study.open (sin transporte)
export const transport = signal(null);         // Transport (study.state)
export const audioError = signal(null);        // aviso visible de audio (study.error, play fallido o transport.audioError)
export const chordsExpanded = signal(false);

export const channels = computed(() => transport.value?.channels ?? []);

/// Posición y niveles en vivo, fuera de las señales.
export const pos = { seconds: 0, playing: false, at: 0 };
export const levels = { channels: {} };
const posSubs = new Set(), levelSubs = new Set();
export const onPosition = fn => { posSubs.add(fn); return () => posSubs.delete(fn); };
export const onLevels = fn => { levelSubs.add(fn); return () => levelSubs.delete(fn); };
const firePos = () => posSubs.forEach(fn => { try { fn(pos); } catch (e) { console.error('position', e); } });
const fireLevels = () => levelSubs.forEach(fn => { try { fn(levels); } catch (e) { console.error('levels', e); } });

function setPos(seconds, playing) {
  pos.seconds = seconds;
  pos.playing = playing;
  pos.at = performance.now();
  firePos();
}

function applyTransport(t, { syncPos = true } = {}) {
  if (!t) return;
  transport.value = t;
  if (t.audioError) audioError.value = t.audioError;
  if (syncPos || pos.playing !== !!t.playing) setPos(t.position ?? pos.seconds, !!t.playing);
}

let token = 0;
let openId = null;

export async function openStudy(id) {
  if (openId === id && status.value !== 'error') return;
  const mine = ++token;
  openId = id;
  status.value = 'loading';
  openError.value = null;
  audioError.value = null;
  study.value = null;
  transport.value = null;
  setPos(0, false);
  levels.channels = {};
  try {
    if (transportName() === 'mock') await import('./mock-study.js');
    const r = await call('study.open', { projectId: id });
    if (mine !== token) return;
    const { transport: t, ...rest } = r;
    study.value = rest;
    if (rest.loadError) audioError.value = null;
    applyTransport(t);
    status.value = 'ready';
  } catch (e) {
    if (mine !== token) return;
    openId = null;
    openError.value = { code: e.code ?? 'internal', message: e.message };
    status.value = 'error';
  }
}

export async function closeStudy() {
  token++;
  const had = openId != null;
  openId = null;
  status.value = 'idle';
  study.value = null;
  transport.value = null;
  setPos(0, false);
  if (had) { try { await call('study.close'); } catch (e) { console.error('study.close', e.code, e.message); } }
}

/// Llama a un método de transporte y aplica el Transport devuelto. Un error de audio queda como aviso, la pantalla sigue viva.
async function act(method, params = {}, { syncPos = true } = {}) {
  try {
    const t = await call(method, params);
    applyTransport(t, { syncPos });
    return t;
  } catch (e) {
    if (e.code === 'audio-unavailable') audioError.value = e.message;
    else if (e.code === 'not-open') { /* tema cerrado mientras tanto */ }
    else console.error(method, e.code, e.message);
    return null;
  }
}

export const play = () => act('study.play');
export const pause = () => act('study.pause');
export const togglePlay = () => (transport.value?.playing ? pause() : play());
export const setRate = rate => act('study.setRate', { rate: Math.min(RATE_MAX, Math.max(RATE_MIN, rate)) }, { syncPos: false });
export const setTranspose = (semitones, fineCents) =>
  act('study.setTranspose', fineCents === undefined ? { semitones } : { fineCents }, { syncPos: false });
export const setCapo = capo => act('study.setCapo', { capo }, { syncPos: false });
export const setLoop = (start, end, name) =>
  act('study.setLoop', start == null ? {} : (name ? { start, end, name } : { start, end }), { syncPos: false });
export const setMetronome = (onValue, gainDB) =>
  act('study.setMetronome', { ...(onValue != null ? { on: onValue } : {}), ...(gainDB != null ? { gainDB } : {}) }, { syncPos: false });
export const setMaster = gainDB => act('study.setMaster', { gainDB }, { syncPos: false });

/// Aplica un `EditState` (resultado de study.setChord/setKey/...; contrato 8.5b) al tema abierto: análisis (con las
/// correcciones), correcciones, secciones, bucles, guitarras y transporte. Solo toca los campos presentes.
export function applyEditState(es) {
  if (!es || !study.value) return;
  const { transport: t, added: _a, ...rest } = es;
  study.value = { ...study.value, ...rest };
  if (t) applyTransport(t, { syncPos: false });
}

/// Llama a un método de edición del estudio y aplica su `EditState`. Devuelve `true` si salió bien; si falla deja un aviso.
export const editAct = async (method, params = {}) => (await editResult(method, params)) != null;

// Acordes y tonalidad. Todo viaja guardado (sin transponer): quien llama convierte con `transposed(index, -transpose)`.
export const setChord = (start, end, index) => editAct('study.setChord', { start, end, index });
export const removeChordOverrides = (start, end) => editAct('study.removeChordOverrides', { start, end });
export const clearChordOverrides = () => editAct('study.clearChordOverrides');
export const splitChord = at => editAct('study.splitChord', { at });
export const setKey = key => editAct('study.setKey', { key });

// Mezcla: se actualiza al momento en local (fader fluido) y se envía sin esperar; el Transport devuelto lo confirma.
export function setMix(channel, patch, { optimistic = true } = {}) {
  const t = transport.value;
  if (t && optimistic) {
    const chs = t.channels.map(c => (c.id === channel ? { ...c, ...patch } : c));
    transport.value = { ...t, channels: chs, anySolo: chs.some(c => c.solo) };
  }
  return act('study.setMix', { channel, gainDB: patch.gainDB, mute: patch.muted, solo: patch.solo }, { syncPos: false });
}

/// Seek con la cadencia limitada del Mac. `final` fuerza el envío (soltar el ratón).
let lastSeek = 0;
export function seek(seconds, { final = true } = {}) {
  const now = performance.now();
  if (!final && now - lastSeek < SCRUB_INTERVAL_MS) return;
  lastSeek = now;
  const dur = transport.value?.duration ?? 0;
  const s = Math.min(Math.max(seconds, 0), dur);
  setPos(s, pos.playing);
  return act('study.seek', { seconds: s }, { syncPos: false });
}

// Eventos del núcleo.
on('study.position', p => {
  if (status.value !== 'ready') return;
  setPos(p.seconds ?? 0, !!p.playing);
});
on('study.state', t => { if (status.value === 'ready') applyTransport(t, { syncPos: false }); });
on('study.levels', p => { levels.channels = p.channels ?? {}; fireLevels(); });
on('study.error', p => { audioError.value = p.message || p.code || 'Error de audio'; });

// --- 8.6c-B: análisis, guitarras y secciones (contrato 8.5b) ---

/// Como `editAct`, pero devuelve el `EditState` (con `added`) ya aplicado, o null si falla (queda un aviso).
export async function editResult(method, params = {}) {
  try {
    const es = await call(method, params);
    applyEditState(es);
    return es;
  } catch (e) {
    if (e.code !== 'not-open') audioError.value = e.message || e.code;
    console.error(method, e.code, e.message);
    return null;
  }
}

/// Vuelve a pedir el estado del tema abierto SIN reabrirlo (no corta reproducción, posición ni bucle).
export async function refreshSnapshot() {
  const mine = token;
  try {
    const r = await call('study.snapshot');
    if (mine !== token || !study.value) return;
    const { transport: t, ...rest } = r;
    study.value = { ...study.value, ...rest };
    applyTransport(t, { syncPos: false });
  } catch (e) { if (e.code !== 'not-open') console.error('study.snapshot', e.code, e.message); }
}

/// «Analizar» / «Reintentar»: la cola lo hace; el avance llega por `study.analysis`.
export const analyze = () => editResult('study.analyze');

on('study.analysis', p => {
  if (status.value !== 'ready' || !study.value) return;
  const a = study.value.analysis ?? {};
  if (a.state === p.state && (a.error ?? null) === (p.error ?? null)) return;
  study.value = { ...study.value, analysis: { ...a, state: p.state, error: p.error ?? null } };
  if (p.state === 'ready') refreshSnapshot();   // relee pulso, acordes y tonalidad sin tocar la reproducción
});

/// `study.open` y `study.snapshot` ya traen `guitars` y `unappliedSections` (contrato 8.6d-C). Mientras las guitarras se
/// procesan se relee el snapshot (no corta reproducción ni toca lo editado: el snapshot lleva las secciones en edición).
export const syncEditState = () => refreshSnapshot();

export const setGuitarStereo = onValue => editResult('study.setGuitarStereo', { on: onValue });
export const renameGuitar = (role, name) => editResult('study.renameGuitar', { role, name });
export const markSection = (start, end, solo) => editResult('study.markSection', { start, end, solo: !!solo });
export const updateSection = (id, patch) => editResult('study.updateSection', { id, ...patch });
export const nudgeSectionEdge = (id, start, forward, bar) => editResult('study.nudgeSectionEdge', { id, start, forward, bar: !!bar });
export const deleteSection = id => editResult('study.deleteSection', { id });
export const applySections = () => editResult('study.applySections');
export const discardSections = () => editResult('study.discardSections');

on('study.state', t => {
  // El nombre del aparato de salida llega con el Transport (en Windows se conoce al abrir la salida, en el primer play).
  if (status.value === 'ready' && t?.outputName && study.value?.audio && study.value.audio.outputName !== t.outputName) {
    study.value = { ...study.value, audio: { ...study.value.audio, outputName: t.outputName } };
  }
  if (status.value === 'ready' && study.value?.guitars?.process === 'processing') syncEditState();
});
