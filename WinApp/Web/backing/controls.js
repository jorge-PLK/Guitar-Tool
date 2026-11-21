// Transporte, barra de progreso, tiempos y ajustes de la tarjeta «Línea de tiempo» (BackingTimelineCard del Mac).
// Posición y reloj se actualizan directamente en el DOM desde `study.position`; el resto sale de señales.
import { html } from '../html.js';
import { useRef, useEffect, useState } from 'preact/hooks';
import {
  transport, study, pos, onPosition, play, pause, seek, setRate, setTranspose, setCapo, setLoop, setMetronome,
  RATE_MIN, RATE_MAX, RATE_STEP,
} from './store.js';
import { fmtClock, fmtPercent, clamp } from './model.js';
import { keyName, chordName, transposed, chordShape } from './chords.js';
import { chordAt, nextChord } from './model.js';
import { ChordDiagram } from './diagram.js';
import { KeyMenu } from './chord-editor.js';
import { icon } from '../icons.js';

const BAR_THUMB = 14;
/// Cadencia del envío de velocidad/afinación mientras se arrastra el deslizador.
const SLIDER_SEND_MS = 150;

const throttle = (fn, ms) => {
  let last = 0, timer = 0, args;
  return (...a) => {
    args = a;
    const now = performance.now();
    if (now - last >= ms) { last = now; fn(...a); return; }
    clearTimeout(timer);
    timer = setTimeout(() => { last = performance.now(); fn(...args); }, ms - (now - last));
  };
};

/// «1:24 / 3:52», el primero actualizado desde el evento de posición.
export function Clock() {
  const el = useRef(null);
  const dur = transport.value?.duration ?? 0;
  useEffect(() => {
    let shown = -1;
    const paint = () => {
      const s = Math.floor(pos.seconds);
      if (s !== shown && el.current) { shown = s; el.current.textContent = fmtClock(pos.seconds); }
    };
    paint();
    return onPosition(paint);
  }, []);
  return html`<span class="clock" aria-label="Tiempo"><span class="now" ref=${el}>0:00</span><span class="total"> / ${fmtClock(dur)}</span></span>`;
}

