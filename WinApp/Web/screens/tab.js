// Pantalla Tablatura (App/Sources/TabScreen.swift). Partitura: alphaTab en un iframe (tab/frame.js); estado: tab/store.js;
// transporte compartido con Backing: backing/store.js.
import { Fragment } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { entries, selectedEntry, selectedId, screen, go, loaded } from '../state.js';
import { PopupMenu, AccentBar } from '../ui.js';
import { target, study, analyze, transport, pos, onPosition, status as studyStatus, togglePlay, play, pause, seek, setRate, setLoop, setMetronome,
  RATE_MIN, RATE_MAX, RATE_STEP } from '../backing/store.js';
import { fmtClock, fmtPercent } from '../backing/model.js';
import {
  tab, opening, openProblem, webError, dismissed, tracks, readyTracks, selectedTrack, openTab, closeTab, reopenTab, attachFrame, detachFrame,
  createFrame, setKeyHandler, followPosition, watchLoop, selectTrack, toggleMute, toggleSolo, setListening, setAllListening, setSource,
  setTuning, setEditMode, edit, spanAction, transcribe, cancelTranscription, exportGp, localFlash, SPAN_LOOP_NAME,
} from '../tab/store.js';
import { forwardEditKey } from '../tab/keys.js';

/// Mac (TabController.tuningName).
const TUNING_NAMES = { standard: 'Estándar', halfStepDown: 'Medio tono abajo', wholeStepDown: 'Un tono abajo', dropD: 'Drop D', custom: 'Personalizada' };
const FIXED_TUNINGS = ['standard', 'halfStepDown', 'wholeStepDown', 'dropD'];
/// Mac (TabScreen.editBar): piezas de batería y su operación `hit` del contrato.
const DRUM_PIECES = [['kick', 'Bombo'], ['snare', 'Caja'], ['hiHat', 'Charles'], ['tom', 'Tom'], ['crash', 'Platos']];
const RATE_SEND_MS = 150;

const svg = (body, size = 14) => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
  stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
const KIND_ICON = {
  guitar: html`<path d="M14 4l6 6-3 1-2 2a5 5 0 1 1-4-4l2-2z"/><circle cx="9.5" cy="14.5" r="1"/>`,
  bass: html`<path d="M3 12h2l2-6 4 12 3-9 2 3h5"/>`,
  drums: html`<circle cx="6" cy="6" r="2"/><circle cx="12" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="6" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="18" cy="12" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="12" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>`,
  vocal: html`<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>`,
};
const kindIcon = k => svg(KIND_ICON[k] ?? KIND_ICON.guitar);
const speaker = svg(html`<path d="M11 5L6 9H3v6h3l5 4zM16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/>`, 12);

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

/// «Analizar» de «Esperando el análisis» (Mac: `model.retryAnalysis()`): lanza el análisis.
function analyzeAndReopen() { analyze(); }   // el avance llega por `study.analysis`; al terminar, `Tab` reabre (efecto de abajo)

/// Tema de Tablatura: el de Backing (compartido, como `backingTarget` del Mac); si no hay, el seleccionado si ya está separado.
function resolveTarget() {
  if (target.value) return target.value;
  const sel = selectedEntry.value;
  return sel && sel.separationState === 'done' ? sel.id : null;
}

function Chooser() {
  const ready = entries.value.filter(e => e.separationState === 'done');
  return html`<div class="screen tab"><div class="tab-chooser">
    <h1 class="page-title">Tablatura</h1>
    ${!loaded.value ? null : ready.length === 0
      ? html`<p class="muted">Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.</p>`
      : html`<p class="muted">Elige un tema</p>
        <div class="tab-chooser-list">${ready.map(e => html`<button class="tab-chooser-item" key=${e.id} onClick=${() => { target.value = e.id; selectedId.value = e.id; }}>
          <span>${e.title}</span><span class="muted">${e.artist ?? ''}</span></button>`)}</div>`}
  </div></div>`;
}

