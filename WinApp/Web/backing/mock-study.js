// Simulador de `study.*` para `?mock=1` (sin núcleo): estado de transporte, reloj de posición a 30 Hz y niveles sintéticos.
// Variantes con `?study=`: missing | analyzing | failed (análisis), unseparated (sin stems), audioerr (play falla), loaderr.
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';
import { mockEditsB } from './mock-edits.js';

const EVENT_HZ = 30;
const params = new URLSearchParams(location.search);
const variant = params.get('study');
let fixture = null;
let tr = null;                 // Transport simulado
let timer = 0, lastTick = 0;
let open = false;
let cur = null, baseChords = [], overrides = [];     // tema abierto, acordes detectados y correcciones (ediciones 8.5b)

const clone = o => JSON.parse(JSON.stringify(o));
const emitState = () => mockEmit('study.state', clone(tr));

function stopClock() { clearInterval(timer); timer = 0; }

function tick() {
  const now = performance.now();
  const dt = (now - lastTick) / 1000;
  lastTick = now;
  tr.position += dt * tr.rate;
  const L = tr.loop;
  if (L && tr.position >= L.end) tr.position = L.start + (tr.position - L.end);
  if (tr.position >= tr.duration) {
    tr.position = tr.duration; tr.playing = false;
    stopClock();
    mockEmit('study.position', { seconds: tr.position, playing: false });
    emitState();
    return;
  }
  mockEmit('study.position', { seconds: tr.position, playing: true });
  const ch = {};
  const t = now / 1000;
  tr.channels.forEach((c, i) => {
    const silent = c.muted || (tr.anySolo && !c.solo);
    const base = -24 + 9 * Math.sin(t * (1.3 + i * 0.37) + i) + 4 * Math.sin(t * 7.1 + i * 2) + c.gainDB;
    ch[c.id] = silent ? { rmsDB: -120, peakDB: -120 } : { rmsDB: Math.max(-90, Math.min(0, base)), peakDB: Math.min(0, base + 6) };
  });
  mockEmit('study.levels', { channels: ch });
}

function startClock() {
  if (timer) return;
  lastTick = performance.now();
  timer = setInterval(tick, 1000 / EVENT_HZ);
}

async function loadFixture() {
  if (!fixture) fixture = await (await fetch(new URL('mock/study.open.json', document.baseURI))).json();
  return clone(fixture);
}

function need() { if (!open) throw new BridgeError('not-open', 'No hay ningún tema abierto'); }

/// Acordes efectivos: los detectados con las correcciones encima (gana la última), como `ChordTimeline` del núcleo.
function applyOverrides() {
  let list = baseChords.map(c => ({ ...c, overridden: false }));
  for (const o of overrides) {
    const out = [];
    for (const c of list) {
      if (c.end <= o.start || c.start >= o.end) { out.push(c); continue; }
      if (c.start < o.start) out.push({ ...c, end: o.start });
      if (c.end > o.end) out.push({ ...c, start: o.end });
    }
    out.push({ start: o.start, end: o.end, index: o.index, overridden: true });
    list = out.sort((a, b) => a.start - b.start);
  }
  const name = i => (i === 169 ? 'N' : i === 168 ? 'X' : 'idx' + i);
  return list.map(c => ({ ...c, name: c.name && !c.overridden ? c.name : name(c.index) }));
}

