// Simulador de `tab.*` para `?mock=1` (sin núcleo): partitura pequeña, selección por clic, edición básica y progreso.
// Variantes con `?tab=`: progress (bajo transcribiendo, batería en cola) | working (nada listo) | choose | waiting | empty | failed.
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';
import '../mock/songsterr.js';

const variant = new URLSearchParams(location.search).get('tab');
const clone = o => JSON.parse(JSON.stringify(o));

const GUITAR_RIFF = [[2, 2], [3, 2], [4, 0], [3, 2], [2, 2], [3, 2], [4, 3], [4, 5]];   // [cuerda (0 = grave), traste]
const bars = Array.from({ length: 8 }, (_, i) => ({ num: 4, den: 4, tempo: 120, start: i * 2 }));
const guitarBars = bars.map((_, b) => GUITAR_RIFF.map(([s, f], i) => ({ d: 8, notes: [{ s: s + (b % 2), f: i === 7 ? f + b % 3 : f }] })));
const bassBars = bars.map((_, b) => [0, 0, 2, 0].map((f, i) => ({ d: 4, notes: [{ s: b % 4 === 3 && i === 3 ? 1 : 0, f: f + (b % 2 ? 3 : 0) }] })));
const drumBars = bars.map(() => [[35, 42], [42], [38, 42], [42], [35, 42], [35, 42], [38, 42], [42]].map(h => ({ d: 8, hits: h })));
const SCORE = {
  version: 1, title: 'Maqueta', artist: 'ToneForge', bars,
  tracks: [
    { name: 'Guitarra', kind: 'guitar', tuning: [40, 45, 50, 55, 59, 64], bars: guitarBars },
    { name: 'Bajo', kind: 'bass', tuning: [28, 33, 38, 43], bars: bassBars },
    { name: 'Batería', kind: 'drums', bars: drumBars },
  ],
};

const STD = { preset: 'standard', name: 'Estándar', strings: [64, 59, 55, 50, 45, 40] };
const mkTrack = (id, name, kind, extra = {}) => ({
  id, name, kind, tuning: kind === 'drums' ? null : kind === 'bass' ? { ...STD, strings: [43, 38, 33, 28] } : STD, customTuning: null,
  origin: 'stem', playerTrack: id, transcription: 'ready', progress: null, error: null, fingerprint: null, noteCount: 64,
  muted: false, solo: false, dimmed: false, listening: false, synth: null, ...extra,
});

let st = null;
let revision = 1;
let timer = 0;

function fresh(id) {
  const tracks = [mkTrack('guitar', 'Guitarra', 'guitar'), mkTrack('bass', 'Bajo', 'bass'), mkTrack('drums', 'Batería', 'drums')];
  if (variant === 'progress') {
    Object.assign(tracks[1], { transcription: 'transcribing', progress: 0.42, noteCount: 0 });
    Object.assign(tracks[2], { transcription: 'queued', noteCount: 0 });
  } else if (variant === 'working') {
    tracks.forEach((t, i) => Object.assign(t, { transcription: i === 0 ? 'transcribing' : 'queued', progress: i === 0 ? 0.18 : null, noteCount: 0 }));
  } else if (variant === 'failed') {
    Object.assign(tracks[2], { transcription: 'failed', error: 'No se encontró el modelo de batería.', noteCount: 0 });
  }
  const phase = { choose: 'choosingSource', waiting: 'waitingAnalysis', empty: 'empty' }[variant]
    ?? (variant === 'working' ? 'working' : 'ready');
  st = {
    projectId: id, phase, error: null, header: '4/4 · 120 BPM', source: variant === 'choose' ? null : 'automatic',
    tracks: phase === 'empty' || phase === 'waitingAnalysis' ? [] : tracks, selectedTrack: 'guitar', notices: variant === 'progress' ? ['Aviso de ejemplo: la batería se transcribe al final.'] : [],
    canUndo: false, canRedo: false, editMode: false, graceMode: false, listenMode: 'stems', anySolo: false,
    selection: null, span: null, revision, flash: null,
  };
}

/// Para `mock/songsterr.js`: cambia el TabState simulado (aceptar el emparejamiento o pasar a automática) y lo devuelve.
export function mockTabPatch(fn) { if (!st) throw new BridgeError('not-open', 'No hay ninguna tablatura abierta.'); fn(st); revision++; st.revision = revision; return clone(st); }
export const mockTabOpen = () => st != null;

function emitState() { mockEmit('tab.state', clone(st)); }
const readyTracks = () => st.tracks.filter(t => t.transcription === 'ready');
const track = id => st.tracks.find(t => t.id === id);