// ---- Cabecera --------------------------------------------------------------------------------

function SourceMenu({ st }) {
  const [menu, setMenu] = useState(null);
  const label = st.source === 'songsterr' ? 'Songsterr' : st.source === 'automatic' ? 'Transcripción automática' : 'Sin elegir';
  const open = e => { const r = e.currentTarget.getBoundingClientRect(); setMenu({ x: r.right, y: r.bottom + 4 }); };
  const items = [
    // Songsterr aún no existe en Windows (ola 2): mismos textos que el Mac, entradas deshabilitadas.
    { label: 'Buscar en Songsterr…', disabled: true },
    ...(st.source === 'songsterr' ? [{ label: 'Cambiar emparejamiento…', disabled: true }] : []),
    { label: 'Transcripción automática', disabled: st.source === 'automatic', onSelect: () => setSource('automatic') },
  ];
  return html`<${Fragment}><button class="tab-menu-btn" aria-haspopup="menu" disabled=${st.phase === 'waitingAnalysis' || st.phase === 'empty'}
      onClick=${open}>Fuente: ${label}<span class="caret" aria-hidden="true">▾</span></button>
    ${menu ? html`<${PopupMenu} x=${menu.x} y=${menu.y} align="right" items=${items} onClose=${() => setMenu(null)} />` : null}</${Fragment}>`;
}

function Header() {
  const st = tab.value;
  const s = study.value;
  const ready = st?.phase === 'ready';
  return html`<div class="tab-head">
    <div><div class="muted song">${s ? [s.artist, s.title].filter(Boolean).join(' · ') : ''}</div>
      <h1 class="page-title tab-title">Tablatura</h1></div>
    ${st ? html`<div class="tab-head-actions">
      <${SourceMenu} st=${st} />
      <button class=${'tab-toggle' + (st.editMode ? ' on' : '')} aria-pressed=${st.editMode} disabled=${!ready} onClick=${() => setEditMode(!st.editMode)}>Editar notas</button>
      <button class="btn secondary sm" disabled=${!ready || readyTracks.value.length === 0} onClick=${exportGp}>Exportar a Guitar Pro</button>
    </div>` : null}
  </div>`;
}

function Notices({ st }) {
  const shown = (st.notices ?? []).filter(n => !dismissed.value.has(n));
  if (!shown.length) return null;
  return html`<div class="tab-notice" role="status"><div class="tab-notice-text">${shown.map((n, i) => html`<div key=${i}>${n}</div>`)}</div>
    <button class="tab-x" aria-label="Cerrar aviso" onClick=${() => { dismissed.value = new Set([...dismissed.value, ...shown]); }}>${icon('close', 14)}</button></div>`;
}

// ---- Pistas ----------------------------------------------------------------------------------

function ToggleMS({ text, on, label, onClick }) {
  return html`<button class=${'tab-ms' + (on ? ' on' : '')} aria-pressed=${on} aria-label=${label} title=${label} onClick=${onClick}>${text}</button>`;
}

function TrackTabs({ st }) {
  return html`<div class="tab-tracks" role="tablist" aria-label="Pistas">${st.tracks.map(t => {
    if (t.transcription !== 'ready') {
      const txt = t.transcription === 'transcribing' && t.progress != null ? ` ${Math.round(t.progress * 100)} %` : t.transcription === 'failed' ? ' (error)' : '';
      return html`<span class=${'tab-pill pending' + (t.transcription === 'failed' ? ' failed' : '')} key=${t.id}>${t.name}${txt}</span>`;
    }
    const active = t.id === st.selectedTrack;
    return html`<div class="tab-track" key=${t.id} style=${t.dimmed ? 'opacity:.55' : ''}>
      <button role="tab" aria-selected=${active} class=${'tab-pill' + (active ? ' active' : '')} onClick=${() => selectTrack(t.id)}>
        ${kindIcon(t.kind)}<span>${t.name}</span>${t.listening ? speaker : null}</button>
      <${ToggleMS} text="M" on=${t.muted} label=${(t.muted ? 'Activar ' : 'Silenciar ') + t.name} onClick=${() => toggleMute(t.id)} />
      <${ToggleMS} text="S" on=${t.solo} label=${'Solo ' + t.name} onClick=${() => toggleSolo(t.id)} />
    </div>`;
  })}</div>`;
}

