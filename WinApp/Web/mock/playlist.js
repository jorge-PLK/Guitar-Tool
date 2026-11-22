// Simulador de playlist.* y del enlace de lista de link.resolve para `?mock=1` (contrato W2-J, sin núcleo).
// Variantes con `?playlist=`: spotify (por omisión) | youtube | truncada (banner de 100 temas) | leyendo (link.resolve espera a link.cancel) |
//   error (fallo de lectura) | limite (la cola se detiene por rate-limited) | roto (se detiene por yt-dlp roto) | fallos (algún tema falla y otro no se separa).
// `?plfreeze=searching|running`: la búsqueda o la cola se queda parada a mitad (capturas).
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';

const q = new URLSearchParams(location.search);
const variant = q.get('playlist') ?? 'spotify';
const freeze = q.get('plfreeze');
const wait = ms => new Promise(r => setTimeout(r, ms));
const FINAL = new Set(['imported', 'skipped', 'inLibrary', 'failed']);

const ERR_UNAVAILABLE = { code: 'video-unavailable', title: 'Vídeo no disponible', detail: 'YouTube no deja descargar este vídeo (privado, borrado o restringido en tu país).', suggestsUpdate: false };
const ERR_RATE = { code: 'rate-limited', title: 'YouTube está limitando las peticiones', detail: 'Espera unos minutos.', suggestsUpdate: false };
const ERR_BROKEN = { code: 'extractor-broken', title: 'yt-dlp puede estar desactualizado (versión 2026.10.26)', detail: 'ERROR: [youtube] Unable to extract nsig function code', suggestsUpdate: true };

const TRACKS = [
  ['3aaa', 'La luna me sabe a poco', 'Marea', 253], ['3bbb', 'So payaso', 'Extremoduro', 264], ['3ccc', 'No hay tregua', 'Barricada', 213],
  ['3ddd', 'Entre dos tierras', 'Héroes del Silencio', 258], ['3eee', 'Masculino singular', 'Rosendo', 231],
  ['3fff', 'Dolores se llamaba Lola', 'Los Suaves', 275], ['3ggg', 'Ayatollah', 'Siniestro Total', 177], ['3hhh', 'Sin documentos', 'Los Rodríguez', 227],
];
const LIB = { id: '00000001-0000-4000-8000-000000000001', title: 'Entre dos tierras', artist: 'Héroes del Silencio' };

let st = null;       // sesión viva
let runToken = 0;
let loadingWaiter = null;
const youtube = () => variant === 'youtube';

function yt(id, title, channel, duration, extra = {}) {
  return { id, title, artist: channel, duration, thumbnail: `https://i.ytimg.com/vi/${id}/mqdefault.jpg`, source: 'youtube',
    url: `https://www.youtube.com/watch?v=${id}`, isClose: false, isLive: false, difference: null, inLibrary: null, ...extra };
}

function newSession() {
  const items = TRACKS.map(([id, title, artist, duration], n) => {
    const base = { id: youtube() ? `yt${id}` : id, title, artist, duration, kind: youtube() ? 'youtube' : 'spotify', selected: true, status: 'pending',
      candidates: [] };
    if (id === '3ddd') return { ...base, selected: false, status: 'inLibrary', inLibrary: LIB };
    if (id === '3eee') return { ...base, selected: false, possible: { id: LIB.id, title: 'Masculino singular (directo)', artist: 'Rosendo' } };
    if (youtube()) base.chosen = yt(base.id, title, artist, duration);
    return base;
  });
  const total = variant === 'truncada' ? 100 : items.length;
  return { step: 'tracks', name: youtube() ? 'Rock en español' : 'Rock en español · esenciales', source: youtube() ? 'youtube' : 'spotify', kind: 'playlist',
    mayBeTruncated: variant === 'truncada', items, total, didRun: false, cancelled: false, update: { updating: false, alreadyLatest: false },
    warnings: [], searchDone: 0, searchTotal: 0, error: null };
}