function runTranscription() {
  clearInterval(timer);
  timer = setInterval(() => {
    const cur = st.tracks.find(t => t.transcription === 'transcribing') ?? st.tracks.find(t => t.transcription === 'queued');
    if (!cur) { clearInterval(timer); st.phase = 'ready'; emitState(); return; }
    cur.transcription = 'transcribing';
    cur.progress = Math.min(1, (cur.progress ?? 0) + 0.12);
    if (cur.progress >= 1) {
      Object.assign(cur, { transcription: 'ready', progress: null, noteCount: 64 });
      revision++; st.revision = revision;
      mockEmit('tab.progress', { track: cur.id, state: 'done', fraction: 1, error: null });
      emitState();
    } else mockEmit('tab.progress', { track: cur.id, state: 'transcribing', fraction: cur.progress, error: null });
  }, 600);
}

function handle(method, p) {
  if (method === 'tab.open') {
    if (!st || st.projectId !== p.projectId) fresh(p.projectId);
    return clone(st);
  }
  if (!st) throw new BridgeError('not-open', 'No hay ninguna tablatura abierta.');
  switch (method) {
    case 'tab.state': return clone(st);
    case 'tab.close': st = null; clearInterval(timer); return {};
    case 'tab.setSource': st.source = p.source; st.phase = 'working'; return clone(st);
    case 'tab.score': {
      const ids = ['guitar', 'bass', 'drums'];
      return { json: JSON.stringify(SCORE), trackIndex: Math.max(0, ids.indexOf(p.track ?? 'guitar')), trackIDs: ids, revision };
    }
    case 'tab.selectTrack': st.selectedTrack = p.track; st.selection = null; mockEmit('tab.selection', { bar: -1, fraction: 0 }); return clone(st);
    case 'tab.transcribe': {
      const q = st.tracks.filter(t => (p.track ? t.id === p.track : t.transcription === 'queued' || t.transcription === 'failed'));
      q.forEach(t => { t.transcription = 'queued'; t.error = null; });
      st.phase = 'working';
      if (variant !== 'working') runTranscription();   // `working` se queda quieto para la captura
      return { queued: q.map(t => t.id) };
    }
    case 'tab.cancel': clearInterval(timer); st.tracks.forEach(t => { if (t.transcription === 'transcribing') { t.transcription = 'queued'; t.progress = null; } }); emitState(); return { cancelled: true };
    case 'tab.beatClick': case 'tab.noteClick': {
      const per = st.selectedTrack === 'bass' ? 4 : 8;
      st.selection = { track: st.selectedTrack, beat: p.bar * per + p.beat, tick: 0, string: p.string ?? null, summary: `Compás ${p.bar + 1}, pulso ${p.beat + 1}`,
        barRange: { bar: p.bar, start: bars[p.bar].start, end: bars[p.bar].start + 2 } };
      mockEmit('tab.selection', { bar: p.bar, fraction: p.beat / per });
      mockEmit('study.position', { seconds: bars[p.bar].start + (p.beat / per) * 2, playing: false });
      return clone(st);
    }
    case 'tab.beatDrag': return clone(st);
    case 'tab.span': {
      if (p.action === 'clear') { st.span = null; mockEmit('tab.range', { startBar: -1, startFraction: 0, endBar: 0, endFraction: 0 }); }
      return clone(st);
    }
    case 'tab.toggleMute': track(p.track).muted = !track(p.track).muted; return clone(st);
    case 'tab.toggleSolo': track(p.track).solo = !track(p.track).solo; st.anySolo = st.tracks.some(t => t.solo); return clone(st);
    case 'tab.setListening': track(p.track).listening = p.on; st.listenMode = st.tracks.every(t => t.listening) ? 'transcription' : st.tracks.some(t => t.listening) ? 'mixed' : 'stems'; return clone(st);
    case 'tab.setAllListening':
      readyTracks().forEach(t => { t.listening = p.on; t.synth = p.on ? (variant === 'progress' ? 'rendering' : 'ready') : null; });
      st.listenMode = p.on ? 'transcription' : 'stems';
      return clone(st);
    case 'tab.edit':
      if (p.op === 'editMode') { st.editMode = !!p.on; if (!p.on) st.selection = null; }
      else if (p.op === 'deselect') st.selection = null;
      else if (p.op === 'tuning') { const t = track(p.track); t.tuning = { ...t.tuning, preset: p.preset, name: p.preset === 'dropD' ? 'Drop D' : 'Estándar' }; }
      else { st.flash = 'Edición simulada: ' + p.op; setTimeout(() => { st.flash = null; emitState(); }, 2500); }
      return clone(st);
    case 'tab.exportName': return { fileName: 'ToneForge - Maqueta.gp' };
    case 'tab.export': return { saved: true, path: 'C:\\Users\\jorge\\Documents\\Maqueta.gp' };
    default: throw new BridgeError('unknown-method', method);
  }
}

setMockHandler((method, p) => (method.startsWith('tab.') ? handle(method, p) : undefined));
