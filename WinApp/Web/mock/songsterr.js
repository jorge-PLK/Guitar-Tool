// Simulador de `tab.songsterr.*` para `?mock=1` (sin núcleo). Estados con `?ss=` (en tf-webdev: --mock-query "tab=choose&ss=...").
//   results (por omisión) | searching | loading (leyendo pistas) | rateLimited | noResults | offline | detailError
//   working | pairing | importFailed
// Y `host.preview.show/hide` (anfitrión): `?ssPreview=unsupported` lo da como no soportado.
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';
import { mockTabPatch } from '../tab/mock-tab.js';

const params = new URLSearchParams(location.search);
const variant = params.get('ss') ?? 'results';
const clone = o => JSON.parse(JSON.stringify(o));
const url = id => `https://www.songsterr.com/a/wsa/song-tab-s${id}`;

const SONGS = [
  { songId: 7, artist: 'Metallica', title: 'Enter Sandman' },
  { songId: 8, artist: 'Metallica', title: 'Enter Sandman (Live)' },
  { songId: 9, artist: 'Metallica', title: 'Enter Sandman (Bass)' },
  { songId: 10, artist: 'Apocalyptica', title: 'Enter Sandman' },
  { songId: 11, artist: 'Metallica', title: 'Enter Sandman (Acoustic)' },
  { songId: 12, artist: 'Vitamin String Quartet', title: 'Enter Sandman' },
];
const STD = [64, 59, 55, 50, 45, 40];
const TRACKS = [
  { partId: 0, name: 'Rítmica', instrument: 'Overdriven Guitar', tuning: STD, tuningText: 'E A D G B E' },
  { partId: 1, name: 'Solista', instrument: 'Distortion Guitar', tuning: STD, tuningText: 'E A D G B E' },
  { partId: 2, name: 'Bajo', instrument: 'Electric Bass', tuning: [43, 38, 33, 28], tuningText: 'E A D G' },
  { partId: 3, name: 'Batería', instrument: 'Drums', tuning: null, tuningText: '-' },
];
const NO_RESULTS = { kind: 'noResults', message: 'Songsterr no tiene este tema.', canRetry: false, suggestion: 'Puedes transcribir el tema automáticamente.' };
const ISSUES = {
  rateLimited: { kind: 'rateLimited', message: 'Songsterr está limitando las peticiones. Espera un momento y reintenta.', canRetry: true, suggestion: null },
  noResults: NO_RESULTS,
  offline: { kind: 'offline', message: 'No hay conexión con Songsterr.', canRetry: true, suggestion: null },
};

const choice = (track, name, sim) => ({ track, name, similarity: sim, label: sim == null ? name : `${name} (${Math.round(sim * 100)} %)` });
const PAIRING = {
  intro: 'Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio.',
  slots: [
    { stemId: 'guitar-rhythm', name: 'Guitarra rítmica', kind: 'guitar', role: 'guitar', track: 0, confidence: 0.82, confidenceText: '82 %',
      choices: [choice(0, 'Rítmica', 0.82), choice(1, 'Solista', 0.41)], solos: [] },
    { stemId: 'guitar-lead', name: 'Guitarra solista', kind: 'guitar', role: 'lead', track: null, confidence: null, confidenceText: null,
      choices: [choice(0, 'Rítmica', 0.3), choice(1, 'Solista', 0.74)],
      solos: [
        { index: 0, start: 12, end: 30, clock: '0:12', track: 1, confidence: 0.74, confidenceText: '74 %', choices: [choice(1, 'Solista', 0.74)] },
        { index: 1, start: 95, end: 130, clock: '1:35', track: null, confidence: null, confidenceText: null, choices: [choice(1, 'Solista', 0.28)] },
      ] },
    { stemId: 'bass', name: 'Bajo', kind: 'bass', role: 'bass', track: 2, confidence: 0.31, confidenceText: '31 %', choices: [choice(2, 'Bajo', 0.31)], solos: [] },
    { stemId: 'drums', name: 'Batería', kind: 'drums', role: 'drums', track: 3, confidence: null, confidenceText: 'sin medir', choices: [choice(3, 'Batería', null)], solos: [] },
  ],
  extraNames: [],
  extraText: null,
  warnings: ['La afinación del bajo (E A D G) no coincide con la del stem; se transcribe igual.',
    'El tempo de Songsterr (123 BPM) difiere 2 BPM del análisis; se alinea con el audio.'],
};

let s = { open: false };
let timer = 0;
const emit = () => mockEmit('tab.songsterr.state', clone(s));
const later = (ms, fn) => { clearTimeout(timer); timer = setTimeout(fn, ms); };

const base = () => ({
  open: true, stage: 'choosing', query: 'Metallica · Enter Sandman',
  search: { phase: 'searching', issue: null }, results: [], selected: null, loadingSongId: null, detailIssue: null, linkIssue: null,
  busy: true, canUse: false, workingText: null, failure: null, pairing: null,
});
const results = selectedId => SONGS.map(r => ({ ...r, selected: r.songId === selectedId, loading: false, previewUrl: url(r.songId) }));
const selectedOf = id => { const r = SONGS.find(x => x.songId === id); return { songId: id, revisionId: id * 100, artist: r.artist, title: r.title, previewUrl: url(id), tracks: TRACKS }; };
const withResults = id => ({ ...base(), search: { phase: 'results', issue: null }, results: results(id), selected: id ? selectedOf(id) : null, busy: false, canUse: id != null });

