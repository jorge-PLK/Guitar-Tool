// Hoja «Encuadre» de una toma (MontageFramingSheet): un fotograma con la caja de la guitarra, «Seguir la guitarra»,
// ajuste manual (fijo: mover y escalar la caja; seguir: zoom y desplazamiento), «Restablecer», «Reanalizar», «Hecho».
import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { Modal } from '../ui.js';
import { mediaUrl } from '../state.js';
import { lanes, sheetTake, framingOf, setFraming, resetFraming, reanalyze, framingFrame, snap } from './store.js';
import {
  HANDLE_RADIUS, MIN_BOX_SIDE, ZOOM_RANGE, OFFSET_RANGE, FRAME_DEBOUNCE_MS, clamp, fmtDur, fmtPercent,
} from './model.js';

/// Cadencia del envío del ajuste mientras se arrastra (el núcleo guarda y, en seguir, rehace el recorte).
const SEND_MS = 100;

/// Mueve la caja sin salirse del fotograma (MontageFramingSheet.moved).
export const moved = (b, dx, dy) => ({ x: clamp(b.x + dx, 0, 1 - b.width), y: clamp(b.y + dy, 0, 1 - b.height), width: b.width, height: b.height });
/// Escala la caja desde su esquina superior izquierda conservando su proporción en píxeles (MontageFramingSheet.resized).
export function resized(b, dx, aspect) {
  const boxAspect = (b.width * aspect) / Math.max(b.height, 1e-6);
  const maxW = Math.min(1 - b.x, ((1 - b.y) * boxAspect) / aspect);
  const w = clamp(b.width + dx, MIN_BOX_SIDE, Math.max(MIN_BOX_SIDE, maxW));
  return { x: b.x, y: b.y, width: w, height: (w * aspect) / boxAspect };
}

function statusLine(f) {
  switch (f.status) {
    case 'analyzing': return ['Analizando la guitarra… ' + fmtPercent(f.progress), 'accent-text'];
    case 'ready': return f.detected === 0 ? ['Sin detección: se usa el fotograma entero, centrado. Puedes colocar la caja a mano.', 'accent-text']
      : [`Guitarra detectada en ${f.detected} de ${f.samples} muestras.`, 'muted'];
    case 'failed': return [`No se pudo analizar la toma (${f.error ?? ''}).`, 'danger-text'];
    default: return ['En cola para analizar la guitarra…', 'muted'];
  }
}

function SliderRow({ label, value, range, format, onChange }) {
  return html`<div class="mt-srow"><span class="l">${label}</span>
    <input type="range" class="mt-slider" min=${range[0]} max=${range[1]} step="any" value=${value} aria-label=${label}
      style=${`--f:${((value - range[0]) / (range[1] - range[0])) * 100}%`} onInput=${e => onChange(+e.currentTarget.value)} />
    <span class="v">${format(value)}</span></div>`;
}