function ListenSelector({ st }) {
  const mode = st.listenMode;
  const listening = st.tracks.filter(t => t.listening);
  const done = listening.filter(t => t.synth === 'ready').length;
  const rendering = st.tracks.some(t => t.synth === 'rendering');
  const opt = (title, on, targetOn) => html`<button class=${'tab-seg' + (on ? ' on' : '')} aria-pressed=${on} onClick=${() => setAllListening(targetOn)}>${title}</button>`;
  return html`<div class="tab-listen"><span class="muted">Oír</span>
    ${opt('Stems', mode === 'stems', false)}${opt('Transcripción', mode === 'transcription', true)}
    ${mode === 'mixed' ? html`<span class="muted">Mixto</span>` : null}
    ${rendering ? html`<span class="tab-synth muted"><span class="spinner" aria-hidden="true"></span>Sintetizando ${done}/${listening.length}…</span>` : null}</div>`;
}

function TrackControls({ st, t }) {
  const tuning = t.tuning;
  const custom = t.customTuning;
  return html`<div class="tab-controls">
    ${t.kind !== 'drums' && tuning ? html`<label class="tab-field"><span class="muted">Afinación</span>
      <select class="tab-select" aria-label="Afinación" onChange=${e => setTuning(t.id, e.currentTarget.value)}>
        ${FIXED_TUNINGS.map(p => html`<option value=${p} selected=${tuning.preset === p}>${TUNING_NAMES[p]}</option>`)}
        ${custom || tuning.preset === 'custom' ? html`<option value="custom" selected=${tuning.preset === 'custom'}>${(custom ?? tuning).name || TUNING_NAMES.custom}</option>` : null}
      </select></label>` : null}
    <label class="tab-check"><input type="checkbox" checked=${t.listening} onChange=${e => setListening(t.id, e.currentTarget.checked)} />Oír transcripción</label>
    ${t.synth === 'rendering' ? html`<span class="tab-synth muted"><span class="spinner" aria-hidden="true"></span>Sintetizando…</span>` : null}
    <span class="grow"></span>
    ${st.header ? html`<span class="muted">${st.header}</span>` : null}
  </div>`;
}

// ---- Lienzo y estados ------------------------------------------------------------------------

function Canvas() {
  const box = useRef(null);
  useEffect(() => {
    const f = createFrame(box.current);
    attachFrame(f);
    followPosition(true);
    return () => { followPosition(false); detachFrame(f); f.destroy(); };
  }, []);
  return html`<div class="tab-canvas" ref=${box}></div>`;
}

function TranscribeList({ st, overlay }) {
  const pending = st.tracks.filter(t => t.transcription !== 'ready');
  if (!pending.length) return null;
  const active = pending.some(t => t.transcription === 'queued' || t.transcription === 'transcribing');
  return html`<div class=${'tab-transcribe' + (overlay ? ' overlay' : '')}>
    <div class="tab-transcribe-head"><h2>${active ? 'Transcribiendo…' : 'Transcripción pendiente'}</h2>
      ${active ? html`<button class="btn secondary sm" onClick=${cancelTranscription}>Cancelar</button>` : null}</div>
    ${overlay ? html`<p class="muted">La primera vez tarda un poco. Lo hecho se guarda pista a pista.</p>` : null}
    ${pending.map(t => html`<div class="tab-trow" key=${t.id}><span class="name">${t.name}</span>
      ${t.transcription === 'failed'
        ? html`<span class="err">${t.error ?? 'Error desconocido'}</span><button class="btn secondary sm" onClick=${() => transcribe(t.id)}>Reintentar</button>`
        : html`<${AccentBar} fraction=${t.transcription === 'transcribing' ? t.progress : (t.transcription === 'queued' ? 0 : null)} />
          <span class="muted pct">${t.transcription === 'transcribing' ? (t.progress != null ? Math.round(t.progress * 100) + ' %' : '…') : 'En cola'}</span>`}
    </div>`)}</div>`;
}

