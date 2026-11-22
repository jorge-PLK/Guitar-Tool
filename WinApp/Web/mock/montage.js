// Simulador de `montage.*` para `?mock=1` (sin núcleo): instantánea con tomas sintéticas, transporte con reloj, exportación
// con progreso, encuadre y fotogramas JPEG dibujados en la página (`frames.montage`).
// Variantes: ?mlayout=side|grid|stack|single|single-landscape, ?mstate=default|three|exporting|done|failed|empty|preparing|hevc
// (hevc: el códec guardado viene del Mac pero solo hay H.264 -> sin selector), ?msheet=1 abre la hoja de encuadre.
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';

const q = new URLSearchParams(location.search);
const variant = q.get('mstate') ?? 'default';
const EVENT_HZ = 30, FRAME_HZ = 10;
const SPAN = { start: 20, end: 60 };
const clone = o => JSON.parse(JSON.stringify(o));

let st = null, open = false, timer = 0, lastTick = 0, seq = 0, expTimer = 0, previewTimer = 0;

function fresh(projectId) {
  const three = variant !== 'default' && variant !== 'empty';
  const lanes = [
    { id: 'p-robe', takeId: 't-robe', partName: 'Robe · rítmica', isSolo: false, presence: [{ start: 20, end: 60 }], take: { start: 14, end: 62 }, hasVideo: true, rotation: 0 },
    { id: 'p-uoho', takeId: 't-uoho', partName: 'Uoho · rítmica', isSolo: false, presence: [{ start: 20, end: 60 }], take: { start: 18, end: 60 }, hasVideo: !!three, rotation: 0 },
  ];
  if (three) lanes.push({ id: 'p-solo', takeId: 't-solo', partName: 'Solo · solista', isSolo: true, replaces: 'rhythm', presence: [{ start: 40, end: 60 }], take: { start: 38, end: 61 }, hasVideo: true, rotation: 90 });
  const layout = q.get('mlayout') ?? 'side';
  st = {
    projectId, title: 'So payaso', artist: 'Extremoduro', layout, lanes, cuts: [], caption: true, showPartLabels: true, keepVideoAspect: false,
    cutGaps: false, singleRhythmPartId: null, hasPlan: variant !== 'empty',
    export: { codec: variant === 'hevc' ? 'hevc' : 'h264', container: 'mov', resolution: { width: 1920, height: 1080 }, fps: 30, normalize: true, limiter: true, trackWAVs: true },
    framing: Object.fromEntries(lanes.map(l => [l.takeId, { takeId: l.takeId, status: 'ready', progress: 1, samples: 24, detected: 21, mode: 'fixed', manualBox: null, followZoom: 1, followOffset: { x: 0, y: 0 } }])),
    exportStatus: { phase: 'idle', progress: 0 },
    playing: false, position: SPAN.start, previewPhase: variant === 'preparing' ? 'preparing' : 'ready',
  };
  if (variant === 'exporting') st.exportStatus = { phase: 'running', stage: 'Componiendo el vídeo', progress: 0.42 };
  if (variant === 'done') st.exportStatus = { phase: 'done', progress: 1, result: { path: 'C:\\Users\\jorge\\ToneForge\\Extremoduro - So payaso\\video\\So payaso-side.mov', tracksDirectory: 'C:\\Users\\jorge\\ToneForge\\Extremoduro - So payaso\\video\\So payaso-side-pistas', finalLUFS: -14.1, finalTruePeakDB: -1.3, normalized: true, limitedByPeak: false, limiterEnabled: true, limiterApplied: true, limiterMaxReductionDB: 2.4, limiterOutOfTolerance: false, clippedFiles: [], codec: 'h264' } };
  if (variant === 'failed') st.exportStatus = { phase: 'failed', progress: 0.3, message: 'No se pudo exportar el vídeo (el códec no está disponible).' };
  if (layout === 'single' || layout === 'single-landscape') st.cuts = [{ id: 'c1', time: 32, partId: 'p-uoho' }, { id: 'c2', time: 46, partId: null }];
}

const isSingle = () => st.layout === 'single' || st.layout === 'single-landscape';
const isPortrait = () => st.layout === 'stack' || st.layout === 'single';