/// Barra de progreso: clic salta, arrastrar mueve el cabezal con seek continuo limitado. Muestra el bucle.
export function ProgressBar() {
  const dur = Math.max(transport.value?.duration ?? 0, 0.001);
  const loop = transport.value?.loop;
  const fill = useRef(null), thumb = useRef(null), root = useRef(null);
  const scrub = useRef(null);
  const place = s => {
    const f = clamp(s / dur, 0, 1), w = root.current?.clientWidth ?? 0;
    if (fill.current) fill.current.style.transform = `scaleX(${f})`;
    if (thumb.current) thumb.current.style.transform = `translateX(${f * w - BAR_THUMB / 2}px)`;
  };
  useEffect(() => {
    place(scrub.current ?? pos.seconds);
    const off = onPosition(() => { if (scrub.current == null) place(pos.seconds); });
    const ro = new ResizeObserver(() => place(scrub.current ?? pos.seconds));
    ro.observe(root.current);
    return () => { off(); ro.disconnect(); };
  }, [dur]);
  const at = e => { const r = root.current.getBoundingClientRect(); return clamp((e.clientX - r.left) / r.width, 0, 1) * dur; };
  const down = e => {
    if (e.button !== 0) return;
    try { root.current.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
    scrub.current = at(e); place(scrub.current); seek(scrub.current, { final: false });
  };
  const move = e => { if (scrub.current == null) return; scrub.current = at(e); place(scrub.current); seek(scrub.current, { final: false }); };
  const up = e => { if (scrub.current == null) return; const s = at(e); scrub.current = null; seek(s); };
  const key = e => {
    const d = e.key === 'ArrowRight' ? 5 : e.key === 'ArrowLeft' ? -5 : 0;
    if (!d) return;
    e.preventDefault(); seek(pos.seconds + d);
  };
  const lx = loop ? (loop.start / dur) * 100 : 0, lw = loop ? Math.max(((loop.end - loop.start) / dur) * 100, 0.2) : 0;
  return html`<div class="progress" ref=${root} role="slider" tabindex="0" aria-label="Posición" aria-valuemin="0" aria-valuemax=${Math.round(dur)}
      aria-valuenow=${Math.round(pos.seconds)} aria-valuetext=${`${fmtClock(pos.seconds)} de ${fmtClock(dur)}`}
      onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onPointerCancel=${up} onKeyDown=${key}>
    <div class="progress-track"></div>
    <div class="progress-fill" ref=${fill}></div>
    ${loop ? html`<div class="progress-loop" style=${`left:${lx}%;width:${lw}%`}></div>` : null}
    <div class="progress-thumb" ref=${thumb}></div>
  </div>`;
}

/// Acorde actual y siguiente con su diagrama; solo se re-renderiza al cambiar de acorde.
export function ChordCard({ chords }) {
  const [cur, setCur] = useState(() => chordAt(chords, pos.seconds));
  useEffect(() => {
    const f = () => setCur(chordAt(chords, pos.seconds));
    f();
    return onPosition(f);
  }, [chords]);
  const t = transport.value;
  const tr = t?.transpose ?? 0, capo = t?.capo ?? 0;
  const idx = cur >= 0 ? transposed(chords[cur].index, tr) : null;
  const nxt = nextChord(chords, cur);
  return html`<div class="chord-card">
    <${ChordDiagram} shape=${idx != null ? chordShape(idx, capo) : null} />
    <div class="chord-card-text">
      <div class="chord-card-name">${idx != null ? chordName(idx) : '—'}</div>
      <div class="chord-card-next">${nxt ? 'Siguiente: ' + chordName(transposed(nxt.index, tr)) : ' '}</div>
      ${capo > 0 ? html`<div class="chord-card-capo">Capo ${capo}</div>` : null}
    </div>
  </div>`;
}

/// Tempo detectado, tonalidad, transposición, capo y afinación fina.
export function InfoRow() {
  const t = transport.value, a = study.value?.analysis;
  const tr = t?.transpose ?? 0, cents = t?.fineCents ?? 0;
  const [fine, setFine] = useState(null);
  const sendFine = useRef(throttle(v => setTranspose(undefined, v), SLIDER_SEND_MS)).current;
  return html`<div class="bk-info-row">
    <span class="stat">Tempo detectado: <b>${a?.bpm ? `${Math.round(a.bpm)} BPM` : '—'}</b></span>
    <${KeyMenu} />
    <label class="labeled">Transponer
      <select class="select" aria-label="Transponer" value=${tr} onChange=${e => setTranspose(+e.currentTarget.value)}>
        ${Array.from({ length: 25 }, (_, i) => i - 12).map(n => html`<option value=${n} selected=${n === tr}>${n === 0 ? '0 semitonos' : (n > 0 ? '+' : '−') + Math.abs(n)}</option>`)}
      </select></label>
    <label class="labeled">Capo virtual
      <select class="select" aria-label="Capo virtual" onChange=${e => setCapo(+e.currentTarget.value)}>
        ${Array.from({ length: 13 }, (_, i) => html`<option value=${i} selected=${i === (t?.capo ?? 0)}>${i === 0 ? 'Sin capo' : 'Traste ' + i}</option>`)}
      </select></label>
    <label class="labeled">Afinación fina
      <input type="range" class="range" min="-50" max="50" step="1" value=${fine ?? cents} aria-label="Afinación fina"
        onInput=${e => { const v = Math.round(+e.currentTarget.value); setFine(v); sendFine(v); }}
        onChange=${e => { setTranspose(undefined, Math.round(+e.currentTarget.value)); setFine(null); }} />
      <span class="cents">${Math.round(fine ?? cents)} cents</span></label>
  </div>`;
}

/// Reproducir/pausa, tiempo, bucle, tempo y metrónomo.
export function TransportBar() {
  const t = transport.value;
  const playing = !!t?.playing;
  const loop = t?.loop;
  const rate = t?.rate ?? 1;
  const [live, setLive] = useState(null);
  const sendRate = useRef(throttle(v => setRate(v), SLIDER_SEND_MS)).current;
  const m = t?.metronome;
  return html`<div class="transport">
    <button class="play-btn" aria-label=${playing ? 'Pausar' : 'Reproducir'} title=${playing ? 'Pausar (espacio)' : 'Reproducir (espacio)'}
      onClick=${() => (playing ? pause() : play())}>
      ${playing
        ? html`<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>`
        : html`<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M7 4l13 8-13 8z"/></svg>`}
    </button>
    <${Clock} />
    <${LoopMarks} />
    ${loop ? html`<span class="loop-pill">Bucle: ${loop.name || 'libre'} · ${fmtClock(loop.start)}–${fmtClock(loop.end)}
      <button class="loop-x" aria-label="Quitar bucle" onClick=${() => setLoop(null)}>${icon('close', 12)}</button></span>` : null}
    <label class="labeled tempo">Tempo
      <input type="range" class="range" min=${RATE_MIN * 100} max=${RATE_MAX * 100} step=${RATE_STEP * 100} value=${Math.round((live ?? rate) * 100)}
        aria-label="Velocidad"
        onInput=${e => { const v = Math.round(+e.currentTarget.value / 5) * 0.05; setLive(v); sendRate(v); }}
        onChange=${e => { setRate(Math.round(+e.currentTarget.value / 5) * 0.05); setLive(null); }} />
      <b class="tempo-val">${fmtPercent(live ?? rate)}</b></label>
    <label class=${'check' + (m && !m.available ? ' disabled' : '')}>
      <input type="checkbox" checked=${!!m?.on} disabled=${!m?.available} onChange=${e => setMetronome(e.currentTarget.checked)} />Metrónomo</label>
  </div>`;
}

/// Marcar inicio/fin del bucle en la posición actual (además de arrastrar sobre la tira de acordes).
function LoopMarks() {
  const loop = transport.value?.loop;
  const [a, setA] = useState(null);                 // inicio marcado a la espera del fin
  useEffect(() => { if (a != null && !transport.value) setA(null); });
  const markStart = () => {
    const t = pos.seconds;
    if (loop && t < loop.end) { setA(null); setLoop(t, loop.end, loop.name); } else setA(t);
  };
  const markEnd = () => {
    const t = pos.seconds;
    if (a != null && t > a) { setLoop(a, t); setA(null); }
    else if (loop && t > loop.start) setLoop(loop.start, t, loop.name);
  };
  return html`<span class="loop-marks" role="group" aria-label="Marcar bucle">
    <button class=${'btn secondary sm mark' + (a != null ? ' pending' : '')} onClick=${markStart}
      title="Marca el inicio del bucle en la posición actual">Inicio${a != null ? ' ' + fmtClock(a) : ''}</button>
    <button class="btn secondary sm mark" onClick=${markEnd} disabled=${a == null && !loop}
      title="Marca el final del bucle en la posición actual">Fin</button>
  </span>`;
}