function startSearch() {
  s = base();
  if (variant === 'searching') return;
  later(700, () => {
    if (variant === 'rateLimited' || variant === 'noResults' || variant === 'offline') {
      s = { ...base(), search: { phase: 'failed', issue: ISSUES[variant] }, busy: false };
    } else if (variant === 'loading') {
      s = { ...withResults(7), selected: null, loadingSongId: 7, busy: true, canUse: false };
    } else if (variant === 'detailError') {
      s = { ...withResults(null), detailIssue: ISSUES.rateLimited };
    } else s = withResults(7);
    emit();
  });
}

function startImport() {
  s = { ...s, stage: 'working', workingText: 'Descargando pistas de Songsterr…', busy: true, canUse: false };
  later(1200, () => {
    s = { ...s, workingText: 'Alineando con el audio…' }; emit();
    later(1200, () => {
      if (variant === 'importFailed') s = { ...s, stage: 'failed', workingText: null, failure: { ...ISSUES.offline, suggestion: 'Puedes transcribir el tema automáticamente.' } };
      else s = { ...s, stage: 'pairing', workingText: null, pairing: clone(PAIRING), busy: false };
      emit();
    });
  });
}

function directStage() {
  if (variant === 'working') { s = { ...withResults(7), stage: 'working', workingText: 'Leyendo Songsterr…', busy: true }; return true; }
  if (variant === 'pairing') { s = { ...withResults(7), stage: 'pairing', pairing: clone(PAIRING) }; return true; }
  if (variant === 'importFailed') { s = { ...withResults(7), stage: 'failed', failure: { ...ISSUES.offline, suggestion: 'Puedes transcribir el tema automáticamente.' } }; return true; }
  return false;
}

function handle(method, p) {
  if (method === 'host.preview.show') { if (params.get('ssPreview') === 'unsupported') throw new BridgeError('unsupported', 'unsupported'); return {}; }
  if (method === 'host.preview.hide') return {};
  if (!method.startsWith('tab.songsterr.')) return undefined;
  const m = method.slice('tab.songsterr.'.length);
  if (m !== 'open' && !s.open) { if (m === 'close' || m === 'state') return clone(s); throw new BridgeError('not-open', 'No hay ninguna hoja abierta.'); }
  switch (m) {
    case 'open': case 'review': if (!s.open || m === 'review') { if (!directStage()) startSearch(); } return clone(s);
    case 'state': return clone(s);
    case 'close': clearTimeout(timer); s = { open: false }; return clone(s);
    case 'search': case 'retry': startSearch(); return clone(s);
    case 'select': {
      s = { ...withResults(p.songId), selected: null, loadingSongId: p.songId, busy: true, canUse: false, results: results(p.songId) };
      later(500, () => { s = withResults(p.songId); emit(); });
      return clone(s);
    }
    case 'link': {
      const id = Number((String(p.link).match(/-s(\d+)/) ?? [])[1]);
      if (!id) { s = { ...s, linkIssue: { kind: 'invalidLink', message: 'Ese enlace no es de una canción de Songsterr.', canRetry: false, suggestion: null } }; return clone(s); }
      s = { ...s, linkIssue: null }; return clone(s);
    }
    case 'use': startImport(); return clone(s);
    case 'back': clearTimeout(timer); s = { ...withResults(7), pairing: null }; return clone(s);
    case 'retryImport': startImport(); return clone(s);
    case 'assign': {
      const slot = s.pairing.slots.find(x => x.stemId === p.stemId);
      const set = (o, track, choices) => {
        o.track = track ?? null;
        const c = choices.find(x => x.track === o.track);
        o.confidence = c?.similarity ?? null; o.confidenceText = o.track == null ? null : (c?.similarity == null ? 'sin medir' : `${Math.round(c.similarity * 100)} %`);
      };
      if (p.solo != null) set(slot.solos[p.solo], p.track, slot.solos[p.solo].choices); else set(slot, p.track, slot.choices);
      return clone(s);
    }
    case 'allAutomatic':
      s.pairing.slots.forEach(sl => { sl.track = null; sl.confidence = null; sl.confidenceText = null; sl.solos.forEach(so => { so.track = null; so.confidence = null; so.confidenceText = null; }); });
      return clone(s);
    case 'accept': {
      const slots = s.pairing.slots, warnings = s.pairing.warnings;
      s = { open: false };
      return mockTabPatch(st => {
        st.source = 'songsterr'; st.phase = 'ready'; st.notices = warnings;
        for (const t of st.tracks) {
          const slot = slots.find(x => x.stemId === t.id) ?? (t.id === 'guitar' ? slots[0] : null);
          if (slot && slot.track != null) { t.origin = 'songsterr'; t.transcription = 'ready'; }
          else { t.transcription = 'queued'; t.progress = null; }
        }
      });
    }
    case 'automatic': s = { open: false }; return mockTabPatch(st => { st.source = 'automatic'; st.phase = 'ready'; });
    default: throw new BridgeError('unknown-method', method);
  }
}

setMockHandler(handle);