function Message({ title, body, children }) {
  return html`<div class="tab-message"><h2>${title}</h2><p class="muted">${body}</p>${children ? html`<div class="actions">${children}</div>` : null}</div>`;
}

function Overlay({ st }) {
  if (opening.value === 'loading') return html`<div class="tab-message"><span class="muted"><span class="spinner" aria-hidden="true"></span> Abriendo el tema…</span></div>`;
  if (!st) return null;
  const anyReady = readyTracks.value.length > 0;
  switch (st.phase) {
    case 'choosingSource':
      return html`<${Message} title="Elige la fuente de la tablatura"
        body="Songsterr trae la tablatura hecha por la comunidad; la transcripción automática sale del audio.">
        <button class="btn secondary sm" disabled>Buscar en Songsterr</button>
        <button class="btn secondary sm" onClick=${() => setSource('automatic')}>Transcribir automáticamente</button></${Message}>`;
    case 'waitingAnalysis':
      return html`<${Message} title="Esperando el análisis del tema"
        body="La tablatura necesita los compases y pulsos del análisis. Puedes lanzarlo desde Backing track.">
        <button class="btn secondary sm" onClick=${analyzeAndReopen}>Analizar</button></${Message}>`;
    case 'empty':
      return html`<${Message} title="No hay pistas que transcribir" body="Este tema no tiene stems de guitarra, bajo o batería con audio." />`;
    case 'failed':
      return html`<${Message} title="No se pudo transcribir" body=${st.error ?? 'Error desconocido'}>
        <button class="btn secondary sm" onClick=${reopenTab}>Reintentar</button></${Message}>`;
    default:
      if (!anyReady) return html`<${TranscribeList} st=${st} overlay=${true} />`;
      return webError.value ? html`<div class="tab-weberr">alphaTab: ${webError.value}</div>` : null;
  }
}

function Footer({ st }) {
  const t = selectedTrack.value;
  const text = st.flash ?? localFlash.value ?? st.selection?.summary
    ?? (st.source === 'songsterr' ? 'Tablatura de Songsterr · revisa y corrige si hace falta' : 'Transcripción automática · revisa y corrige si hace falta');
  return html`<div class=${'tab-footer' + (st.flash || localFlash.value ? ' flash' : '')} aria-live="polite">${t ? text : ''}</div>`;
}

function Score({ st }) {
  const ready = readyTracks.value.length > 0 && (st.phase === 'ready' || st.phase === 'working');
  const t = selectedTrack.value;
  return html`<section class="card tab-card" aria-label="Tablatura">
    ${readyTracks.value.length ? html`<${ListenSelector} st=${st} />` : null}
    ${st.tracks.length ? html`<${TrackTabs} st=${st} />` : null}
    ${t && t.transcription === 'ready' ? html`<${TrackControls} st=${st} t=${t} />` : null}
    ${ready ? html`<${TranscribeList} st=${st} overlay=${false} />` : null}
    <div class="tab-view">
      <${Canvas} />
      <div class=${'tab-cover' + (ready ? ' clear' : '')}><${Overlay} st=${st} /></div>
    </div>
    <${Footer} st=${st} />
  </section>`;
}

// ---- Edición y transporte --------------------------------------------------------------------