function snapshot() {
  const lanes = st.lanes;
  const s = {
    projectId: st.projectId, title: st.title, artist: st.artist, layout: st.layout, isPortrait: isPortrait(), isSingleShot: isSingle(),
    canvasLabel: isPortrait() ? '1080 × 1920' : '1920 × 1080', keepAspectApplies: st.layout === 'stack' || isSingle(),
    caption: st.caption, showPartLabels: st.showPartLabels, keepVideoAspect: st.keepVideoAspect, cutGaps: st.cutGaps,
    singleRhythmPartId: st.singleRhythmPartId, singleRhythmCandidates: lanes.filter(l => !l.isSolo && l.hasVideo).map(l => l.id),
    hasPlan: st.hasPlan, hasVideo: lanes.some(l => l.hasVideo), span: SPAN, barDuration: 2, songDuration: 215, anticipationLabel: '0,5 s',
    lanes: clone(lanes), audioOnlyParts: lanes.filter(l => !l.hasVideo).map(l => l.partName), missingParts: variant === 'three' ? ['Guitarra 4'] : [],
    segments: st.cutGaps ? [{ start: 20, end: 36, fadeIn: true, fadeOut: false }, { start: 44, end: 60, fadeIn: false, fadeOut: true }] : [{ start: 20, end: 60, fadeIn: true, fadeOut: true }],
    sections: [{ id: 's1', name: 'Intro', start: 0, end: 20, solo: false }, { id: 's2', name: 'Estrofa', start: 20, end: 40, solo: false }, { id: 's3', name: 'Solo', start: 40, end: 70, solo: true }],
    cuts: st.cuts.map(c => ({ ...c, covered: !(c.partId === 'p-uoho' && c.time > 55),
      eligible: lanes.filter(l => l.hasVideo && !(l.id === 'p-uoho' && c.time > 55)).map(l => l.id) })), cutCandidates: lanes.filter(l => l.hasVideo).map(l => l.id),
    planeShots: [], framing: Object.values(st.framing).filter(f => lanes.some(l => l.takeId === f.takeId)),
    isAnalyzing: Object.values(st.framing).some(f => f.status === 'analyzing'),
    export: { ...st.export, effectiveCodec: 'h264', size: isPortrait() ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 },
      canExport: st.hasPlan && st.exportStatus.phase !== 'running',
      options: { codecs: ['h264'], containers: ['mov', 'mp4'], resolutions: [{ width: 1280, height: 720 }, { width: 1920, height: 1080 }, { width: 3840, height: 2160 }], fps: [24, 25, 30, 50, 60] } },
    exportStatus: clone(st.exportStatus),
    preview: { phase: st.previewPhase, audio: { phase: st.previewPhase === 'ready' ? 'ready' : 'preparing', progress: 0.5 }, fps: 15, maxDimension: 640, width: 640, height: 360, delivered: 0, skipped: 0, lastFrameMillis: 4 },
    transport: { playing: st.playing, position: st.position, videoPosition: st.position - SPAN.start, span: SPAN },
  };
  if (isSingle()) {
    const vids = lanes.filter(l => l.hasVideo && !l.isSolo);
    const cuts = [...st.cuts].sort((a, b) => a.time - b.time);
    const marks = [SPAN.start, ...cuts.map(c => c.time), SPAN.end];
    s.planeShots = marks.slice(0, -1).map((a, i) => ({ start: a, end: marks[i + 1], partId: i === 0 ? vids[0]?.id : cuts[i - 1].partId ?? vids[0]?.id, black: false }));
  }
  return s;
}

const state = () => mockEmit('montage.state', snapshot());
function need() { if (!open) throw new BridgeError('not-open', 'No hay ningún tema abierto'); }

