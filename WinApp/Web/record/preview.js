// Vista previa de la cámara (RecordPreview del Mac): vídeo en 16:9 lo más grande posible, píldora de la toma arriba a la izquierda,
// cámara y «Rotar» a la derecha (segunda fila si no caben) y cuenta atrás abajo.
import { useRef, useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { attachFrames } from '../frames.js';
import { snap, rotateCamera, takesOf } from './store.js';
import { RIcon } from './bits.js';
import { fitRotated } from './take-sync.js';

/// Lienzo del canal `frames.camera` con el giro del perfil aplicado (grados horarios) y ajustado a la caja sin recortar.
function CameraCanvas({ rotation, onFirstFrame }) {
  const box = useRef(null), cv = useRef(null);
  const dims = useRef({ w: 16, h: 9 });
  const fit = () => {
    const b = box.current, c = cv.current;
    if (!b || !c) return;
    const r = fitRotated(b.clientWidth, b.clientHeight, dims.current.w, dims.current.h, rotation);
    c.style.width = `${r.width}px`; c.style.height = `${r.height}px`;
    c.style.transform = `translate(-50%, -50%) rotate(${rotation}deg)`;
  };
  useEffect(() => {
    let first = true;
    const off = attachFrames(cv.current, 'camera', { onFrame: f => {
      dims.current = { w: f.width, h: f.height };
      fit();
      if (first) { first = false; onFirstFrame(); }
    } });
    return off;
  }, []);
  useEffect(() => {
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(box.current);
    return () => ro.disconnect();
  }, [rotation]);
  return html`<div class="rec-cam" ref=${box}><canvas ref=${cv} class="rec-cam-canvas" aria-label="Vista previa de la cámara"></canvas></div>`;
}

export function Preview() {
  const s = snap.value;
  const cam = s.camera ?? {};
  const [gotFrame, setGotFrame] = useState(false);
  const hasLive = cam.state === 'live' || cam.state === 'simulated';
  useEffect(() => { if (!hasLive) setGotFrame(false); }, [hasLive]);
  const recording = s.phase !== 'idle' && s.phase !== 'adjusting';
  const part = s.parts.find(p => p.id === s.activePartId);
  const rot = cam.rotation ?? 0;
  const noVideo = cam.state === 'none' || cam.state === 'denied' || cam.state === 'failed';
  const placeholder = noVideo ? 'Sin vídeo: se grabará solo el audio'
    : cam.state === 'simulated' ? `Vista previa de la cámara · ${cam.name ?? 'simulada'} (simulada)` : null;
  const next = s.nextTakeNumber ?? (part ? takesOf(part).length + 1 : 1);
  return html`<div class="rec-preview-wrap"><div class="rec-preview">
    ${hasLive ? html`<${CameraCanvas} rotation=${rot} onFirstFrame=${() => setGotFrame(true)} />` : null}
    ${cam.state === 'idle' ? html`<div class="rec-ph"><span class="spinner" aria-hidden="true"></span></div>`
      : (!hasLive || !gotFrame) && placeholder ? html`<div class="rec-ph">${RIcon.video(40)}<span>${placeholder}</span></div>` : null}
    <div class="rec-overlay">
      <div class="rec-pills">
        <span class="rec-pill rec-pill-take"><i class=${'rec-dot' + (recording ? ' on' : '')}></i><span class="rec-pill-text">${recording ? 'REC · ' : ''}Toma ${next} · ${part?.name ?? ''}</span></span>
        ${cam.label ? html`<span class="rec-cam-pills"><span class="rec-pill">${cam.label}</span>
          <button class=${'rec-pill rec-rotate' + (rot ? ' on' : '')} disabled=${s.phase !== 'idle'} onClick=${() => rotateCamera()}
            title="Gira la imagen de esta cámara 90° en sentido horario (no se recodifica; se aplica al ver y montar)"
            aria-label=${'Rotar cámara, ahora ' + rot + ' grados'}>${RIcon.rotate(17)}<span>${rot === 0 ? 'Rotar' : `Rotar · ${rot}°`}</span></button></span>` : null}
      </div>
      ${s.phase === 'counting' && s.countBeat ? html`<div class="rec-count" aria-live="assertive">${s.countBeat}</div>` : null}
    </div></div></div>`;
}
