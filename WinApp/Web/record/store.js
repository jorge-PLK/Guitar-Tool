// Estado de Grabar: núcleo `record.*` (contrato «W2-R1 record.*»). La instantánea (`Snapshot`) va en una señal;
// posición y niveles (≤30 Hz) NO: se guardan en `pos` / `levels` y se avisa a los suscriptores, que pintan sin re-render.
import { signal, computed } from '@preact/signals';
import { call, on, transportName } from '../bridge.js';
import { notify } from '../state.js';
import { openStudy, closeStudy, study, status as studyStatus } from '../backing/store.js';

export const status = signal('idle');        // idle | loading | ready | error
export const openError = signal(null);       // { code, message }
export const snap = signal(null);            // Snapshot
export const audioInfo = signal({ calibrationValid: true, guitarIn: [] });   // audio.state / audio.settings
/// «Ver toma» pedido desde otra pantalla (Biblioteca): la pantalla Grabar lo abre al estar lista.
export const viewRequest = signal(null);     // { takeId } | null

export const pos = { seconds: 0, playing: false, phase: 'idle' };
export const levels = { channels: {}, input: 0 };
const posSubs = new Set(), levelSubs = new Set();
export const onPosition = fn => { posSubs.add(fn); return () => posSubs.delete(fn); };
export const onLevels = fn => { levelSubs.add(fn); return () => levelSubs.delete(fn); };
const firePos = () => posSubs.forEach(fn => { try { fn(pos); } catch (e) { console.error('record position', e); } });
const fireLevels = () => levelSubs.forEach(fn => { try { fn(levels); } catch (e) { console.error('record levels', e); } });

export const phase = computed(() => snap.value?.phase ?? 'idle');
/// Mac (`ctl.isBusy`): no se toca nada mientras se cuenta, se graba, se guarda o se ajusta.
export const locked = computed(() => !!snap.value && (snap.value.busy || snap.value.phase !== 'idle'));

let token = 0;
let openId = null;

function apply(s) {
  if (!s || typeof s !== 'object' || !s.phase) return;
  snap.value = s;
  if (typeof s.position === 'number' && !pos.playing) { pos.seconds = s.position; firePos(); }
}

export async function openRecord(id) {
  if (openId === id && status.value !== 'error') return;
  const mine = ++token;
  openId = id;
  status.value = 'loading';
  openError.value = null;
  snap.value = null;
  Object.assign(pos, { seconds: 0, playing: false, phase: 'idle' });
  levels.channels = {}; levels.input = 0;
  try {
    if (transportName() === 'mock') await import('../mock/record.js');
    await openStudy(id);                          // «Grabar trabaja sobre el tema abierto en Backing»
    if (mine !== token) return;
    if (studyStatus.value !== 'ready') throw Object.assign(new Error('No se pudo abrir el tema'), { code: 'not-open' });
    const s = await call('record.open', { projectId: id });
    if (mine !== token) return;
    apply(s);
    status.value = 'ready';
    loadAudio();
  } catch (e) {
    if (mine !== token) return;
    openId = null;
    openError.value = { code: e.code ?? 'internal', message: e.message };
    status.value = 'error';
  }
}

/// Sale de Grabar. Con `keepStudy` (rumbo a Montaje) solo devuelve el reproductor a Backing; si no, cierra también el tema (Mac: `closeStudy`).
export async function closeRecord({ keepStudy = false } = {}) {
  token++;
  const had = openId != null;
  openId = null;
  status.value = 'idle';
  snap.value = null;
  if (had) {
    try { await call('audio.setMeters', { visible: false }); } catch { /* sin audio.* */ }
    try { await call('record.close'); } catch (e) { console.error('record.close', e.code, e.message); }
    if (!keepStudy) await closeStudy();
  }
}