export function FramingSheet() {
  const takeId = sheetTake.value;
  const lane = lanes.value.find(l => l.takeId === takeId);
  const f = framingOf(takeId);
  const [time, setTime] = useState(() => { const p = lane?.presence?.[0] ?? lane?.take ?? { start: 0, end: 0 }; return (p.start + p.end) / 2; });
  const [frame, setFrame] = useState(null);
  // Fase 7c: vídeo de la toma convirtiéndose a H.264 (o con la conversión fallida): el motivo en lugar del fotograma.
  // Al acabar la conversión el encuadre se reanaliza; el cambio de `f.status` vuelve a pedir el fotograma.
  const [frameNote, setFrameNote] = useState(null);
  const [dragBox, setDragBox] = useState(null);
  const area = useRef(null);
  const sent = useRef({ at: 0, timer: 0 });
  const close = () => { sheetTake.value = null; };

  const fixedManual = f.mode === 'fixed' ? f.manualBox : null;
  const rotation = lane?.rotation ?? 0;
  useEffect(() => {
    let alive = true;
    const t = setTimeout(async () => {
      try { const r = await framingFrame(takeId, time); if (alive) { setFrame(r); setFrameNote(null); } } catch (e) {
        if (alive) { setFrame(null); setFrameNote(String(e?.code ?? '').startsWith('video-') ? e.message : null); }
      }
    }, FRAME_DEBOUNCE_MS);
    return () => { alive = false; clearTimeout(t); };
  }, [takeId, time, f.mode, f.followZoom, f.followOffset?.x, f.followOffset?.y, rotation, f.status, f.manualBox == null]);

  const aspect = frame ? frame.width / frame.height : 16 / 9;
  const box = dragBox ?? fixedManual ?? frame?.box ?? { x: 0, y: 0, width: 1, height: 1 };
  const send = patch => {
    const s = sent.current, now = performance.now();
    clearTimeout(s.timer);
    const go = () => { s.at = performance.now(); setFraming(takeId, patch); };
    if (now - s.at >= SEND_MS) go(); else s.timer = setTimeout(go, SEND_MS - (now - s.at));
  };

  const pdown = e => {
    if (e.button !== 0 || !frame) return;
    const r = area.current.getBoundingClientRect();
    const sx = e.clientX, sy = e.clientY;
    area.current.setPointerCapture?.(e.pointerId);
    let base, resizes = false, offBase;
    if (f.mode === 'fixed') {
      base = box;
      const cx = (box.x + box.width) * r.width + r.left, cy = (box.y + box.height) * r.height + r.top;
      resizes = Math.hypot(sx - cx, sy - cy) <= HANDLE_RADIUS;
    } else offBase = { ...(f.followOffset ?? { x: 0, y: 0 }) };
    const mv = ev => {
      const dx = (ev.clientX - sx) / r.width, dy = (ev.clientY - sy) / r.height;
      if (f.mode === 'fixed') {
        const b = resizes ? resized(base, dx, aspect) : moved(base, dx, dy);
        setDragBox(b);
        send({ mode: 'fixed', manualBox: b });
      } else send({ followOffset: { x: clamp(offBase.x + dx, ...OFFSET_RANGE), y: clamp(offBase.y + dy, ...OFFSET_RANGE) } });
    };
    const end = () => {
      window.removeEventListener('pointermove', mv);
      window.removeEventListener('pointerup', end);
      window.removeEventListener('pointercancel', end);
      setTimeout(() => setDragBox(null), SEND_MS * 2);
    };
    window.addEventListener('pointermove', mv);
    window.addEventListener('pointerup', end);
    window.addEventListener('pointercancel', end);
  };

  if (!lane) return null;
  const [text, tone] = statusLine(f);
  const src = frame ? `${mediaUrl(frame.path)}?v=${frame.version}` : null;
  const pct = v => `${v * 100}%`;
  const analyzing = f.status === 'analyzing';
  return html`<${Modal} title=${html`<span class="mt-sheet-title"><span>Encuadre · ${lane.partName}</span>
      <button class=${'switch' + (f.mode === 'follow' ? ' on' : '')} role="switch" aria-checked=${f.mode === 'follow'} aria-label="Seguir la guitarra"
        onClick=${() => setFraming(takeId, { mode: f.mode === 'follow' ? 'fixed' : 'follow' })}><span class="knob"></span></button></span>`}
      width=${760} onClose=${close}>
    <div class="mt-sheet-body">
      <p class=${'small ' + tone}>${text}</p>
      <div class="mt-frame" ref=${area} style=${`aspect-ratio:${aspect};--ar:${aspect}`} onPointerDown=${pdown}>
        ${src ? html`<img src=${src} alt="Fotograma de la toma" draggable="false" />` : html`<span class="none muted" role="status">${frameNote ?? 'Sin imagen en este instante'}</span>`}
        <i class="shade" style=${`top:0;left:0;right:0;height:${pct(box.y)}`}></i>
        <i class="shade" style=${`top:${pct(box.y + box.height)};left:0;right:0;bottom:0`}></i>
        <i class="shade" style=${`top:${pct(box.y)};left:0;width:${pct(box.x)};height:${pct(box.height)}`}></i>
        <i class="shade" style=${`top:${pct(box.y)};left:${pct(box.x + box.width)};right:0;height:${pct(box.height)}`}></i>
        <i class="box" style=${`left:${pct(box.x)};top:${pct(box.y)};width:${pct(box.width)};height:${pct(box.height)}`}></i>
        ${f.mode === 'fixed' ? html`<i class="handle" style=${`left:calc(${pct(box.x + box.width)} - 7px);top:calc(${pct(box.y + box.height)} - 7px)`}></i>` : null}
      </div>
      <div class="mt-srow"><span class="l muted">Instante</span>
        <input type="range" class="mt-slider" min=${lane.take.start} max=${Math.max(lane.take.end, lane.take.start + 0.1)} step="any" value=${time}
          aria-label="Instante" style=${`--f:${((time - lane.take.start) / Math.max(lane.take.end - lane.take.start, 0.1)) * 100}%`}
          onInput=${e => setTime(+e.currentTarget.value)} />
        <span class="v narrow">${fmtDur(time)}</span></div>
      ${f.mode === 'fixed'
        ? html`<p class="small muted">${f.manualBox == null ? 'Caja automática: arrástrala para moverla; el punto de la esquina la escala.'
          : 'Ajuste manual: arrastra la caja para moverla; el punto de la esquina la escala.'}</p>`
        : html`<div class="mt-follow">
          <${SliderRow} label="Zoom" value=${f.followZoom ?? 1} range=${ZOOM_RANGE} format=${v => '×' + v.toFixed(2)} onChange=${v => send({ followZoom: v })} />
          <${SliderRow} label="Desplazamiento X" value=${f.followOffset?.x ?? 0} range=${OFFSET_RANGE} format=${v => (v >= 0 ? '+' : '−') + Math.abs(v).toFixed(2)}
            onChange=${v => send({ followOffset: { x: v, y: f.followOffset?.y ?? 0 } })} />
          <${SliderRow} label="Desplazamiento Y" value=${f.followOffset?.y ?? 0} range=${OFFSET_RANGE} format=${v => (v >= 0 ? '+' : '−') + Math.abs(v).toFixed(2)}
            onChange=${v => send({ followOffset: { x: f.followOffset?.x ?? 0, y: v } })} />
          <p class="small muted">El recorte sigue la trayectoria de la guitarra; arrastra sobre el fotograma para desplazarlo.</p></div>`}
      <div class="mt-sheet-actions">
        <button class="btn secondary" onClick=${() => resetFraming(takeId)}>Restablecer</button>
        <button class="btn secondary" disabled=${analyzing} onClick=${() => reanalyze(takeId)}>Reanalizar</button>
        <span class="grow"></span>
        <button class="btn primary" onClick=${close}>Hecho</button>
      </div>
    </div>
  </${Modal}>`;
}
