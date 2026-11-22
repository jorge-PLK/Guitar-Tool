import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { icon } from '../icons.js';
import { attachFrames } from '../frames.js';
import { Group, InfoRow, Select, Switch, fail } from './common.js';

/// Medidas de VideoSettingsView del Mac: vista previa de 240 pt de ancho, 16:9.
const PREVIEW_WIDTH = 240;
/// Rango del desfase por defecto (mini-spec Fase 6, «Ajustes · Cámara y vídeo»: ±500 ms); el núcleo manda `choices.offsetRangeMs`.
const OFFSET_RANGE_MS = { min: -500, max: 500 };

const resKey = r => `${r.width}x${r.height}`;
const parseRes = k => { const [width, height] = k.split('x').map(Number); return { width, height }; };

const cameraIcon = html`<svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M4 6h10a2 2 0 0 1 2 2v1.6l4-2.4v9.6l-4-2.4V16a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z"/></svg>`;

const chev = d => html`<svg aria-hidden="true" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d=${d}/></svg>`;

/// Pestaña «Cámara y vídeo» del Mac (VideoSettingsView): Cámara, Sincronía y Exportación por defecto.
export function VideoSettings() {
  const [cams, setCams] = useState(null);
  const [v, setV] = useState(null);
  useEffect(() => {
    const loadCams = () => call('video.cameras').then(setCams).catch(() => setCams({ cameras: [], defaultId: null }));
    loadCams();
    call('video.settings').then(setV).catch(e => { setV(false); fail('No se pudieron leer los ajustes de vídeo', e); });
    return on('video.camerasChanged', () => { loadCams(); call('video.settings').then(setV).catch(() => {}); });
  }, []);
  if (!cams || !v) return null;
  const update = async change => {
    try { setV(await call('video.setSettings', change)); } catch (e) { fail('No se pudo guardar', e); }
  };
  return html`<div class="sstack"><${CameraGroup} cams=${cams} v=${v} update=${update} />
    <${SyncGroup} v=${v} update=${update} /><${ExportGroup} v=${v} update=${update} /></div>`;
}

function CameraGroup({ cams, v, update }) {
  const camera = cams.cameras.find(c => c.id === v.effectiveCameraId) ?? null;
  const cameraOptions = [{ value: '', label: 'Por defecto del sistema' }, ...cams.cameras.map(c => ({ value: c.id, label: c.name }))];
  if (v.cameraUID && !cams.cameras.some(c => c.id === v.cameraUID)) {
    cameraOptions.push({ value: v.cameraUID, label: `${v.cameraName ?? 'Cámara elegida'} · desconectada` });
  }
  const resolutions = camera?.resolutions ?? [];
  const shownRes = v.shown?.resolution ?? v.resolution;
  const fpsChoices = resolutions.find(r => resKey(r) === resKey(shownRes))?.fps ?? [];
  const shownFps = v.shown?.fps ?? v.fps;
  const inUse = camera ? `En uso: ${camera.name}.`
    : v.cameraUID ? 'La cámara elegida está desconectada.'
    : 'No hay ninguna cámara conectada.';
  return html`<${Group} title="Cámara" note=${inUse}>
    <div class="cam-layout">
      <div class="cam-rows">
        <${InfoRow} label="Cámara"><${Select} label="Cámara" value=${v.cameraUID ?? ''} options=${cameraOptions}
          onChange=${x => update({ cameraUID: x === '' ? null : x })} /><//>
        <${InfoRow} label="Resolución"><${Select} label="Resolución" value=${resKey(shownRes)} disabled=${!camera}
          options=${resolutions.map(r => ({ value: resKey(r), label: r.label }))}
          onChange=${x => update({ resolution: parseRes(x) })} /><//>
        <${InfoRow} label="Fotogramas por segundo"><${Select} label="Fotogramas por segundo" value=${shownFps} disabled=${!camera}
          options=${fpsChoices.map(f => ({ value: f.value, label: f.label }))}
          onChange=${x => update({ fps: Number(x) })} /><//>
      </div>
      <${PreviewBox} previewKey=${`${v.cameraUID ?? '-'}|${resKey(shownRes)}|${shownFps}|${cams.cameras.map(c => c.id).join(',')}`} />
    </div>
  <//>`;
}

/// Recuadro de la vista previa (CameraPreviewModel del Mac): `video.preview.start` al entrar en la pestaña o al cambiar de
/// cámara o formato, imagen por `frames.camera` (W2-E2) y `video.preview.stop` al salir. El giro guardado lo aplica la página.
function PreviewBox({ previewKey }) {
  const canvas = useRef(null);
  const [p, setP] = useState(null);
  const [drawn, setDrawn] = useState(false);
  useEffect(() => {
    let alive = true;
    setP(null); setDrawn(false);
    const off = attachFrames(canvas.current, 'camera', { onFrame: () => { if (alive) setDrawn(true); } });
    call('video.preview.start').then(r => { if (alive) setP(r); })
      .catch(e => { if (alive) setP({ state: 'failed', message: `No se pudo abrir la cámara (${e.message ?? e}).`, rotation: 0 }); });
    return () => { alive = false; off(); call('video.preview.stop').catch(() => {}); };
  }, [previewKey]);
  const live = p && (p.state === 'live' || p.state === 'simulated');
  const rot = (((p?.rotation ?? 0) % 360) + 360) % 360;
  // Como RotatingPreviewView del Mac: a 90° y 270° el lienzo se dibuja con los lados cambiados y se gira para llenar el 16:9.
  const swaps = (rot / 90) % 2 === 1;
  const size = swaps ? `width:${(100 * 9) / 16}%;height:${(100 * 16) / 9}%` : 'width:100%;height:100%';
  const glyph = { noCamera: cameraIcon, denied: lockIcon }[p?.state] ?? icon('warning', 18);
  return html`<div class="cam-preview" style=${`width:${PREVIEW_WIDTH}px;position:relative`}>
    <canvas ref=${canvas} aria-label="Vista previa de la cámara"
      style=${`flex:none;${size};object-fit:contain;transform:rotate(${rot}deg);display:${live && drawn ? 'block' : 'none'}`}></canvas>
    ${!p || (live && !drawn) ? spinner : null}
    ${p?.state === 'simulated' && drawn ? html`<span style=${CAPTION_STYLE}>Vista previa simulada</span>` : null}
    ${p && !live ? html`<div class="cam-msg">${glyph}<span>${p.message}</span>
      ${p.state === 'denied' ? html`<button class="btn secondary" onClick=${() => call('video.openCameraPrivacy').catch(e => fail('No se pudieron abrir los ajustes del sistema', e))}>Abrir Ajustes del Sistema</button>` : null}</div>` : null}
  </div>`;
}