/// Entrada de guitarra y calibración (Mac: `model.audio.settings?.guitarIn`, `calibrationValid`).
async function loadAudio() {
  try {
    const [s, a] = await Promise.all([call('audio.settings'), call('audio.setMeters', { visible: true })]);
    audioInfo.value = { calibrationValid: a.calibrationValid !== false, guitarIn: s.guitarIn ?? [] };
  } catch { /* sin audio.*: la pantalla sigue valiendo */ }
}
on('audio.state', a => { if (status.value === 'ready') audioInfo.value = { ...audioInfo.value, calibrationValid: a.calibrationValid !== false }; });
on('audio.levels', p => {
  if (status.value !== 'ready') return;
  const lv = p.levels ?? [];
  levels.input = (audioInfo.value.guitarIn ?? []).reduce((m, c) => (c >= 1 && c - 1 < lv.length ? Math.max(m, lv[c - 1]) : m), 0);
  fireLevels();
});

/// Llama a un método `record.*` y aplica la instantánea. Un error queda como aviso (no rompe la pantalla).
export async function act(method, params = {}) {
  try {
    const s = await call(method, params);
    apply(s);
    return s;
  } catch (e) {
    if (e.code !== 'not-open') notify('error', e.message || e.code);
    console.error(method, e.code, e.message);
    return null;
  }
}

on('record.state', s => { if (status.value === 'ready') apply(s); });
on('record.position', p => {
  if (status.value !== 'ready') return;
  pos.seconds = p.seconds ?? 0; pos.playing = !!p.playing; pos.phase = p.phase ?? pos.phase;
  firePos();
});
on('record.levels', p => { if (status.value !== 'ready') return; levels.channels = p.channels ?? {}; fireLevels(); });

export const startTake = () => act('record.start');
export const stopTake = () => act('record.stop');
export const cancelTake = () => act('record.cancel');
export const selectPart = partId => act('record.selectPart', { partId });
export const addPart = (name, replaces) => act('record.addPart', replaces ? { name, replaces } : { name });
export const setStartSection = sectionId => act('record.setStartSection', { sectionId: sectionId ?? null });
export const setCountIn = on_ => act('record.setCountIn', { on: on_ });
export const setPreRoll = bars => act('record.setPreRoll', { bars });
export const setPunch = p => act('record.setPunch', p);
export const startPunch = takeId => act('record.startPunch', { takeId });
export const selectTake = takeId => act('record.selectTake', { takeId: takeId ?? null });
export const markBest = takeId => act('record.markBest', { takeId });
export const deleteTake = takeId => act('record.deleteTake', { takeId });
export const setCamera = cameraId => act('record.setCamera', { cameraId: cameraId ?? null });
export const rotateCamera = () => act('record.rotate');
export const adjustOffset = takeId => act('record.adjustOffset', { takeId });
export const setOffset = p => act('record.setOffset', p);
export const finishOffset = (save, makeDefault = true) => act('record.finishOffset', { save, makeDefault });
export const setMaster = gainDB => act('record.setMaster', { gainDB });
/// Mezcla: ajuste local inmediato (fader fluido) y envío sin esperar; la instantánea lo confirma.
export function setMix(channel, patch, { optimistic = true } = {}) {
  const s = snap.value;
  if (s && optimistic) {
    const map = c => (c.id === channel ? { ...c, ...patch } : c);
    const channels = s.mix.channels.map(map), takeChannels = s.mix.takeChannels.map(map);
    snap.value = { ...s, mix: { ...s.mix, channels, takeChannels, anySolo: [...channels, ...takeChannels].some(c => c.solo) } };
  }
  return act('record.setMix', { channel, gainDB: patch.gainDB, mute: patch.muted, solo: patch.solo });
}
/// Para el transporte de Grabar antes de «Ver toma» (false si se está grabando).
export async function prepareViewTake() {
  try { return (await call('record.prepareViewTake')).allowed !== false; }
  catch (e) { notify('error', e.message || e.code); return false; }
}

/// Número de toma como en el Mac: posición (desde 1) entre las no descartadas de su parte.
export const takesOf = part => (part.takes ?? []).filter(t => !t.discarded);
export const guitarName = (s, role) => s.guitarRoles?.find(g => g.role === role)?.name ?? role;
export { study };