function snapshot() {
  const s = st;
  const sel = s.items.filter(i => i.selected);
  const count = f => s.items.filter(f).length;
  const totals = { total: s.total, selected: sel.length, imported: count(i => i.selected && i.status === 'imported'), skipped: count(i => i.selected && i.status === 'skipped'),
    failed: count(i => i.selected && i.status === 'failed'), inLibrary: count(i => i.status === 'inLibrary'),
    remaining: sel.filter(i => !FINAL.has(i.status)).length, queued: sel.filter(i => i.chosen && !FINAL.has(i.status)).length, duplicates: 0 };
  const live = ['searching', 'running', 'stopped', 'loading'].includes(s.step);
  const cur = Math.min(totals.selected - totals.remaining + 1, Math.max(totals.selected, 1));
  const indicator = s.step === 'searching' ? `Buscando ${Math.min(s.searchDone + 1, Math.max(s.searchTotal, 1))} de ${s.searchTotal}`
    : s.step === 'running' ? `Importando ${cur} de ${totals.selected}` : s.step === 'stopped' ? 'Importación detenida'
    : s.step === 'summary' ? (s.cancelled ? 'Importación cancelada' : 'Importación terminada') : null;
  const out = { step: s.step, name: s.name, source: s.source, kind: s.kind, mayBeTruncated: s.mayBeTruncated, isLive: live, totals,
    summary: { imported: totals.imported, skipped: totals.skipped, inLibrary: totals.inLibrary, failed: totals.failed, remaining: totals.remaining, cancelled: s.cancelled },
    progress: totals.selected ? (totals.selected - totals.remaining) / totals.selected : 0, update: s.update, warnings: s.warnings, items: s.items };
  if (indicator) out.indicator = indicator;
  if (s.step === 'searching') { out.searchDone = s.searchDone; out.searchTotal = s.searchTotal; }
  if (s.error && (s.step === 'stopped' || s.step === 'error')) out.error = s.error;
  return JSON.parse(JSON.stringify(out));
}
const push = () => { if (st) mockEmit('playlist.changed', snapshot()); };
const job = (i, p) => mockEmit('jobs.progress', { id: `playlist-${i.id}`, title: `${i.artist} - ${i.title}`, stage: p.stage ?? 'download', state: p.state ?? 'running',
  fraction: p.fraction ?? null, text: p.text ?? '', error: null });

async function search() {
  const mine = ++runToken;
  const todo = st.items.filter(i => i.selected && i.status === 'pending' && !i.chosen);
  st.step = 'searching'; st.searchTotal = todo.length; st.searchDone = 0; push();
  for (const i of todo) {
    i.status = 'searching'; push();
    await wait(600);
    if (mine !== runToken) return;
    const d = i.duration;
    if (i.id === '3hhh') { i.status = 'doubtful'; i.candidates = [yt('x1', 'Los Rodríguez - Sin documentos (en vivo, 1995)', 'Rock en vivo', d + 41, { difference: 41, isLive: true }),
      yt('x2', 'Sin documentos - karaoke', 'Karaoke España', d - 19, { difference: -19 })]; }
    else if (i.id === '3ggg') { i.status = 'proposed'; i.candidates = [yt('y1', 'Siniestro Total - Ayatollah', 'Siniestro Total', d + 1, { isClose: true, difference: 1 }),
      yt('y2', 'Ayatollah (Remasterizado)', 'Siniestro Total - Topic', d + 6, { difference: 6 }),
      yt('y3', 'Siniestro Total - Ayatollah', 'Discos Radiactivos', d - 2, { isClose: true, difference: -2, inLibrary: { id: LIB.id, title: LIB.title, artist: LIB.artist } })]; }
    else { i.status = 'proposed'; i.candidates = [yt(`${i.id}v1`, `${i.artist} - ${i.title}`, i.artist, d - 1, { isClose: true, difference: -1 }),
      yt(`${i.id}v2`, `${i.title} (directo)`, `${i.artist} Oficial`, d + 3, { isClose: true, isLive: true, difference: 3 })]; i.chosen = i.candidates[0]; }
    if (i.status === 'proposed' && !i.chosen) i.chosen = i.candidates[0];
    st.searchDone++;
    if (freeze === 'searching' && st.searchDone === 3) { i.status = 'searching'; st.items[5].status = 'searching'; push(); return; }
    push();
  }
  st.step = 'review'; push();
}

async function runQueue() {
  const mine = ++runToken;
  st.didRun = true; st.cancelled = false; st.error = null; st.step = 'running'; push();
  let n = 0;
  for (const i of st.items.filter(x => x.selected && x.chosen && !FINAL.has(x.status))) {
    n++;
    if (variant === 'limite' && n === 3 && !st.limited) { st.limited = true; st.error = ERR_RATE; st.step = 'stopped'; push(); return; }
    if (variant === 'roto' && n === 3 && !st.fixed) { st.error = ERR_BROKEN; st.step = 'stopped'; push(); return; }
    i.status = 'downloading'; i.stage = 'download';
    for (let f = 0; f <= 1; f += 0.2) {
      i.progress = f; push(); job(i, { fraction: f, text: `Descargando audio… ${Math.round(f * 100)} %` });
      if (freeze === 'running' && n === 3 && f >= 0.4) { i.progress = 0.42; push(); return; }
      await wait(350);
      if (mine !== runToken) { i.status = 'pending'; delete i.stage; delete i.progress; return; }
    }
    i.stage = 'convert'; delete i.progress; push(); job(i, { stage: 'import', text: 'Convirtiendo a WAV…' });
    await wait(500);
    if (mine !== runToken) { i.status = 'pending'; delete i.stage; return; }
    delete i.stage;
    if (variant === 'fallos' && i.id.endsWith('3bbb')) { i.status = 'failed'; i.error = ERR_UNAVAILABLE; }
    else { i.status = 'imported'; if (variant === 'fallos' && i.id.endsWith('3ggg')) st.warnings = ['No se pudo separar Ayatollah: hay una separación en curso o en cola.']; }
    job(i, { state: i.status === 'failed' ? 'failed' : 'done', fraction: 1 });
    push();
  }
  st.step = 'summary'; push();
}

