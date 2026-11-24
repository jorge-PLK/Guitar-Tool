// Pantalla 16:9 de una toma (vídeo girado y ajustado a la caja) y su reproductor sincronizado, para la hoja «Ajustar desfase»
// y el visor «Ver toma» (`useCoreTakePlayer`: audio en el núcleo, W2-V);
// imagen = `<video>` sin sonido (ver take-sync.js).
import { useRef, useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { videoNoteText } from '../state.js';
import { CoreTakeSync, fitRotated } from './take-sync.js';

/// «Ver toma» (W2-V): la toma y el backing suenan en el núcleo (`takeview.*`); el `<video>` sigue a `takeview.position`.
/// `opts`: {projectId, takeId, videoPath, punches, offsetMs}. Devuelve refs, estado y acciones, más el backing.
export function useCoreTakePlayer({ projectId, takeId, videoPath, punches, offsetMs }) {
  const video = useRef(null);
  const sync = useRef(null);
  const [st, setSt] = useState({ t: 0, d: 0, playing: false, ready: false, hasBacking: false, backingOn: true });
  const [error, setError] = useState(null);
  const [videoError, setVideoError] = useState(null);
  const [videoNote, setVideoNote] = useState(null);
  const fail = e => setError(e?.message || String(e));
  const apply = snap => setSt(p => ({ ...p, d: snap.duration, playing: snap.playing, hasBacking: snap.hasBacking, backingOn: snap.backingOn }));
  useEffect(() => {
    let alive = true;
    let early = null;   // posición que llega antes de la respuesta de `open`
    let lateVideo = null;   // `takeview.video` que llega antes de la respuesta de `open`
    let shown = null;   // aviso de vídeo que se enseña ahora (null = `<video>`)
    let mine = null;   // `takeId` de la instantánea (mismo formato que el del evento)
    const off = on('takeview.position', ev => {
      const now = performance.now() / 1000;
      if (sync.current) sync.current.push(ev, now); else early = [ev, now];
      setSt(p => (p.playing === ev.playing ? p : { ...p, playing: ev.playing }));
    });
    // Fase 7c (opción b'): el vídeo se convirtió con el visor abierto. Solo se recarga el `<video>` (sin cerrar el visor ni
    // tocar el audio, que sigue en el núcleo); con otro aviso (fallo), se cambia el texto.
    const showVideo = note => {
      if (shown && !note) { setVideoError(null); sync.current?.setVideo(videoPath, punches ?? []); }
      shown = note;
      setVideoNote(note);
    };
    const offVideo = on('takeview.video', ev => {
      if (!sync.current) { lateVideo = ev; return; }
      if (ev.takeId === mine) showVideo(ev.video ?? null);
    });
    call('takeview.open', { projectId, takeId }).then(snap => {
      if (!alive) return;
      mine = snap.takeId;
      // Vídeo que aún no se puede ver (convirtiéndose): suena el audio y se muestra el aviso, sin `<video>`. Un
      // `takeview.video` llegado antes de esta respuesta solo cuenta si dice que ya se puede ver (es lo único definitivo).
      const note = lateVideo && lateVideo.takeId === mine && !lateVideo.video ? null : (snap.video ?? null);
      shown = note;
      setVideoNote(note);
      const ts = new CoreTakeSync(video.current, { songStart: snap.songStart, offsetMs: offsetMs ?? 0, basePath: note ? null : videoPath,
        punches: note ? [] : (punches ?? []),
        duration: snap.duration, onVideoError: setVideoError, onTick: t => setSt(p => (Math.abs(p.t - t) < 0.01 ? p : { ...p, t })) });
      sync.current = ts;
      if (early) ts.push(...early);
      apply(snap);
      setSt(p => ({ ...p, ready: true, t: snap.position }));
      if (snap.audioError) setError(snap.audioError);
    }, e => { if (alive) setError(e?.code === 'not-found' ? 'Esta toma no tiene audio que reproducir.' : (e?.message || String(e))); });
    return () => {
      alive = false;
      off();
      offVideo();
      sync.current?.destroy();
      sync.current = null;
      call('takeview.close').catch(() => {});
    };
  }, [projectId, takeId, videoPath]);
  return {
    video, error, videoError, ...st,
    toggle: () => call(st.playing ? 'takeview.pause' : 'takeview.play').then(s => { setError(null); apply(s); }, fail),
    seek: t => { setSt(p => ({ ...p, t })); call('takeview.seek', { seconds: t }).then(apply, fail); },
    toggleBacking: () => call('takeview.setBacking', { on: !st.backingOn }).then(apply, fail),
    hasVideo: !videoNote && !!(videoPath || (punches ?? []).some(p => p.videoPath)),
    videoNote,
  };
}

/// Caja 16:9 negra con el vídeo girado `rotation` grados (horarios) sin recortar. `children`: mensajes encima.
export function TakeScreen({ player, rotation = 0, children }) {
  const box = useRef(null);
  const [fit, setFit] = useState(null);
  useEffect(() => {
    const v = player.video.current;
    const run = () => {
      if (!v || !v.videoWidth || !box.current) return;
      setFit(fitRotated(box.current.clientWidth, box.current.clientHeight, v.videoWidth, v.videoHeight, rotation));
    };
    run();
    v.addEventListener('loadedmetadata', run);
    const ro = new ResizeObserver(run);
    ro.observe(box.current);
    return () => { v.removeEventListener('loadedmetadata', run); ro.disconnect(); };
  }, [rotation]);
  const style = fit ? `width:${fit.width}px;height:${fit.height}px;transform:translate(-50%,-50%) rotate(${rotation}deg)` : 'display:none';
  return html`<div class="rec-tscreen" ref=${box}>
    <video ref=${player.video} class="rec-tvideo" style=${player.hasVideo && !player.videoError ? style : 'display:none'} playsinline muted></video>
    ${player.videoError ? html`<div class="rec-tmsg danger">${player.videoError}</div>`
      : player.videoNote ? html`<div class="rec-tmsg muted" role="status">${videoNoteText(player.videoNote)}</div>${player.error ? children : null}`
      : children}</div>`;
}
