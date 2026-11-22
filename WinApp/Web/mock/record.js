// Simulador de `record.*` para `?mock=1` (sin núcleo). Forma de Temp/win/step8-contract.md, «W2-R1 record.*».
// Variantes con `?rec=`: counting | recording | adjusting | punch | nocam | denied | failed | blocked | busyerr.
// `?frames=0` no emite fotogramas de cámara (se ve el rótulo de vista previa simulada). Los ficheros de las tomas son
// mock/media/take/{video.mp4,processed.wav}.
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';

const params = new URLSearchParams(location.search);
const variant = params.get('rec');
const FRAME_FPS = 10;
const BEAT_S = 0.5;

const clone = o => JSON.parse(JSON.stringify(o));
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const SECTIONS = [
  { id: uid(10), name: 'Intro', start: 0.5, end: 16.5, solo: false, color: null, paletteIndex: 0 },
  { id: uid(11), name: 'Estrofa 1', start: 16.5, end: 48.5, solo: false, color: null, paletteIndex: 1 },
  { id: uid(12), name: 'Estribillo', start: 48.5, end: 80.5, solo: false, color: null, paletteIndex: 2 },
  { id: uid(13), name: 'Solo', start: 80.5, end: 112.5, solo: true, color: null, paletteIndex: 3 },
];
const take = (n, id, best, extra = {}) => ({ id, number: n, createdAt: '2026-11-20T18:00:00Z', best, selected: false, discarded: false, durationSeconds: 8,
  songStart: 0.5, hasVideo: true, videoPath: 'take/video.mp4', videoOffsetMs: 40, videoRotation: 0, videoFormat: null, audioPath: 'take/processed.wav',
  punches: [], ...extra });

let s = null, open = false;
let timer = 0, frameTimer = 0, seq = 0, t0 = 0;

function fresh() {
  const robe = { id: uid(1), name: 'Robe · rítmica', replaces: 'rhythm', isLead: false, status: 'done', bestTakeId: uid(102), takes: [take(1, uid(101), false), take(2, uid(102), true)] };
  const uoho = { id: uid(2), name: 'Uoho · rítmica', replaces: 'left', isLead: false, status: 'done', bestTakeId: uid(103), takes: [take(1, uid(103), true)] };
  const solo = { id: uid(3), name: 'Solo', replaces: 'lead', isLead: true, status: 'pending', bestTakeId: null, takes: [] };
  const ch = (id, name, kind, extra = {}) => ({ id, kind, guitarRole: null, name, gainDB: 0, muted: false, solo: false, forcedMuted: false, ...extra });
  const cam = { state: 'simulated', message: null, name: 'iPhone (Continuity Camera)', label: '1080p · 30 fps', width: 1920, height: 1080, fps: 30, rotation: 0,
    defaultOffsetMs: 65, cameras: [{ id: 'sim-camera', name: 'iPhone (Continuity Camera)' }], chosenId: 'sim-camera' };
  if (variant === 'nocam') Object.assign(cam, { state: 'none', message: 'No hay ninguna cámara conectada.', name: null, label: null, defaultOffsetMs: null, cameras: [], chosenId: null });
  if (variant === 'denied') Object.assign(cam, { state: 'denied', message: 'Sin permiso de cámara: se grabará solo el audio. Concédelo en Configuración > Privacidad y seguridad > Cámara.', name: null, label: null, defaultOffsetMs: null });
  if (variant === 'failed') Object.assign(cam, { state: 'failed', message: 'No se pudo abrir la cámara (en uso por otra aplicación).', name: null, label: null, defaultOffsetMs: null });
  const snap = {
    projectId: '', title: '', phase: 'idle', countBeat: null, beatsPerBar: 4, barSeconds: 2.0, bpm: 120.0, downbeats: [], duration: 323.0, position: 0,
    busy: false, blockReason: null, loadError: null, messages: [], notices: [], takeSaveError: null, countIn: true, preRollBars: 2, startSectionId: null, startTime: 0,
    plannedStop: null, sections: clone(SECTIONS),
    guitarRoles: [{ role: 'rhythm', name: 'Guitarra rítmica' }, { role: 'left', name: 'Guitarra izq.' }, { role: 'right', name: 'Guitarra der.' }, { role: 'lead', name: 'Guitarra solista' }],
    parts: [robe, uoho, solo], activePartId: robe.id, nextTakeNumber: 3, selectedTakeId: null,
    punch: { enabled: false, in: null, out: null, ready: false },
    mix: { masterGainDB: -7.7, anySolo: false, outputName: 'Altavoces del MacBook Pro',
      channels: [ch('vocals', 'Voz', 'vocals'), ch('drums', 'Batería', 'drums'), ch('bass', 'Bajo', 'bass'),
        ch('guitar_left', 'Guitarra izq.', 'guitar', { guitarRole: 'left' }), ch('guitar_right', 'Guitarra der.', 'guitar', { guitarRole: 'right' })],
      takeChannels: [{ id: `take-${uoho.id}`, partId: uoho.id, name: 'Tú · Uoho · rítmica', gainDB: 0, muted: false, solo: false }] },
    camera: cam, offset: null, audio: { sessionOpen: true, hosting: true, recording: false, outputName: 'Altavoces del MacBook Pro' } };
  if (variant === 'blocked') snap.blockReason = 'Elige una parte.';
  if (variant === 'busyerr') { snap.messages = ['La toma se detuvo y se guardó lo grabado.']; snap.takeSaveError = 'No se pudo guardar la toma (disco lleno).'; }
  if (variant === 'punch') Object.assign(snap, { selectedTakeId: uid(102), punch: { enabled: true, in: 20, out: 36, ready: true } });
  return snap;
}

