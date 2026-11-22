// Simulador de settings.*, library.usage, models.*, tools.* y video.* para `?mock=1` (sin núcleo).
// Variantes con `?settings=`: previewdenied | previewfailed (vista previa de la cámara) | nocamera | disconnected (cámara elegida ausente) | updated (yt-dlp actualizado) | notinstalled | downloading | failed.
import { setMockHandler, mockEmit, BridgeError } from '../bridge.js';

const variant = new URLSearchParams(location.search).get('settings');
const wait = ms => new Promise(r => setTimeout(r, ms));
const clone = o => JSON.parse(JSON.stringify(o));
const res = (width, height, label) => ({ width, height, label });
const R720 = res(1280, 720, '720p'), R1080 = res(1920, 1080, '1080p'), R4K = res(3840, 2160, '4K');
const fps = (...v) => v.map(value => ({ value, label: `${value} fps` }));

const CAMERAS = variant === 'nocamera' ? [] : [
  { id: 'sim-cam', name: 'Cámara simulada', kind: 'simulated', isDefault: true,
    resolutions: [{ ...R720, fps: fps(24, 25, 30) }, { ...R1080, fps: fps(24, 25, 30) }] },
  { id: 'sim-iphone', name: 'iPhone (Continuity Camera)', kind: 'continuity', isDefault: false,
    resolutions: [{ ...R720, fps: fps(24, 25, 30, 50, 60) }, { ...R1080, fps: fps(24, 25, 30, 50, 60) }, { ...R4K, fps: fps(24, 25, 30) }] },
];
const chosen = variant === 'nocamera' ? null : variant === 'disconnected' ? 'sim-gone' : 'sim-iphone';
let previewTimer = 0, previewSeq = 0;
function previewFrame() {
  const c = document.createElement('canvas');
  c.width = 640; c.height = 360;
  const g = c.getContext('2d'), t = performance.now() / 1000;
  const grad = g.createLinearGradient(0, 0, 640, 360);
  grad.addColorStop(0, '#3A4A5C'); grad.addColorStop(1, '#6B4A3A');
  g.fillStyle = grad; g.fillRect(0, 0, 640, 360);
  g.fillStyle = 'rgba(255,255,255,.85)';
  g.beginPath(); g.arc(320 + 150 * Math.sin(t * 1.5), 180 + 60 * Math.cos(t * 2.1), 38, 0, 7); g.fill();
  return c.toDataURL('image/jpeg', 0.6).split(',')[1];
}
const stopPreview = () => { clearInterval(previewTimer); previewTimer = 0; };
const video = {
  cameraUID: chosen, resolution: R1080, fps: 30, offsetsMs: chosen && variant !== 'disconnected' ? { 'sim-iphone': 65 } : {}, rotations: {},
  export: { codec: 'h264', resolution: R1080, titleOverlay: true, exportStemWAVs: true, normalizeLUFS: -14 },
};

function videoSettings() {
  const effective = variant === 'nocamera' ? null : (video.cameraUID ?? 'sim-cam');
  const cam = CAMERAS.find(c => c.id === effective) ?? null;
  const connected = video.cameraUID == null || CAMERAS.some(c => c.id === video.cameraUID);
  let shown = null;
  if (cam) {
    const r = cam.resolutions.find(x => x.width === video.resolution.width) ?? cam.resolutions[cam.resolutions.length - 1];
    const f = r.fps.find(x => x.value === video.fps) ?? r.fps[r.fps.length - 1];
    shown = { resolution: { width: r.width, height: r.height, label: r.label }, fps: f.value, fpsLabel: f.label };
  }
  return {
    cameraUID: video.cameraUID, cameraConnected: connected, cameraName: cam?.name ?? (connected ? null : 'iPhone (Continuity Camera)'), effectiveCameraId: effective,
    noCamera: cam == null && connected, resolution: video.resolution, fps: video.fps, fpsLabel: `${video.fps} fps`, shown,
    offsetMs: video.offsetsMs[effective] ?? 0, rotation: video.rotations[effective] ?? 0, offsetsMs: video.offsetsMs, rotations: video.rotations,
    export: video.export,
    choices: { codecs: ['h264'], exportResolutions: [R720, R1080, R4K], rotations: [0, 90, 180, 270], offsetRangeMs: { min: -500, max: 500 } },
  };
}

const MODEL = { id: 'separatorBSRoformerSW', name: 'Separación de stems', state: 'installed', fraction: null, bytes: 727_000_000,
  archiveBytes: 604_000_000, message: null, source: 'store' };
if (variant === 'notinstalled') Object.assign(MODEL, { state: 'notInstalled', bytes: null });
if (variant === 'downloading') Object.assign(MODEL, { state: 'downloading', fraction: 0.42, bytes: null });
if (variant === 'failed') Object.assign(MODEL, { state: 'failed', bytes: null, message: 'Sin conexión' });
const modelList = () => ({ models: [clone(MODEL)], modelsBytes: MODEL.bytes ?? 0 });

