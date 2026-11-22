// Las tres columnas de Montaje: Layout, Vista previa y Exportación (MontageView.swift: LayoutColumn, PreviewColumn, SettingsColumn).
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { attachFrames } from '../frames.js';
import {
  snap, status, lanes, previewReady, exportStatus, setLayout, setSingleRhythm, setExport, setCaption, setShowPartLabels,
  setKeepVideoAspect, setCutGaps, togglePlay, seek, setScrubbing, onPosition, pos,
} from './store.js';
import { LAYOUTS, TRANSITIONS, fmtDur, sectionName, resLabel, fpsLabel, FPS_CHOICES } from './model.js';

const pauseIcon = html`<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><rect x="5" y="3" width="5" height="18" rx="1"/><rect x="14" y="3" width="5" height="18" rx="1"/></svg>`;
const playIcon = icon('play', 16);

function Thumb({ kind }) {
  const t = () => html`<i></i>`;
  const body = kind === 'side' ? html`<div class="th-row w56 h30">${t()}${t()}</div>`
    : kind === 'grid' ? html`<div class="th-grid w56 h30"><div class="th-row">${t()}${t()}</div><div class="th-row">${t()}${t()}</div></div>`
    : kind === 'stack' ? html`<div class="th-grid w24 h40">${t()}${t()}</div>`
    : kind === 'single' ? html`<div class="th-row w24 h40">${t()}</div>`
    : html`<div class="th-row w56 h30">${t()}</div>`;
  return html`<span class="mt-thumb" aria-hidden="true">${body}</span>`;
}

/// Texto que encoge hasta un 80 % para caber en una línea (minimumScaleFactor(0.8) del Mac).
function FitText({ cls, text, size = 11 }) {
  const ref = useRef(null);
  useLayoutEffect(() => {
    const el = ref.current;
    const fit = () => {
      el.style.fontSize = size + 'px';
      const over = el.scrollWidth / Math.max(el.clientWidth, 1);
      if (over > 1) el.style.fontSize = Math.max(size * 0.8, size / over * 0.96) + 'px';   // 4 % de holgura: con el redondeo de scrollWidth, el ajuste justo todavía cortaba con «…»
    };
    fit();
    document.fonts?.load('400 11px Inter').then(fit).catch(() => {});   // Inter (font-display: block) llega después del primer ajuste: se vuelve a medir
    const ro = new ResizeObserver(fit);   // y cuando cambia el ancho (columna compacta, ventana)
    ro.observe(el);
    return () => ro.disconnect();
  });
  return html`<span class=${cls} ref=${ref}>${text}</span>`;
}

export function LayoutColumn() {
  const s = snap.value;
  const cands = (s.singleRhythmCandidates ?? []).map(id => lanes.value.find(l => l.id === id)).filter(Boolean);
  return html`<section class="card mt-card mt-layout" aria-label="Layout">
    <h2>Layout</h2>
    ${LAYOUTS.map(l => html`<button key=${l.kind} class=${'mt-layout-item' + (s.layout === l.kind ? ' on' : '')} aria-pressed=${s.layout === l.kind}
      onClick=${() => setLayout(l.kind)}>
      <${Thumb} kind=${l.kind} />
      <span class="mt-layout-text"><span class="n">${l.name}</span><${FitText} cls="d" text=${l.desc} /></span></button>`)}
    ${s.isSingleShot ? html`<div class="mt-rhythm"><span class="small muted">Rítmica del plano único</span>
      <select class="mt-popup wide" aria-label="Rítmica del plano único" value=${s.singleRhythmPartId ?? ''}
        onChange=${e => setSingleRhythm(e.currentTarget.value || null)}>
        <option value="">Automática (${cands[0]?.partName ?? '—'})</option>
        ${cands.map(l => html`<option value=${l.id} selected=${s.singleRhythmPartId === l.id}>${l.partName}</option>`)}</select></div>` : null}
  </section>`;
}