function editMock(method, p) {
  const bad = m => { throw new BridgeError('bad-params', m); };
  const a = cur.analysis;
  switch (method) {
    case 'study.setChord':
      if (!(p.end > p.start) || p.start < 0 || !(p.index >= 0 && p.index <= 169)) bad('parámetros de acorde no válidos');
      overrides.push({ start: p.start, end: p.end, index: p.index }); break;
    case 'study.removeChordOverrides':
      overrides = overrides.filter(o => !(o.start < p.end && o.end > p.start)); break;
    case 'study.clearChordOverrides': overrides = []; break;
    case 'study.splitChord': {
      const c = applyOverrides().find(x => x.start <= p.at && p.at < x.end);
      const b = (a.beats ?? []).reduce((best, t) => (Math.abs(t - p.at) < Math.abs(best - p.at) ? t : best), Infinity);
      if (!c || !(b > c.start + 0.05 && b < c.end - 0.05)) throw new BridgeError('cannot-split', 'No se puede partir aquí');
      overrides.push({ start: c.start, end: b, index: c.index }, { start: b, end: c.end, index: c.index }); break;
    }
    default: {   // study.setKey
      if (a.state !== 'ready') throw new BridgeError('no-analysis', 'Sin análisis');
      if (p.key != null && !/^[A-G][#b]?:(maj|min)$/.test(p.key)) bad('tonalidad no válida');
      a.key = { ...a.key, override: p.key ?? null, effective: p.key ?? a.key.detected ?? null };
    }
  }
  a.chords = applyOverrides();
  cur.chordOverrides = clone(overrides);
  emitState();
  return { analysis: clone(a), chordOverrides: clone(overrides), sections: clone(cur.sections ?? []), unappliedSections: false,
    loops: clone(cur.loops ?? []), transport: clone(tr) };
}

async function handleStudy(method, p) {
  switch (method) {
    case 'study.open': {
      stopClock();
      const r = await loadFixture();
      r.projectId = p.projectId;
      if (variant === 'missing' || variant === 'analyzing' || variant === 'failed') {
        r.analysis = { state: variant, error: variant === 'failed' ? 'El análisis de acordes terminó con un error' : null, beats: [], downbeats: [], chords: [], key: {} };
        r.sections = [];
      }
      if (variant === 'unseparated') { r.transport.channels = []; r.emptyStems = []; r.analysis = { state: 'missing', beats: [], downbeats: [], chords: [], key: {} }; r.sections = []; r.loops = []; }
      if (variant === 'loaderr') r.loadError = 'No se pudieron cargar los stems (fichero dañado)';
      tr = r.transport;
      cur = r; baseChords = clone(r.analysis?.chords ?? []); overrides = clone(r.chordOverrides ?? []);
      open = true;
      const es = await mockEditsB('study.snapshot', {}, { cur, tr, emitState, clone });   // 8.6d-C: guitars y unappliedSections ya en open
      r.guitars = es.guitars; r.unappliedSections = es.unappliedSections;
      return r;
    }
    case 'study.close': stopClock(); open = false; return {};
    default: break;
  }
  need();
  switch (method) {
    case 'study.play':
      if (variant === 'audioerr') {
        tr.audioError = 'No se pudo abrir la salida de audio. Comprueba el dispositivo en Ajustes.';
        emitState();
        throw new BridgeError('audio-unavailable', tr.audioError);
      }
      if (tr.position >= tr.duration) tr.position = 0;
      tr.playing = true; startClock(); emitState(); return clone(tr);
    case 'study.pause':
      tr.playing = false; stopClock();
      mockEmit('study.position', { seconds: tr.position, playing: false });
      emitState(); return clone(tr);
    case 'study.seek':
      tr.position = Math.min(Math.max(p.seconds ?? 0, 0), tr.duration);
      mockEmit('study.position', { seconds: tr.position, playing: tr.playing });
      return clone(tr);
    case 'study.setRate': tr.rate = Math.min(2, Math.max(0.5, p.rate)); break;
    case 'study.setTranspose':
      if (p.semitones != null) tr.transpose = Math.max(-12, Math.min(12, p.semitones));
      if (p.fineCents != null) tr.fineCents = Math.max(-50, Math.min(50, p.fineCents));
      break;
    case 'study.setCapo': tr.capo = Math.max(0, Math.min(12, p.capo)); break;
    case 'study.setLoop':
      tr.loop = p.start != null && p.end != null && p.end - p.start >= 0.05 ? { start: p.start, end: p.end, name: p.name ?? null } : null;
      break;
    case 'study.setMix': {
      const c = tr.channels.find(x => x.id === p.channel);
      if (!c) throw new BridgeError('bad-params', 'canal desconocido: ' + p.channel);
      if (p.gainDB != null) c.gainDB = Math.max(-60, Math.min(6, p.gainDB));
      if (p.mute != null) c.muted = p.mute;
      if (p.solo != null) c.solo = p.solo;
      tr.anySolo = tr.channels.some(x => x.solo);
      break;
    }
    case 'study.setMaster': tr.masterGainDB = Math.max(-60, Math.min(6, p.gainDB)); break;
    case 'study.setMetronome':
      if (p.on != null) tr.metronome.on = p.on;
      if (p.gainDB != null) tr.metronome.gainDB = p.gainDB;
      break;
    case 'study.setChord': case 'study.removeChordOverrides': case 'study.clearChordOverrides': case 'study.splitChord': case 'study.setKey':
      return editMock(method, p);
    default: {
      const r = await mockEditsB(method, p, { cur, tr, emitState, clone });   // 8.6c-B: análisis, guitarras, secciones
      if (r === undefined) throw new BridgeError('unknown-method', method);
      return r;
    }
  }
  emitState();
  return clone(tr);
}

setMockHandler((method, p) => (method.startsWith('study.') ? handleStudy(method, p) : undefined));