// Fotogramas: se dibujan en un canvas y viajan como JPEG en base64, igual que los del núcleo.
const cv = document.createElement('canvas');
function pushFrame() {
  const portrait = isPortrait();
  cv.width = portrait ? 360 : 640; cv.height = portrait ? 640 : 360;
  const g = cv.getContext('2d');
  const t = st.position - SPAN.start;
  g.fillStyle = '#0B0C0E'; g.fillRect(0, 0, cv.width, cv.height);
  const vids = st.lanes.filter(l => l.hasVideo);
  const n = st.layout === 'grid' ? 4 : st.layout === 'side' || st.layout === 'stack' ? Math.min(vids.length, 2) : 1;
  const cols = st.layout === 'grid' ? 2 : st.layout === 'side' ? n : 1, rows = Math.ceil(n / cols);
  const cw = cv.width / cols, ch = cv.height / rows;
  for (let i = 0; i < n; i++) {
    const x = (i % cols) * cw, y = Math.floor(i / cols) * ch, pad = 6;
    const grad = g.createLinearGradient(x, y, x + cw, y + ch);
    grad.addColorStop(0, '#2b3340'); grad.addColorStop(1, '#14181d');
    g.fillStyle = grad; g.beginPath(); g.roundRect(x + pad, y + pad, cw - 2 * pad, ch - 2 * pad, 10); g.fill();
    g.fillStyle = ['#5BC0EB', '#F2A33A', '#6FD99E', '#C97F9E'][i % 4];
    g.beginPath(); g.arc(x + cw / 2 + Math.sin(t * 2 + i) * cw * 0.1, y + ch / 2, Math.min(cw, ch) * 0.16, 0, 7); g.fill();
    g.fillStyle = '#E8EAED'; g.font = '14px sans-serif';
    if (st.showPartLabels) g.fillText((vids[i] ?? vids[0]).partName, x + 16, y + ch - 14);
  }
  const jpeg = cv.toDataURL('image/jpeg', 0.7).split(',')[1];
  mockEmit('frames.montage', { seq: ++seq, width: cv.width, height: cv.height, ptsMs: Math.round(t * 1000), jpeg });
}

function tick() {
  const now = performance.now(), dt = (now - lastTick) / 1000;
  lastTick = now;
  st.position += dt;
  if (st.position >= SPAN.end) { st.position = SPAN.end; st.playing = false; stopClock(); pushFrame(); mockEmit('montage.position', { seconds: st.position, videoSeconds: st.position - SPAN.start, playing: false }); state(); return; }
  mockEmit('montage.position', { seconds: st.position, videoSeconds: st.position - SPAN.start, playing: true });
}
function startClock() {
  if (timer) return;
  lastTick = performance.now();
  timer = setInterval(tick, 1000 / EVENT_HZ);
  previewTimer = setInterval(pushFrame, 1000 / FRAME_HZ);
}
function stopClock() { clearInterval(timer); clearInterval(previewTimer); timer = previewTimer = 0; }

function runExport() {
  clearInterval(expTimer);
  expTimer = setInterval(() => {
    const e = st.exportStatus;
    if (e.phase !== 'running') { clearInterval(expTimer); return; }
    e.progress = Math.min(1, e.progress + 0.06);
    e.stage = e.progress < 0.3 ? 'Mezclando el audio' : e.progress < 0.9 ? 'Componiendo el vídeo' : 'Normalizando el volumen';
    if (e.progress >= 1) {
      clearInterval(expTimer);
      st.exportStatus = { phase: 'done', progress: 1, result: { path: 'C:\\Users\\jorge\\ToneForge\\Extremoduro - So payaso\\video\\So payaso-' + st.layout + '.mov', finalLUFS: -14.0, finalTruePeakDB: -1.2, normalized: st.export.normalize, limitedByPeak: false, limiterEnabled: st.export.limiter, limiterApplied: false, limiterMaxReductionDB: 0, limiterOutOfTolerance: false, clippedFiles: [], codec: 'h264' } };
      state();
    } else mockEmit('montage.export', { phase: 'running', stage: e.stage, progress: e.progress });
  }, 250);
}