/// Reloj de la vista previa: texto, deslizador y sección se actualizan desde el evento de posición, sin re-render.
function useClock(refs, span) {
  useEffect(() => {
    let shown = '';
    const paint = () => {
      const t = pos.seconds;
      if (refs.now.current) refs.now.current.textContent = fmtDur(t);
      if (refs.range.current && !refs.range.current.dataset.drag) refs.range.current.value = String(Math.min(Math.max(t, span.start), span.end));
      if (refs.head.current) {
        const txt = [fmtDur(t), sectionName(snap.value, t)].filter(Boolean).join(' · ');
        if (txt !== shown) { shown = txt; refs.head.current.textContent = txt; }
      }
      if (refs.range.current) {
        const f = span.end > span.start ? (Math.min(Math.max(t, span.start), span.end) - span.start) / (span.end - span.start) : 0;
        refs.range.current.style.setProperty('--f', (f * 100) + '%');
      }
    };
    paint();
    return onPosition(paint);
  }, [span.start, span.end]);
}

export function PreviewColumn() {
  const s = snap.value;
  const canvas = useRef(null);
  const now = useRef(null), range = useRef(null), head = useRef(null);
  const ready = previewReady.value;
  const phase = s.preview?.phase ?? 'none';
  const span = s.span ?? { start: 0, end: 0 };
  const playing = !!s.transport?.playing;
  useEffect(() => attachFrames(canvas.current, 'montage'), []);
  useClock({ now, range, head }, span);
  const dur = span.end - span.start;
  const label = `Vista previa · ${s.canvasLabel}`;
  return html`<section class="card mt-card mt-preview" aria-label="Vista previa">
    <div class="mt-prev-head muted"><span class="t">${label}</span><span class="tm" ref=${head}>${fmtDur(pos.seconds)}</span></div>
    <div class="mt-player-wrap"><div class=${'mt-player' + (s.isPortrait ? ' portrait' : '')}>
      <canvas ref=${canvas} aria-label="Vista previa del montaje"></canvas>
      ${phase === 'preparing' || phase === 'none' ? html`<span class="mt-prep" role="status"><span class="spinner" aria-hidden="true"></span></span>` : null}
    </div></div>
    <div class="mt-controls">
      <button class="mt-play" disabled=${!ready} aria-label=${playing ? 'Pausar la vista previa' : 'Reproducir la vista previa'}
        onClick=${togglePlay}>${playing ? pauseIcon : playIcon}</button>
      ${dur > 0 ? html`<input type="range" class="mt-slider" ref=${range} min=${span.start} max=${span.end} step="any" disabled=${!ready}
          aria-label="Posición de la vista previa"
          onPointerDown=${e => { e.currentTarget.dataset.drag = '1'; setScrubbing(true); }}
          onPointerUp=${e => { delete e.currentTarget.dataset.drag; setScrubbing(false); seek(+e.currentTarget.value); }}
          onPointerCancel=${e => { delete e.currentTarget.dataset.drag; setScrubbing(false); }}
          onInput=${e => { seek(+e.currentTarget.value, { final: false }); }}
          onChange=${e => seek(+e.currentTarget.value)} />` : html`<span class="grow"></span>`}
      <span class="mt-clock"><span ref=${now}>${fmtDur(pos.seconds)}</span><span class="muted"> / ${fmtDur(span.end)}</span></span>
    </div>
    ${s.preview?.audio?.phase === 'preparing' ? html`<div class="small muted" role="status">Mezclando el audio de la vista previa…</div>` : null}
    ${s.preview?.audio?.phase === 'error' && s.preview.audio.error ? html`<div class="small danger-text">${s.preview.audio.error}</div>` : null}
  </section>`;
}

function Popup({ label, value, onChange, children, disabled }) {
  return html`<label class="mt-row"><span class="lbl">${label}</span>
    <select class="mt-popup" aria-label=${label} value=${String(value)} disabled=${disabled} onChange=${onChange}>${children}</select></label>`;
}

function Check({ label, on, onChange, disabled, title }) {
  return html`<label class=${'check mt-check' + (disabled ? ' disabled' : '')} title=${title}>
    <input type="checkbox" checked=${on} disabled=${disabled} onChange=${e => onChange(e.currentTarget.checked)} /><span>${label}</span></label>`;
}