const need = () => { if (!st) throw new BridgeError('no-playlist', 'No hay ninguna lista abierta.'); };
const find = id => { const i = st.items.find(x => x.id === id); if (!i) throw new BridgeError('not-found', 'El tema no es de la lista.'); return i; };

const LIST_URL = /youtube\.com\/playlist|open\.spotify\.com\/(playlist|album)|^spotify:(playlist|album):/i;

function handle(method, p) {
  if (method === 'link.classify') {
    const u = String(p.url ?? '').trim();
    const source = /youtube|youtu\.be/i.test(u) ? 'youtube' : /spotify/i.test(u) ? 'spotify' : null;
    return { kind: !source ? 'unsupported' : LIST_URL.test(u) ? 'playlist' : 'track', source };
  }
  if (method === 'link.resolve') {
    const u = String(p.url ?? '');
    if (!/youtube\.com\/playlist|open\.spotify\.com\/(playlist|album)|^spotify:(playlist|album):/i.test(u)) return undefined;
    return (async () => {
      if (variant === 'leyendo') { await new Promise(res => { loadingWaiter = res; }); throw new BridgeError('cancelled', 'Cancelado\n'); }
      await wait(variant === 'spotify' || variant === 'truncada' ? 1200 : 600);
      if (variant === 'error') throw new BridgeError('spotify-unreadable', 'No se pudo leer la lista de Spotify\nLa lista es privada o Spotify ha cambiado su página. Prueba con una lista pública.');
      runToken++; st = newSession();
      return { link: 'playlist', pastedURL: u, title: st.name, artist: null, album: null, duration: null, thumbnail: null, existing: null, possibleDuplicate: null,
        noCloseCandidate: false, candidates: [], playlist: snapshot() };
    })();
  }
  if (method === 'link.cancel' && !p.jobId) {
    if (!loadingWaiter) return undefined;
    loadingWaiter(); loadingWaiter = null; return { cancelled: true };
  }
  if (!method.startsWith('playlist.')) return undefined;
  if (method === 'playlist.close') {
    if (!st) return { closed: false, live: false };
    const live = snapshot().isLive;
    if (live && !p.force) return { closed: false, live: true };
    runToken++; st = null; return { closed: true, live };
  }
  need();
  switch (method) {
    case 'playlist.state': return snapshot();
    case 'playlist.select': find(p.id).selected = !!p.selected; break;
    case 'playlist.selectAll': st.items.forEach(i => { if (i.status !== 'inLibrary' && !i.possible) i.selected = true; }); break;
    case 'playlist.selectNone': st.items.forEach(i => { i.selected = false; }); break;
    case 'playlist.continue':
      if (!st.items.some(i => i.selected)) break;
      if (youtube()) runQueue(); else search();
      break;
    case 'playlist.search': search(); break;
    case 'playlist.choose': {
      const i = find(p.id), c = i.candidates.find(x => x.id === p.candidateId);
      if (!c) throw new BridgeError('not-found', 'Ese candidato no es de este tema.');
      if (c.inLibrary) throw new BridgeError('in-library', 'Ese vídeo ya está en la biblioteca.');
      i.chosen = c; i.status = 'proposed'; break;
    }
    case 'playlist.skip': { const i = find(p.id); delete i.chosen; i.status = 'skipped'; break; }
    case 'playlist.start': runQueue(); break;
    case 'playlist.cancel':
      runToken++;
      if (st.step === 'searching') { st.items.forEach(i => { if (i.status === 'searching') i.status = 'pending'; }); st.step = st.items.some(i => i.chosen) ? 'review' : 'tracks'; }
      else if (st.step === 'running' || st.step === 'stopped') { st.items.forEach(i => { if (i.status === 'downloading') { i.status = 'pending'; delete i.stage; delete i.progress; } }); st.cancelled = true; st.step = 'summary'; }
      break;
    case 'playlist.resume': if (st.didRun) runQueue(); else search(); return snapshot();
    case 'playlist.updateAndRetry':
      st.update = { updating: true, alreadyLatest: false }; push();
      wait(900).then(() => { st.update = { updating: false, alreadyLatest: q.get('latest') === '1' }; if (!st.update.alreadyLatest) { st.fixed = true; runQueue(); } else push(); });
      break;
    case 'playlist.retryFailed':
      st.items.forEach(i => { if (i.status === 'failed') { i.status = 'pending'; delete i.error; } });
      variantFixed(); runQueue(); break;
    default: throw new BridgeError('unknown-method', `método desconocido: ${method}`);
  }
  push();
  return snapshot();
}
function variantFixed() { st.warnings = []; }

setMockHandler((method, p) => handle(method, p));