const tools = { ytDlpVersion: '2026.10.26', ytDlpOrigin: variant === 'updated' ? 'updated' : 'embedded', denoVersion: '2.1.4', ffmpegVersion: '7.1' };
let projectsFolder = 'C:\\Users\\jorge\\ToneForge';
let restart = false;

setMockHandler((method, p) => {   // síncrono: devuelve undefined si no es suyo (si fuera async, tragaría todo)
  switch (method) {
    case 'settings.get': return { projectsFolder, activeProjectsFolder: restart ? 'C:\\Users\\jorge\\ToneForge' : projectsFolder, video: videoSettings() };
    case 'library.usage': return { totalBytes: 3_412_000_000, regenerableBytes: 2_100_000_000, projects: [] };
    case 'library.cleanupInfo': if (p.id) return undefined; return { bytes: 2_100_000_000 };
    case 'library.cleanup': if (p.id) return undefined; return wait(400).then(() => ({ cleaned: true, bytes: 2_100_000_000 }));
    case 'host.chooseFolder': return { path: 'D:\\Música\\ToneForge' };
    case 'library.relocate': projectsFolder = p.path; return { path: p.path, mediaRemapped: true };
    case 'host.pickProjectsFolder': projectsFolder = 'D:\\Música\\ToneForge'; restart = true; return { path: projectsFolder, restartRequired: true };
    case 'models.list': return modelList();
    case 'models.download': {
      Object.assign(MODEL, { state: 'downloading', fraction: 0 });
      (async () => {
        for (let f = 0.05; f <= 1; f += 0.05) { await wait(250); MODEL.fraction = f; mockEmit('models.progress', { id: MODEL.id, fraction: f }); }
        Object.assign(MODEL, { state: 'installed', fraction: null, bytes: 727_000_000 });
        mockEmit('models.changed', { ...modelList(), error: null });
      })();
      return { started: true };
    }
    case 'models.delete': Object.assign(MODEL, { state: 'notInstalled', bytes: null }); return modelList();
    case 'tools.info': return { ...tools };
    case 'tools.updateYtDlp': return wait(1200).then(() => { Object.assign(tools, { ytDlpVersion: '2026.11.01', ytDlpOrigin: 'updated' }); return { version: tools.ytDlpVersion, origin: 'updated', alreadyLatest: false }; });
    case 'tools.revertYtDlp': Object.assign(tools, { ytDlpVersion: '2026.10.26', ytDlpOrigin: 'embedded' }); return { reverted: true };
    case 'video.cameras': return { cameras: clone(CAMERAS), defaultId: CAMERAS[0]?.id ?? null };
    case 'video.settings': return videoSettings();
    case 'video.preview.start': {
      stopPreview();
      const v = videoSettings(), cam = CAMERAS.find(c => c.id === v.effectiveCameraId);
      const base = { rotation: v.rotation, fromRecord: false };
      if (!cam) return { state: 'noCamera', message: v.cameraUID ? 'La cámara elegida está desconectada.' : 'No hay ninguna cámara conectada.', ...base };
      if (variant === 'previewdenied') return { state: 'denied', message: 'ToneForge no tiene permiso para usar la cámara.', cameraId: cam.id, cameraName: cam.name, ...base };
      if (variant === 'previewfailed') return { state: 'failed', message: 'No se pudo abrir la cámara (simulado).', cameraId: cam.id, cameraName: cam.name, ...base };
      previewSeq = 0;
      if (new URLSearchParams(location.search).get('frames') !== '0') {
        previewTimer = setInterval(() => mockEmit('frames.camera', { seq: ++previewSeq, width: 640, height: 360, ptsMs: Math.round(performance.now()), jpeg: previewFrame() }), 100);
      }
      return { state: 'simulated', cameraId: cam.id, cameraName: cam.name, width: v.shown?.resolution.width ?? 1920, height: v.shown?.resolution.height ?? 1080,
        fps: v.shown?.fps ?? 30, ...base };
    }
    case 'video.preview.stop': stopPreview(); return { state: 'idle', rotation: 0, fromRecord: false };
    case 'video.openCameraPrivacy': return { opened: true };
    case 'video.setSettings': {
      if ('cameraUID' in p) video.cameraUID = p.cameraUID;
      if (p.resolution) video.resolution = [R720, R1080, R4K].find(r => r.width === p.resolution.width) ?? video.resolution;
      if (p.fps) video.fps = p.fps;
      if (p.offset) {
        const id = videoSettings().effectiveCameraId;
        if (!id) throw new BridgeError('bad-params', 'Sin cámara');
        video.offsetsMs[id] = Math.max(-500, Math.min(500, Math.round(p.offset.ms)));
      }
      if (p.export) {
        const { resolution, ...rest } = p.export;
        Object.assign(video.export, rest);
        if (resolution) video.export.resolution = [R720, R1080, R4K].find(r => r.width === resolution.width) ?? video.export.resolution;
      }
      return videoSettings();
    }
  }
  return undefined;
});
