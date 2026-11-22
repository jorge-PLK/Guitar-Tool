// Hoja «Ajustar desfase» (OffsetSheet del Mac): vista previa del vídeo con la guitarra grabada, desfase en ms (±500) con
// ±1 fotograma y ±1 ms, y «Guardar como desfase por defecto de esta cámara».
// W2-O: la toma suena en el núcleo (`takeview.openOffset`, salida del perfil) y el `<video>` sin sonido la sigue
// (CoreTakeSync). El desfase se aplica solo aquí, al objetivo del vídeo: moverlo no toca el audio.
import { useRef, useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { Modal } from '../ui.js';
import { snap, setOffset, finishOffset } from './store.js';
import { RIcon, fmtMs } from './bits.js';
import { TakeScreen } from './take-screen.js';
import { CoreTakeSync } from './take-sync.js';

/// Contrato: ±500 ms (`offset.minMs/maxMs` del núcleo mandan si vienen).
const RANGE_MS = 500;

/// Reproductor de la hoja: audio de la toma en el núcleo y vídeo con el desfase `offsetMs` en vivo.
/// `opts`: {videoPath, punches, offsetMs}. Devuelve lo mismo que `useCoreTakePlayer` (refs, estado, acciones).
function useOffsetPlayer({ videoPath, punches, offsetMs }) {
  const video = useRef(null);
  const sync = useRef(null);
  const [st, setSt] = useState({ t: 0, d: 0, playing: false, ready: false });
  const [error, setError] = useState(null);
  const [videoError, setVideoError] = useState(null);
  const fail = e => setError(e?.message || String(e));
  const apply = s => setSt(p => ({ ...p, d: s.duration, playing: s.playing }));
  useEffect(() => {
    let alive = true;
    let early = null;   // posición que llega antes de la respuesta de `openOffset`
    const off = on('takeview.position', ev => {
      const now = performance.now() / 1000;
      if (sync.current) sync.current.push(ev, now); else early = [ev, now];
      setSt(p => (p.playing === ev.playing ? p : { ...p, playing: ev.playing }));
    });
    call('takeview.openOffset').then(s => {
      if (!alive) return;
      const ts = new CoreTakeSync(video.current, { songStart: s.songStart, offsetMs: offsetMs ?? 0, basePath: videoPath, punches: punches ?? [],
        duration: s.duration, onVideoError: setVideoError, onTick: t => setSt(p => (Math.abs(p.t - t) < 0.01 ? p : { ...p, t })) });
      sync.current = ts;
      if (early) ts.push(...early);
      apply(s);
      setSt(p => ({ ...p, ready: true, t: s.position }));
      if (s.audioError) setError(s.audioError);
    }, e => { if (alive) setError(e?.code === 'not-found' ? 'Esta toma no tiene audio que reproducir.' : `No se pudo abrir la toma (${e?.message || e}).`); });
    return () => {
      alive = false;
      off();
      sync.current?.destroy();
      sync.current = null;
      call('takeview.close').catch(() => {});
    };
  }, [videoPath]);
  useEffect(() => { sync.current?.setOffset(offsetMs ?? 0); }, [offsetMs]);
  return {
    video, error, videoError, ...st,
    toggle: () => call(st.playing ? 'takeview.pause' : 'takeview.play').then(s => { setError(null); apply(s); }, fail),
    restart: () => call('takeview.seek', { seconds: 0 }).then(apply, fail),
    hasVideo: !!(videoPath || (punches ?? []).some(p => p.videoPath)),
  };
}

export function OffsetSheet() {
  const o = snap.value.offset;
  const lo = o.minMs ?? -RANGE_MS, hi = o.maxMs ?? RANGE_MS;
  const frameMs = o.frameMs ?? 1000 / Math.max(o.fps ?? 30, 1);
  const [ms, setMs] = useState(Math.round(o.valueMs ?? o.initialMs ?? 0));
  const [text, setText] = useState(null);
  const [makeDefault, setMakeDefault] = useState(true);
  const player = useOffsetPlayer({ videoPath: o.videoPath, punches: o.punches, offsetMs: ms });
  const put = v => {
    const c = Math.min(Math.max(v, lo), hi);
    setText(null);
    if (c === ms) return;
    setMs(c);
    setOffset({ valueMs: c });
  };
  const commitText = () => {
    if (text == null) return;
    const v = parseFloat(text.replace(',', '.'));
    if (Number.isFinite(v)) put(v); else setText(null);
  };
  const finish = save => finishOffset(save, save ? makeDefault : false);
  const step = (label, d) => html`<button class="btn secondary rec-b34" onClick=${() => put(ms + d)}>${label}</button>`;
  return html`<${Modal} title="Ajustar desfase" width=${720} autofocus=".rec-ms" labelledBy="rec-off-title">
    <div class="rec-sheet rec-offset">
      <p class="rec-offset-help">Dale al play y mueve el desfase hasta que imagen y sonido coincidan (un golpe seco en las cuerdas ayuda). Positivo = la imagen llega tarde.</p>
      <${TakeScreen} player=${player} rotation=${o.rotation ?? 0}>
        ${player.error ? html`<div class="rec-tmsg danger">${player.error}</div>`
          : !player.ready ? html`<span class="spinner" aria-hidden="true"></span>` : null}</${TakeScreen}>
      <div class="rec-row">
        <button class="btn secondary rec-b34" disabled=${!player.ready} onClick=${player.toggle}>${RIcon.playpause(15)}Reproducir / pausa</button>
        <button class="btn secondary rec-b34" disabled=${!player.ready} onClick=${player.restart}>${RIcon.begin(15)}Al principio</button></div>
      <div class="rec-row rec-steps">
        ${step('−1 fotograma', -frameMs)}${step('−1 ms', -1)}
        <span class="rec-ms-box"><input class="rec-ms" type="text" inputmode="decimal" aria-label="Desfase en milisegundos"
          value=${text ?? fmtMs(ms)} onInput=${e => setText(e.currentTarget.value)} onBlur=${commitText}
          onKeyDown=${e => { if (e.key === 'Enter') commitText(); }} /><span class="muted">ms</span></span>
        ${step('+1 ms', 1)}${step('+1 fotograma', frameMs)}
        <span class="grow"></span><span class="rec-frame-note">Fotograma = ${fmtMs(frameMs)} ms</span></div>
      <label class="check rec-check"><input type="checkbox" checked=${makeDefault} onChange=${e => setMakeDefault(e.currentTarget.checked)} />
        Guardar como desfase por defecto de esta cámara (${o.cameraName ?? ''})</label>
      <div class="modal-actions">
        <button class="btn secondary" onClick=${() => finish(false)}>${o.isNew ? 'Descartar toma' : 'Cancelar'}</button>
        <button class="btn primary" onClick=${() => finish(true)}>${o.isNew ? 'Guardar toma' : 'Guardar'}</button></div></div></${Modal}>`;
}