// Estado visible: la parte activa figura «Grabando» mientras hay una toma en curso (RecordController.status(of:), igual en AppCore).
const view = () => {
  const c = clone(s);
  if (c.phase !== 'idle' && c.phase !== 'adjusting') { const a = c.parts.find(p => p.id === c.activePartId); if (a) a.status = 'recording'; }
  return c;
};
const emit = () => mockEmit('record.state', view());

function frame() {
  const c = document.createElement('canvas');
  c.width = 640; c.height = 360;
  const g = c.getContext('2d');
  const t = (performance.now() - t0) / 1000;
  const grad = g.createLinearGradient(0, 0, 640, 360);
  grad.addColorStop(0, '#3A4A5C'); grad.addColorStop(1, '#6B4A3A');
  g.fillStyle = grad; g.fillRect(0, 0, 640, 360);
  g.fillStyle = 'rgba(255,255,255,.85)';
  g.beginPath(); g.arc(320 + 150 * Math.sin(t * 1.5), 180 + 60 * Math.cos(t * 2.1), 38, 0, 7); g.fill();
  g.fillStyle = '#fff'; g.font = '20px sans-serif'; g.fillText('Cámara simulada', 20, 340);
  return c.toDataURL('image/jpeg', 0.6).split(',')[1];
}
function startFrames() {
  stopFrames();
  if (params.get('frames') === '0' || !['live', 'simulated'].includes(s.camera.state)) return;
  seq = 0;
  frameTimer = setInterval(() => {
    seq++;
    mockEmit('frames.camera', { seq, width: 640, height: 360, ptsMs: Math.round(performance.now() - t0), jpeg: frame() });
  }, 1000 / FRAME_FPS);
}
function stopFrames() { clearInterval(frameTimer); frameTimer = 0; }

function levelsTick() {
  const t = performance.now() / 1000, ch = {};
  [...s.mix.channels, ...s.mix.takeChannels].forEach((c, i) => {
    const db = -22 + 9 * Math.sin(t * (1.3 + i * 0.37) + i) + 4 * Math.sin(t * 7.1 + i * 2);
    ch[c.id] = c.muted ? { rmsDB: -120, peakDB: -120 } : { rmsDB: Math.max(-90, Math.min(0, db + c.gainDB)), peakDB: Math.min(0, db + 6) };
  });
  mockEmit('record.levels', { channels: ch });
  const lv = Math.max(0, 0.4 + 0.35 * Math.sin(t * 5) + 0.15 * Math.sin(t * 13));
  mockEmit('audio.levels', { levels: [lv, lv], rmsDB: [-20, -20], peakDB: [-10, -10] });
}

function stopClock() { clearInterval(timer); timer = 0; }

