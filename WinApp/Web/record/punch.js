// Línea de tiempo del punch-in (PunchTimeline del Mac): secciones del tema y marcas de entrada y salida; el núcleo da el imán al
// compás salvo con Alt (`free`). Mac: primer arrastre fija la entrada, el segundo la salida; con las dos, mueve la más cercana.
import { useRef, useEffect } from 'preact/hooks';
import { html } from '../html.js';
import { snap, locked, pos, onPosition, setPunch } from './store.js';
import { fmtPunch, TF_PALETTE } from './bits.js';

const HEIGHT = 54;
/// Cadencia del envío de marcas al núcleo mientras se arrastra.
const SEND_MS = 50;

export function PunchTimeline() {
  const s = snap.value;
  const d = Math.max(s.duration, 0.001);
  const a = s.punch?.in ?? null, b = s.punch?.out ?? null;
  const busy = locked.value;
  const track = useRef(null), head = useRef(null);
  const drag = useRef({ active: null, last: 0 });
  const pct = t => `${(t / d) * 100}%`;
  useEffect(() => {
    const paint = () => {
      if (!head.current) return;
      const show = pos.phase !== 'idle' || pos.seconds > 0;
      head.current.style.display = show ? '' : 'none';
      head.current.style.left = pct(pos.seconds);
    };
    paint();
    return onPosition(paint);
  }, [d]);
  const timeAt = e => {
    const r = track.current.getBoundingClientRect();
    return Math.min(Math.max((e.clientX - r.left) / Math.max(r.width, 1), 0), 1) * d;
  };
  const send = (e, t) => {
    const dr = drag.current;
    if (dr.active == null) {
      if (a == null) dr.active = 'in';
      else if (b == null) dr.active = 'out';
      else dr.active = Math.abs(t - a) <= Math.abs(t - b) ? 'in' : 'out';
    }
    setPunch({ [dr.active]: t, free: e.altKey });
  };
  const down = e => {
    if (busy || e.button !== 0) return;
    try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
    drag.current = { active: null, last: performance.now(), pressed: true };
    send(e, timeAt(e));
  };
  const move = e => {
    const dr = drag.current;
    if (!dr.pressed) return;
    const now = performance.now();
    if (now - dr.last < SEND_MS) return;
    dr.last = now;
    send(e, timeAt(e));
  };
  const up = e => {
    const dr = drag.current;
    if (!dr.pressed) return;
    dr.pressed = false;
    send(e, timeAt(e));
    dr.active = null;
  };
  return html`<section class=${'card rec-punch' + (busy ? ' disabled' : '')} aria-label="Punch-in">
    <div class="rec-punch-head"><h3>Punch-in</h3><span class="grow"></span>
      <span class="rec-punch-sum">Entrada ${fmtPunch(a)} · Salida ${fmtPunch(b)}</span></div>
    <div class="rec-track" ref=${track} style=${`height:${HEIGHT}px`} onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onPointerCancel=${up}>
      ${s.sections.map(x => {
        const c = TF_PALETTE[(x.paletteIndex ?? 0) % TF_PALETTE.length];
        return html`<div class="rec-sec" key=${x.id} style=${`left:${pct(x.start)};width:max(${((x.end - x.start) / d) * 100}%,2px);background:${c}4D;color:${c}`}>${x.name}</div>`;
      })}
      ${a != null ? html`<div class="rec-punch-range" style=${`left:${pct(a)};width:max(${(((b ?? a) - a) / d) * 100}%,2px)`}></div>` : null}
      ${a != null ? html`<div class="rec-handle" style=${`left:calc(${pct(a)} - 3px)`} aria-label="Entrada del punch-in"></div>` : null}
      ${b != null ? html`<div class="rec-handle" style=${`left:calc(${pct(b)} - 3px)`} aria-label="Salida del punch-in"></div>` : null}
      <div class="rec-playhead" ref=${head} style="display:none"></div></div>
    <p class="rec-punch-help">Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (Alt = libre, sin imán al compás).</p></section>`;
}