/// Rótulo del Mac sobre la imagen simulada (11 pt seminegrita, blanco sobre negro al 60 %, cápsula, 6 pt del borde inferior).
const CAPTION_STYLE = 'position:absolute;bottom:6px;left:50%;transform:translateX(-50%);white-space:nowrap;font-size:11px;'
  + 'font-weight:600;color:#fff;background:rgba(0,0,0,.6);border-radius:999px;padding:3px 8px';

/// `ProgressView` pequeño del Mac mientras arranca la vista previa (sin CSS propio: gira con SMIL).
const spinner = html`<svg aria-label="Abriendo la cámara" width="16" height="16" viewBox="0 0 16 16" style="color:var(--muted)">
  <circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-opacity=".25" stroke-width="2"/>
  <path d="M8 2a6 6 0 0 1 6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
    <animateTransform attributeName="transform" type="rotate" from="0 8 8" to="360 8 8" dur="0.9s" repeatCount="indefinite"/></path></svg>`;

/// «lock.fill» del Mac para el permiso denegado (el botón «Abrir Ajustes del Sistema» llama a `video.openCameraPrivacy`).
const lockIcon = html`<svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M7 10V7a5 5 0 0 1 10 0v3h1a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h1zm2 0h6V7a3 3 0 0 0-6 0v3z"/></svg>`;

function SyncGroup({ v, update }) {
  const id = v.effectiveCameraId;
  const range = v.choices?.offsetRangeMs ?? OFFSET_RANGE_MS;
  const [text, setText] = useState(String(v.offsetMs));
  useEffect(() => setText(String(v.offsetMs)), [v.offsetMs, id]);
  const commit = raw => {
    const n = Math.round(Number(String(raw).replace(',', '.')));
    if (!Number.isFinite(n)) { setText(String(v.offsetMs)); return; }
    const ms = Math.min(Math.max(n, range.min), range.max);
    setText(String(ms));
    if (ms !== v.offsetMs) update({ offset: { ms } });
  };
  const step = d => commit(v.offsetMs + d);
  return html`<${Group} title="Sincronía" note="Se ajusta al terminar cada toma; este es el valor con el que empieza la siguiente.">
    <${InfoRow} label="Desfase por defecto de esta cámara">
      <input class="numfield" type="text" inputmode="numeric" aria-label="Desfase" disabled=${id == null} value=${text}
        onInput=${e => setText(e.currentTarget.value)} onBlur=${e => commit(e.currentTarget.value)}
        onKeyDown=${e => { if (e.key === 'Enter') commit(e.currentTarget.value); }} />
      <span class="muted">ms</span>
      <span class="stepper"><button aria-label="Aumentar desfase" disabled=${id == null} onClick=${() => step(1)}>${chev('M6 15l6-6 6 6')}</button>
        <button aria-label="Reducir desfase" disabled=${id == null} onClick=${() => step(-1)}>${chev('M6 9l6 6 6-6')}</button></span><//>
  <//>`;
}

/// Exportación por defecto. El Mac enseña aquí un selector HEVC / H.264; en Windows el único códec es H.264 (decisión de
/// Jorge, 21/11/2026) y al ser única opción no se muestra: solo queda la resolución.
function ExportGroup({ v, update }) {
  const e = v.export;
  const resolutions = v.choices?.exportResolutions ?? [];
  return html`<${Group} title="Exportación por defecto" note="Se puede cambiar en cada montaje.">
    <${InfoRow} label="Formato de vídeo"><${Select} label="Resolución de exportación" value=${resKey(e.resolution)}
      options=${resolutions.map(r => ({ value: resKey(r), label: r.label }))}
      onChange=${x => update({ export: { resolution: parseRes(x) } })} /><//>
    <${InfoRow} label="Volumen"><b class="val">normalizado a −14 LUFS</b><//>
    <${InfoRow} label="Rótulo con el título del tema"><${Switch} label="Rótulo con el título del tema" on=${e.titleOverlay}
      onChange=${on => update({ export: { titleOverlay: on } })} /><//>
    <${InfoRow} label="WAV de cada pista"><${Switch} label="WAV de cada pista" on=${e.exportStemWAVs}
      onChange=${on => update({ export: { exportStemWAVs: on } })} /><//>
  <//>`;
}