function beginRecording() {
  s.phase = 'recording'; s.countBeat = null; s.busy = false;
  const start = s.startTime;
  const begin = performance.now();
  s.audio.recording = true;
  emit();
  stopClock();
  timer = setInterval(() => {
    const pos = start + (performance.now() - begin) / 1000;
    s.position = pos;
    mockEmit('record.position', { seconds: pos, playing: true, phase: 'recording' });
    levelsTick();
  }, 50);
}
function startTake() {
  if (s.blockReason) throw new BridgeError('record-blocked', s.blockReason);
  if (s.phase !== 'idle') throw new BridgeError('busy', 'Ya hay una toma en curso');
  if (!s.countIn) return beginRecording();
  s.phase = 'counting'; s.countBeat = 1; s.busy = true;
  emit();
  let n = 1;
  stopClock();
  timer = setInterval(() => {
    n++;
    if (n > s.beatsPerBar) { stopClock(); beginRecording(); return; }
    s.countBeat = n; emit();
  }, BEAT_S * 1000);
}
function finishTake(save) {
  stopClock();
  s.audio.recording = false;
  mockEmit('record.position', { seconds: s.position, playing: false, phase: 'idle' });
  const part = s.parts.find(p => p.id === s.activePartId);
  const id = uid(200 + Math.floor(Math.random() * 1000));
  const hasVideo = ['live', 'simulated'].includes(s.camera.state);
  if (!save) { s.phase = 'idle'; s.busy = false; return; }
  if (hasVideo) {
    s.phase = 'adjusting';
    s.offset = { takeId: id, isNew: true, videoPath: 'take/video.mp4', audioPath: 'take/processed.wav', songStart: 0.5, fps: 30, frameMs: 1000 / 30,
      cameraId: s.camera.chosenId, cameraName: s.camera.name, initialMs: s.camera.defaultOffsetMs ?? 0, valueMs: s.camera.defaultOffsetMs ?? 0,
      minMs: -500, maxMs: 500, rotation: s.camera.rotation, punches: [] };
  } else { addTake(part, id, null); s.phase = 'idle'; }
  s.busy = false;
}
function addTake(part, id, offsetMs) {
  const t = take(part.takes.length + 1, id, false, { hasVideo: offsetMs != null, videoPath: offsetMs != null ? 'take/video.mp4' : null, videoOffsetMs: offsetMs });
  part.takes.push(t);
  part.status = 'done';
  s.nextTakeNumber = part.takes.length + 1;
}
function part(id) { const p = s.parts.find(x => x.id === id); if (!p) throw new BridgeError('not-found', 'Parte no encontrada'); return p; }
function findTake(id) {
  for (const p of s.parts) { const t = p.takes.find(x => x.id === id); if (t) return { p, t }; }
  throw new BridgeError('not-found', 'Toma no encontrada');
}
function setMixOf(ch, p) {
  const c = [...s.mix.channels, ...s.mix.takeChannels].find(x => x.id === ch);
  if (!c) throw new BridgeError('not-found', 'Canal no encontrado');
  if (p.gainDB != null) c.gainDB = p.gainDB;
  if (!c.forcedMuted) { if (p.mute != null) c.muted = p.mute; if (p.solo != null) c.solo = p.solo; }
  s.mix.anySolo = [...s.mix.channels, ...s.mix.takeChannels].some(x => x.solo);
}