function InfoPopover({ anchor, onClose }) {
  const ref = useRef(null);
  const [pos_, setPos] = useState({ left: 0, top: 0 });
  useLayoutEffect(() => {
    const a = anchor.getBoundingClientRect(), r = ref.current.getBoundingClientRect();
    setPos({ left: Math.max(8, Math.min(a.left + a.width / 2 - r.width / 2, window.innerWidth - r.width - 8)), top: a.bottom + 8 });
  }, []);
  useEffect(() => {
    const down = e => { if (!ref.current.contains(e.target) && !anchor.contains(e.target)) onClose(); };
    const key = e => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('mousedown', down, true);
    document.addEventListener('keydown', key);
    return () => { document.removeEventListener('mousedown', down, true); document.removeEventListener('keydown', key); };
  }, []);
  return html`<div class="mt-pop" ref=${ref} role="dialog" aria-label="Transiciones" style=${`left:${pos_.left}px;top:${pos_.top}px`}>
    <h3>Transiciones</h3>
    ${TRANSITIONS.map(([k, v]) => html`<div class="row" key=${k}><span class="k">${k}</span><span class="v">${v ?? snap.value.anticipationLabel}</span></div>`)}</div>`;
}

export function SettingsColumn() {
  const s = snap.value, ex = s.export;
  const [info, setInfo] = useState(false);
  const btn = useRef(null);
  const opts = ex.options ?? {};
  const codecs = opts.codecs ?? [];
  const containers = opts.containers ?? ['mov', 'mp4'];
  const resolutions = opts.resolutions ?? [];
  const fpsList = [...new Set([...(opts.fps?.length ? opts.fps : FPS_CHOICES), ex.fps])].sort((a, b) => a - b);
  const resKey = r => `${r.width}x${r.height}`;
  const codecName = c => (c === 'hevc' ? 'HEVC' : c === 'h264' ? 'H.264' : c);
  return html`<section class="card mt-card mt-settings" aria-label="Exportación">
    <div class="mt-set-head"><h2>Exportación</h2>
      <button class="mt-info" ref=${btn} title="Transiciones" aria-label="Transiciones" aria-expanded=${info} onClick=${() => setInfo(!info)}>${icon('info', 16)}</button></div>
    ${info ? html`<${InfoPopover} anchor=${btn.current} onClose=${() => setInfo(false)} />` : null}
    ${codecs.length > 1 ? html`<${Popup} label="Formato" value=${ex.codec} onChange=${e => setExport({ codec: e.currentTarget.value })}>
      ${codecs.map(c => html`<option value=${c} selected=${ex.codec === c}>${codecName(c)}</option>`)}</${Popup}>` : null}
    <${Popup} label="Contenedor" value=${ex.container} onChange=${e => setExport({ container: e.currentTarget.value })}>
      ${containers.map(c => html`<option value=${c} selected=${ex.container === c}>${c.toUpperCase()}</option>`)}</${Popup}>
    <${Popup} label="Resolución" value=${resKey(ex.resolution)}
      onChange=${e => { const [width, height] = e.currentTarget.value.split('x').map(Number); setExport({ resolution: { width, height } }); }}>
      ${resolutions.map(r => html`<option value=${resKey(r)} selected=${resKey(ex.resolution) === resKey(r)}>${resLabel(r)}</option>`)}</${Popup}>
    <${Popup} label="Fotogramas" value=${ex.fps} onChange=${e => setExport({ fps: +e.currentTarget.value })}>
      ${fpsList.map(f => html`<option value=${f} selected=${ex.fps === f}>${fpsLabel(f)}</option>`)}</${Popup}>
    <${Check} label="Volumen normalizado a -14 LUFS" on=${ex.normalize} onChange=${v => setExport({ normalize: v })} />
    <${Check} label="Limitador" on=${ex.limiter} disabled=${!ex.normalize} onChange=${v => setExport({ limiter: v })} />
    <${Check} label="Rótulo con título y artista" on=${s.caption} onChange=${setCaption} />
    <${Check} label="Nombre de cada parte" on=${s.showPartLabels} onChange=${setShowPartLabels} />
    <${Check} label="Mantener aspect ratio de vídeo" on=${s.keepVideoAspect} disabled=${!s.keepAspectApplies} onChange=${setKeepVideoAspect}
      title=${s.keepAspectApplies ? '' : 'Solo en apilado y plano único'} />
    <${Check} label="Cortar huecos sin tomas" on=${s.cutGaps} onChange=${setCutGaps} />
    <${Check} label="WAV de cada pista" on=${ex.trackWAVs} onChange=${v => setExport({ trackWAVs: v })} />
  </section>`;
}