setMockHandler((method, p) => {
  if (!method.startsWith('montage.')) return undefined;
  const m = method.slice(8);
  if (m === 'open') { open = true; fresh(p.projectId); if (st.previewPhase === 'ready') setTimeout(pushFrame, 100); if (variant === 'exporting') runExport(); return snapshot(); }
  need();
  const lane = id => st.lanes.find(l => l.id === id);
  switch (m) {
    case 'close': open = false; stopClock(); clearInterval(expTimer); return {};
    case 'snapshot': return snapshot();
    case 'setLayout': st.layout = p.layout; setTimeout(pushFrame, 50); return snapshot();
    case 'setSingleRhythm': st.singleRhythmPartId = p.partId ?? null; return snapshot();
    case 'setCutGaps': st.cutGaps = p.on; return snapshot();
    case 'setCaption': st.caption = p.on; return snapshot();
    case 'setShowPartLabels': st.showPartLabels = p.on; return snapshot();
    case 'setKeepVideoAspect': st.keepVideoAspect = p.on; return snapshot();
    case 'moveLane': { const a = st.lanes.findIndex(l => l.id === p.id), b = st.lanes.findIndex(l => l.id === p.to); if (a >= 0 && b >= 0) { const [x] = st.lanes.splice(a, 1); st.lanes.splice(b, 0, x); } return snapshot(); }
    case 'setPartOrder': return snapshot();
    case 'addCut': { const id = 'c' + (Date.now() % 100000); st.cuts.push({ id, time: Math.round(p.time * 2) / 2, partId: p.partId ?? null }); return { cutId: id, snapshot: snapshot() }; }
    case 'moveCut': { const c = st.cuts.find(x => x.id === p.id); if (c) c.time = Math.round(p.time * 2) / 2; return snapshot(); }
    case 'setCutPart': { const c = st.cuts.find(x => x.id === p.id); if (c) c.partId = p.partId ?? null; return snapshot(); }
    case 'removeCut': st.cuts = st.cuts.filter(x => x.id !== p.id); return snapshot();
    case 'clearCuts': st.cuts = []; return snapshot();
    case 'setExport': Object.assign(st.export, p); return snapshot();
    case 'startExport': st.exportStatus = { phase: 'running', stage: 'Mezclando el audio', progress: 0 }; runExport(); return snapshot();
    case 'cancelExport': clearInterval(expTimer); st.exportStatus = { phase: 'cancelled', progress: 0 }; return snapshot();
    case 'dismissExport': st.exportStatus = { phase: 'idle', progress: 0 }; return snapshot();
    case 'reveal': return { revealed: true };
    case 'setFraming': { const f = st.framing[p.takeId]; const { takeId, clearManualBox, ...rest } = p; Object.assign(f, rest); if (clearManualBox) f.manualBox = null; return snapshot(); }
    case 'resetFraming': { const f = st.framing[p.takeId]; Object.assign(f, { manualBox: null, followZoom: 1, followOffset: { x: 0, y: 0 } }); return snapshot(); }
    case 'reanalyze': { const f = st.framing[p.takeId]; f.status = 'analyzing'; f.progress = 0.3; setTimeout(() => { f.status = 'ready'; f.progress = 1; state(); }, 1500); return snapshot(); }
    case 'rotateTake': { const l = st.lanes.find(x => x.takeId === p.takeId); if (l) l.rotation = ((l.rotation ?? 0) + 90) % 360; return snapshot(); }
    case 'framingFrame': {
      const f = st.framing[p.takeId], z = f.mode === 'follow' ? 1 / f.followZoom : 1;
      const w = 0.4 * z, h = 0.6 * z;
      const box = f.mode === 'fixed' ? (f.manualBox ?? { x: 0.3, y: 0.2, width: 0.4, height: 0.6 }) : { x: Math.min(0.5 - w / 2 + f.followOffset.x, 1 - w), y: Math.min(0.5 - h / 2 + f.followOffset.y, 1 - h), width: w, height: h };
      return { path: 'c1/framing-mock.svg', width: 1280, height: 720, time: p.time, version: 1, box };
    }
    case 'play': st.playing = true; startClock(); return snapshot();
    case 'pause': st.playing = false; stopClock(); pushFrame(); return snapshot();
    case 'seek': st.position = Math.min(Math.max(p.seconds, SPAN.start), SPAN.end); if (!st.playing) pushFrame(); return snapshot();
    case 'setPreviewFps': return snapshot();
    default: throw new BridgeError('bad-params', 'Método desconocido: ' + method);
  }
});