function EditBar({ st }) {
  const t = selectedTrack.value;
  const sel = st.selection;
  const hasNote = sel != null && sel.string != null;
  const btn = (label, onClick, { disabled, aria } = {}) => html`<button class="btn secondary xs" disabled=${disabled} aria-label=${aria} onClick=${onClick}>${label}</button>`;
  return html`<div class="tab-editbar" role="toolbar" aria-label="Edición de notas">
    ${btn(html`${icon('undo', 14)}Deshacer`, () => edit('undo'), { disabled: !st.canUndo })}
    ${btn(html`${icon('redo', 14)}Rehacer`, () => edit('redo'), { disabled: !st.canRedo })}
    ${t?.kind === 'drums' ? html`<${Fragment}>
        ${DRUM_PIECES.map(([piece, label]) => html`<button key=${piece} class="btn secondary xs" disabled=${!sel} onClick=${() => edit('hit', { piece })}>${label}</button>`)}
        <span class="muted">B bombo · C caja · H charles · T tom · P platos</span></${Fragment}>`
      : html`<${Fragment}>
        ${btn(html`${icon('plus', 14)}Añadir nota`, () => edit('addNote'))}
        ${btn(icon('minus', 14), () => edit('duration', { sign: -1 }), { disabled: !hasNote, aria: 'Acortar nota' })}
        ${btn(icon('plus', 14), () => edit('duration', { sign: 1 }), { disabled: !hasNote, aria: 'Alargar nota' })}
        ${btn(html`${icon('trash', 14)}Borrar`, () => edit('delete'), { disabled: !hasNote })}
        <span class="muted nowrap">Dígitos: traste · ↑ ↓: cuerda · ← →: mover · +/−: duración · Ctrl+Z deshacer</span></${Fragment}>`}
  </div>`;
}

function TabClock() {
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
  return html`<span class="tab-clock" aria-label="Tiempo"><span ref=${el}>0:00</span><span class="muted"> / ${fmtClock(dur)}</span></span>`;
}

function LoopMenu({ st }) {
  const [menu, setMenu] = useState(null);
  const t = transport.value;
  const loop = t?.loop;
  const bar = st.selection?.barRange;   // Mac: TabController.selectedBarRange
  const open = e => { const r = e.currentTarget.getBoundingClientRect(); setMenu({ x: r.left, y: r.top - 4 }); };
  const items = [
    { label: 'Sin bucle', onSelect: () => { if (st.span) spanAction('clear'); setLoop(null); } },
    ...(st.span ? [{ label: SPAN_LOOP_NAME, onSelect: () => spanAction('apply') }] : []),
    ...(bar ? [{ label: `Compás ${bar.bar + 1}`, onSelect: () => setLoop(bar.start, bar.end, `compás ${bar.bar + 1}`) }] : []),
    ...((study.value?.sections ?? []).map(s => ({ label: s.name, onSelect: () => setLoop(s.start, s.end, s.name) }))),
  ];
  return html`<${Fragment}><button class=${'tab-menu-btn loop' + (loop ? ' on' : '')} aria-haspopup="menu" onClick=${open}>
      ${loop ? `Bucle: ${loop.name || 'libre'} · ${fmtClock(loop.start)}–${fmtClock(loop.end)}` : 'Bucle'}<span class="caret" aria-hidden="true">▾</span></button>
    ${menu ? html`<${PopupMenu} x=${menu.x} y=${menu.y} above=${true} items=${items} onClose=${() => setMenu(null)} />` : null}</${Fragment}>`;
}