function handle(method, p) {
  if (method === 'record.open') {
    open = true; s = fresh(); t0 = performance.now();
    s.projectId = p.projectId ?? '';
    s.title = 'So payaso';
    if (variant === 'counting') Object.assign(s, { phase: 'counting', countBeat: 3, busy: true });
    if (variant === 'recording') { Object.assign(s, { phase: 'recording', position: 12.4, busy: false }); }
    if (variant === 'adjusting') {
      s.phase = 'adjusting';
      s.offset = { takeId: uid(300), isNew: true, videoPath: 'take/video.mp4', audioPath: 'take/processed.wav', songStart: 0.5, fps: 30, frameMs: 1000 / 30,
        cameraId: 'sim-camera', cameraName: 'iPhone (Continuity Camera)', initialMs: 65, valueMs: 65, minMs: -500, maxMs: 500, rotation: 0, punches: [] };
    }
    startFrames();
    if (variant === 'recording') setTimeout(() => { mockEmit('record.position', { seconds: 12.4, playing: true, phase: 'recording' }); }, 50);
    return view();
  }
  if (method === 'record.close') { open = false; stopClock(); stopFrames(); return {}; }
  if (!open) throw new BridgeError('not-open', 'Grabar no está abierto');
  switch (method) {
    case 'record.state': break;
    case 'record.start': startTake(); break;
    case 'record.stop': if (s.phase === 'recording' || s.phase === 'counting') finishTake(s.phase === 'recording'); break;
    case 'record.cancel':
      if (s.phase === 'adjusting') { s.phase = 'idle'; s.offset = null; } else finishTake(false);
      break;
    case 'record.selectPart': s.activePartId = part(p.partId).id; s.selectedTakeId = null; break;
    case 'record.addPart': {
      if (!p.name) throw new BridgeError('bad-params', 'Falta el nombre');
      const n = { id: uid(50 + s.parts.length), name: p.name, replaces: p.replaces ?? null, isLead: p.replaces === 'lead', status: 'pending', bestTakeId: null, takes: [] };
      s.parts.push(n); s.activePartId = n.id; break;
    }
    case 'record.setStartSection': {
      s.startSectionId = p.sectionId ?? null;
      const sec = SECTIONS.find(x => x.id === s.startSectionId);
      s.startTime = sec ? sec.start : 0; s.plannedStop = sec ? sec.end + 2 * s.barSeconds : null; break;
    }
    case 'record.setCountIn': s.countIn = !!p.on; break;
    case 'record.setPreRoll': s.preRollBars = p.bars; break;
    case 'record.setPunch': {
      const q = s.punch;
      const snapBar = v => (p.free ? v : Math.round(v / s.barSeconds) * s.barSeconds);
      if (p.enabled != null) { q.enabled = p.enabled; if (!p.enabled) { q.in = null; q.out = null; } }
      if (p.in != null) q.in = snapBar(p.in);
      if (p.out != null) q.out = snapBar(p.out);
      if (p.clearIn) q.in = null;
      if (p.clearOut) q.out = null;
      if (q.in != null && q.out != null && q.in >= q.out) [q.in, q.out] = [q.out, q.in];
      q.ready = q.in != null && q.out != null && q.out > q.in; break;
    }
    case 'record.startPunch': findTake(p.takeId); s.selectedTakeId = p.takeId; s.punch.enabled = true; break;
    case 'record.selectTake': s.selectedTakeId = p.takeId ?? null; break;
    case 'record.markBest': { const { p: pt } = findTake(p.takeId); pt.bestTakeId = p.takeId; pt.takes.forEach(t => { t.best = t.id === p.takeId; }); break; }
    case 'record.deleteTake': {
      const { p: pt } = findTake(p.takeId);
      pt.takes = pt.takes.filter(t => t.id !== p.takeId);
      if (pt.bestTakeId === p.takeId) pt.bestTakeId = pt.takes.at(-1)?.id ?? null;
      if (!pt.takes.length) pt.status = 'pending';
      if (s.selectedTakeId === p.takeId) s.selectedTakeId = null;
      break;
    }
    case 'record.setCamera': s.camera.chosenId = p.cameraId ?? null; break;
    case 'record.rotate': s.camera.rotation = (s.camera.rotation + 90) % 360; break;
    case 'record.adjustOffset': {
      const { t } = findTake(p.takeId);
      if (!t.hasVideo) throw new BridgeError('no-video', 'La toma no tiene vídeo');
      s.offset = { takeId: t.id, isNew: false, videoPath: t.videoPath, audioPath: t.audioPath, songStart: t.songStart, fps: 30, frameMs: 1000 / 30, cameraId: 'sim-camera',
        cameraName: s.camera.name ?? 'Cámara', initialMs: t.videoOffsetMs ?? 0, valueMs: t.videoOffsetMs ?? 0, minMs: -500, maxMs: 500, rotation: t.videoRotation ?? 0, punches: [] };
      break;
    }
    case 'record.setOffset': {
      if (!s.offset) throw new BridgeError('no-offset', 'No hay hoja de desfase abierta');
      const v = p.valueMs ?? (s.offset.valueMs + (p.deltaMs ?? 0) + (p.frames ?? 0) * s.offset.frameMs);
      s.offset.valueMs = Math.min(500, Math.max(-500, v)); break;
    }
    case 'record.finishOffset': {
      if (!s.offset) throw new BridgeError('no-offset', 'No hay hoja de desfase abierta');
      if (tv?.offset) { clearInterval(tvTimer); tv = null; }   // W2-O: el núcleo suelta el reproductor de la hoja antes
      const o = s.offset;
      if (p.save) {
        if (o.isNew) addTake(part(s.activePartId), o.takeId, o.valueMs);
        else findTake(o.takeId).t.videoOffsetMs = o.valueMs;
        if (p.makeDefault !== false) s.camera.defaultOffsetMs = o.valueMs;
      }
      s.offset = null; s.phase = 'idle'; break;
    }
    case 'record.setMix': setMixOf(p.channel, p); break;
    case 'record.setMaster': s.mix.masterGainDB = p.gainDB; break;
    case 'record.prepareViewTake': return { allowed: s.phase !== 'recording' && s.phase !== 'counting' };
    default: return undefined;
  }
  emit();
  return view();
}