function TransportRow({ st }) {
  const t = transport.value;
  const playing = !!t?.playing;
  const rate = t?.rate ?? 1;
  const [live, setLive] = useState(null);
  const sendRate = useRef(throttle(v => setRate(v), RATE_SEND_MS)).current;
  const m = t?.metronome;
  const quant = v => Math.round(+v / 5) * 0.05;
  return html`<div class="tab-transport">
    <button class="tab-round" aria-label="Volver al inicio" title="Volver al inicio" onClick=${() => seek(0)}>
      ${svg(html`<path d="M6 5v14M19 5l-9 7 9 7z"/>`, 16)}</button>
    <button class="tab-play" aria-label=${playing ? 'Pausar' : 'Reproducir'} title=${playing ? 'Pausar (espacio)' : 'Reproducir (espacio)'}
      onClick=${() => (playing ? pause() : play())}>
      ${playing ? html`<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>`
        : html`<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M7 4l13 8-13 8z"/></svg>`}</button>
    <${TabClock} />
    <label class="tab-field tempo"><span>Tempo</span>
      <input type="range" class="tab-range" min=${RATE_MIN * 100} max=${RATE_MAX * 100} step=${RATE_STEP * 100} value=${Math.round((live ?? rate) * 100)} aria-label="Velocidad"
        onInput=${e => { const v = quant(e.currentTarget.value); setLive(v); sendRate(v); }}
        onChange=${e => { setRate(quant(e.currentTarget.value)); setLive(null); }} />
      <b class="tempo-val">${fmtPercent(live ?? rate)}</b></label>
    <label class=${'tab-check' + (m && !m.available ? ' disabled' : '')}>
      <input type="checkbox" checked=${!!m?.on} disabled=${!m?.available} onChange=${e => setMetronome(e.currentTarget.checked)} />Metrónomo</label>
    <${LoopMenu} st=${st} />
  </div>`;
}

// ---- Pantalla --------------------------------------------------------------------------------

function onKey(e) {
  if (e.defaultPrevented) return;
  const tag = e.target?.tagName;
  if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
  if (e.code === 'Space' && !e.ctrlKey && !e.metaKey && !e.altKey) {
    if (e.target?.tagName === 'BUTTON') return;   // un botón enfocado usa el espacio para pulsarse
    e.preventDefault();
    if (!e.repeat && studyStatus.value === 'ready') togglePlay();
    return;
  }
  if (forwardEditKey(e)) e.preventDefault();
}

export function Tab() {
  const id = resolveTarget();
  useEffect(() => {
    if (!id) return undefined;
    target.value = id;
    openTab(id);
    return () => { closeTab({ keepStudy: screen.value === 'backing' }); };
  }, [id]);
  useEffect(() => {
    setKeyHandler(onKey);
    window.addEventListener('keydown', onKey);
    return () => { setKeyHandler(null); window.removeEventListener('keydown', onKey); };
  }, []);
  const st = tab.value;
  const analysisState = study.value?.analysis?.state;
  // Mac: `onChange(of: session.beats) { tab?.start() }`: al terminar el análisis, la tablatura en espera arranca sola.
  useEffect(() => { if (analysisState === 'ready' && st?.phase === 'waitingAnalysis') reopenTab(); }, [analysisState, st?.phase]);
  useEffect(() => { watchLoop(); }, [transport.value?.loop?.name]);

  if (!id) return html`<${Chooser} />`;
  if (opening.value === 'error') {
    const e = openProblem.value;
    return html`<div class="screen tab"><${Header} /><div class="empty error"><b>No se pudo abrir la tablatura</b>
      <span class="muted">${e?.message} <code>(${e?.code})</code></span>
      <div><button class="btn secondary" onClick=${() => openTab(id)}>Reintentar</button></div></div></div>`;
  }
  const open = opening.value === 'ready' && st;
  return html`<div class="screen tab">
    <${Header} />
    ${open ? html`<${Notices} st=${st} />` : null}
    ${open ? html`<${Score} st=${st} />`
      : html`<section class="card tab-card"><div class="tab-view"><div class="tab-cover"><${Overlay} st=${null} /></div></div></section>`}
    ${open && st.editMode && st.phase === 'ready' ? html`<${EditBar} st=${st} />` : null}
    ${open ? html`<${TransportRow} st=${st} />` : null}
  </div>`;
}