setMockHandler((method, p) => (method.startsWith('record.') ? handle(method, p) : undefined));

// `takeview.*` (contrato W2-V): reloj simulado sin sonido, a 30 Hz, con `at` en segundos de `performance.now()` + 1000 (el
// núcleo usa otro origen; la página lo estima). `?view=nobacking` simula un tema sin stems.
const TV_DURATION = 8;
let tv = null, tvTimer = 0;
const tvNow = () => performance.now() / 1000;
const tvPos = () => (tv.playing ? Math.min(TV_DURATION, tv.base + tvNow() - tv.since) : tv.base);
const tvEmit = () => mockEmit('takeview.position', { seconds: tvPos(), playing: tv.playing, rate: tv.playing ? 1 : 0, at: tvNow() + 1000, epoch: tv.epoch });
const tvSnap = () => ({ projectId: tv.projectId, takeId: tv.takeId, duration: TV_DURATION, songStart: tv.songStart ?? 0.5,
  hasBacking: !tv.offset && params.get('view') !== 'nobacking',
  backingOn: tv.backingOn, playing: tv.playing, position: tvPos(), epoch: tv.epoch, outputName: 'Salida simulada' });
function tvJump(playing, at = tvPos()) {
  tv.base = at; tv.since = tvNow(); tv.playing = playing; tv.epoch += 1;
  clearInterval(tvTimer);
  if (playing) {
    tvTimer = setInterval(() => {
      if (tvPos() >= TV_DURATION) { tvJump(false, TV_DURATION); return; }
      tvEmit();
    }, 1000 / 30);
  }
  tvEmit();
}
setMockHandler((method, p) => {
  if (!method.startsWith('takeview.')) return undefined;
  if (method === 'takeview.open') {
    clearInterval(tvTimer);
    tv = { projectId: p.projectId, takeId: p.takeId, base: 0, since: tvNow(), playing: false, epoch: 0, backingOn: true };
    tvEmit();
    return tvSnap();
  }
  // W2-O: hoja «Ajustar desfase»: solo la toma de `record` (`s.offset`), sin backing; play vuelve al principio a 1 fotograma del final.
  if (method === 'takeview.openOffset') {
    if (!s?.offset) throw new BridgeError('no-offset', 'No hay ninguna hoja de desfase abierta.');
    clearInterval(tvTimer);
    tv = { projectId: s.projectId, takeId: s.offset.takeId, songStart: s.offset.songStart, offset: true, base: 0, since: tvNow(), playing: false, epoch: 0, backingOn: false };
    tvEmit();
    return tvSnap();
  }
  if (method === 'takeview.close') { clearInterval(tvTimer); tv = null; return {}; }
  if (!tv) throw new BridgeError('not-open', 'No hay ninguna toma abierta en el visor.');
  switch (method) {
    case 'takeview.play': tvJump(true, tvPos() >= TV_DURATION - (tv.offset ? 1 / 30 : 0.1) ? 0 : tvPos()); break;
    case 'takeview.pause': tvJump(false); break;
    case 'takeview.seek': tvJump(tv.playing, Math.min(TV_DURATION, Math.max(0, p.seconds))); break;
    case 'takeview.setBacking': tv.backingOn = !!p.on; break;
    case 'takeview.snapshot': break;
    default: return undefined;
  }
  return tvSnap();
});
