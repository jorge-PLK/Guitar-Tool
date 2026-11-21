// Mezclador (BackingMixer.swift del Mac): master a la izquierda, un canal por stem audible o pista de guitarra.
// Faders y vúmetros se mueven directamente en el DOM (sin re-render de Preact a 30 Hz).
import { html } from '../html.js';
import { useRef, useEffect, useState } from 'preact/hooks';
import { icon } from '../icons.js';
import {
  transport, study, channels, chordsExpanded, onLevels, levels,
  setMix, setMaster, setGuitarStereo, renameGuitar, FADER_MIN_DB, FADER_MAX_DB, FADER_SNAP_DB, METER_FLOOR_DB,
} from './store.js';
import { fmtDb, clamp } from './model.js';

// Mac (MixerChannel): el fader mide 150 px; aquí se estira con el canal (CSS) y la tapa se coloca en porcentaje,
// para que el mezclador encoja con la ventana en lugar de salirse de ella.
/// Mac (BackingView): por encima de este nivel un canal cuenta como sonando; por debajo, silencio.
const SILENT_DB = -119;
/// Cadencia del envío de ganancias al núcleo mientras se arrastra (el estado local es inmediato).
const SEND_MS = 60;

const dbToFrac = db => (clamp(db, FADER_MIN_DB, FADER_MAX_DB) - FADER_MIN_DB) / (FADER_MAX_DB - FADER_MIN_DB);
const capTop = db => `${(1 - dbToFrac(db)) * 100}%`;

function Fader({ db, label, dbRef, onChange, onCommit }) {
  const cap = useRef(null);
  const live = useRef(null);
  const lastSend = useRef(0);
  const place = v => {
    if (cap.current) cap.current.style.top = capTop(v);
    if (dbRef?.current) dbRef.current.textContent = fmtDb(v);
  };
  useEffect(() => { if (live.current == null) place(db); });
  const fromEvent = e => {
    const r = e.currentTarget.getBoundingClientRect();
    const f = 1 - clamp((e.clientY - r.top) / r.height, 0, 1);
    let v = FADER_MIN_DB + f * (FADER_MAX_DB - FADER_MIN_DB);
    if (Math.abs(v) < FADER_SNAP_DB) v = 0;     // imán a 0 dB
    return v;
  };
  const down = e => {
    if (e.button !== 0) return;
    try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
    live.current = fromEvent(e);
    place(live.current); onChange(live.current);
    lastSend.current = performance.now();
  };
  const move = e => {
    if (live.current == null) return;
    live.current = fromEvent(e);
    place(live.current);
    const now = performance.now();
    if (now - lastSend.current >= SEND_MS) { lastSend.current = now; onChange(live.current); }
  };
  const up = () => {
    if (live.current == null) return;
    const v = live.current;
    live.current = null;
    onCommit(v);
  };
  const key = e => {
    const step = e.shiftKey ? 3 : 1;
    if (e.key === 'ArrowUp' || e.key === 'ArrowRight') onCommit(clamp(Math.round(db) + step, FADER_MIN_DB, FADER_MAX_DB));
    else if (e.key === 'ArrowDown' || e.key === 'ArrowLeft') onCommit(clamp(Math.round(db) - step, FADER_MIN_DB, FADER_MAX_DB));
    else if (e.key === 'Home') onCommit(0);
    else return;
    e.preventDefault();
  };
  return html`<div class="fader" role="slider" tabindex="0" aria-label=${'Volumen ' + label} aria-orientation="vertical"
      aria-valuemin=${FADER_MIN_DB} aria-valuemax=${FADER_MAX_DB} aria-valuenow=${Math.round(db * 10) / 10} aria-valuetext=${fmtDb(db)}
      onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onPointerCancel=${up}
      onDblClick=${() => onCommit(0)} onKeyDown=${key}>
    <div class="fader-rail"></div>
    <div class="fader-cap" ref=${cap} style=${`top:${capTop(db)}`}></div>
  </div>`;
}

function Toggle({ text, on, label, onClick }) {
  return html`<button class=${'mix-toggle' + (on ? ' on' : '')} aria-label=${label} aria-pressed=${on} onClick=${onClick}>${text}</button>`;
}

/// Título del canal. Las pistas de guitarra se renombran con doble clic (Mac: MixerChannel.rename); vacío = nombre por defecto.
function ChannelTitle({ c }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const renamable = !!c.guitarRole;
  const start = () => { if (renamable) { setDraft(c.name); setEditing(true); } };
  const commit = () => { if (!editing) return; setEditing(false); if (draft !== c.name) renameGuitar(c.guitarRole, draft); };
  if (editing) {
    return html`<input class="chan-title-edit" type="text" aria-label="Nombre" value=${draft} ref=${el => el && !el.__f && (el.__f = 1, el.focus(), el.select())}
      onInput=${e => setDraft(e.currentTarget.value)} onBlur=${commit}
      onKeyDown=${e => { if (e.key === 'Enter') commit(); else if (e.key === 'Escape') { e.stopPropagation(); setEditing(false); } }} />`;
  }
  return html`<div class=${'chan-title' + (renamable ? ' renamable' : '')} title=${renamable ? c.name + ' · doble clic para cambiar el nombre' : c.name}
    onDblClick=${start} onContextMenu=${e => { if (renamable) { e.preventDefault(); start(); } }}>${c.name}</div>`;
}

/// «Guitarras en L y R» y el estado del paso de guitarras (Mac: GuitarStereoToggle + GuitarStatusView).
function GuitarOptions() {
  const g = study.value?.guitars;
  const process = g?.process ?? 'idle';
  return html`<span class="mixer-tools">
    ${process === 'processing' ? html`<span class="guitar-status" role="status"><span class="spinner" aria-hidden="true"></span>Procesando guitarras…</span>` : null}
    ${process === 'failed' ? html`<span class="guitar-status err" role="alert" title=${g.error ?? ''}>${icon('warning', 14)}<span>${g.error ?? 'Error al procesar las guitarras'}</span></span>` : null}
    ${process === 'idle' && g?.saveError ? html`<span class="guitar-status err" role="alert"><span>${g.saveError}</span></span>` : null}
    <label class="switch" title="L = canal izquierdo, R = canal derecho de la pista de guitarras">
      <input type="checkbox" role="switch" checked=${!!g?.stereoSplit} onChange=${e => setGuitarStereo(e.currentTarget.checked)} />Guitarras en L y R</label>
  </span>`;
}

/// Una columna con faders: stem o guitarra. `meters` registra la barra para que los niveles la muevan sin render.
function Channel({ c, dim, meters }) {
  const bar = useRef(null);
  const dbText = useRef(null);
  useEffect(() => { meters.set(c.id, bar.current); return () => meters.delete(c.id); }, [c.id]);
  // Al montar, o al quedar atenuado, la barra vuelve al nivel actual (0 si atenuado).
  useEffect(() => { paintMeter(bar.current, dim ? null : levels.channels[c.id]); }, [dim, c.id]);
  return html`<div class=${'chan' + (dim ? ' dim' : '')}>
    <${ChannelTitle} c=${c} />
    <div class="chan-body">
      <${Fader} db=${c.gainDB} label=${c.name} dbRef=${dbText}
        onChange=${v => setMix(c.id, { gainDB: v }, { optimistic: false })}
        onCommit=${v => setMix(c.id, { gainDB: v })} />
      <div class="meter" aria-hidden="true"><div class="meter-fill" ref=${bar}></div></div>
    </div>
    <div class="chan-db" ref=${dbText}>${c.muted ? 'Silenciado' : fmtDb(c.gainDB)}</div>
    <div class="chan-btns">
      <${Toggle} text="M" on=${c.muted} label=${(c.muted ? 'Activar ' : 'Silenciar ') + c.name} onClick=${() => setMix(c.id, { muted: !c.muted })} />
      <${Toggle} text="S" on=${c.solo} label=${'Solo ' + c.name} onClick=${() => setMix(c.id, { solo: !c.solo })} />
    </div>
  </div>`;
}

function paintMeter(el, m) {
  if (!el) return;
  const floor = METER_FLOOR_DB;
  const f = m && m.rmsDB > SILENT_DB ? clamp((m.rmsDB - floor) / -floor, 0, 1) : 0;
  el.style.clipPath = `inset(${(1 - f) * 100}% 0 0 0)`;
}

function MasterChannel() {
  const db = transport.value?.masterGainDB ?? 0;
  const dbText = useRef(null);
  return html`<div class="chan master">
    <div class="chan-title">Master</div>
    <div class="chan-body"><${Fader} db=${db} label="Master" dbRef=${dbText} onChange=${v => setMaster(v)} onCommit=${v => setMaster(v)} /></div>
    <div class="chan-db" ref=${dbText}>${fmtDb(db)}</div>
    <div class="chan-btns-spacer"></div>
  </div>`;
}

/// Compacto (rejilla expandida): master en una línea y solo M/S por canal.
function Compact({ chs, anySolo }) {
  const db = transport.value?.masterGainDB ?? 0;
  return html`<div class="mix-compact">
    <div class="mix-master-row"><b>Master</b>
      <input type="range" class="range" min=${FADER_MIN_DB} max=${FADER_MAX_DB} step="0.5" value=${db} aria-label="Volumen Master"
        onInput=${e => { const v = +e.currentTarget.value; setMaster(Math.abs(v) < FADER_SNAP_DB ? 0 : v); }} />
      <span class="chan-db">${fmtDb(db)}</span></div>
    <div class="mix-sep"></div>
    <div class="mix-compact-chans">${chs.map(c => {
      const dim = c.muted || (anySolo && !c.solo);
      return html`<div class=${'cchan' + (dim ? ' dim' : '')} key=${c.id}><div class="cchan-name" title=${c.name}>${c.name}</div>
        <div class="chan-btns">
          <${Toggle} text="M" on=${c.muted} label=${(c.muted ? 'Activar ' : 'Silenciar ') + c.name} onClick=${() => setMix(c.id, { muted: !c.muted })} />
          <${Toggle} text="S" on=${c.solo} label=${'Solo ' + c.name} onClick=${() => setMix(c.id, { solo: !c.solo })} />
        </div></div>`;
    })}</div>
  </div>`;
}

export function Mixer() {
  const t = transport.value;
  const meters = useRef(new Map()).current;
  const chs = channels.value;
  const anySolo = !!t?.anySolo;
  const compact = chordsExpanded.value;
  useEffect(() => onLevels(l => {
    for (const [id, el] of meters) {
      const c = transport.value?.channels.find(x => x.id === id);
      const dim = c && (c.muted || (transport.value.anySolo && !c.solo));
      paintMeter(el, dim ? null : l.channels[id]);
    }
  }), []);
  const out = study.value?.audio?.outputName;
  return html`<section class=${'card mixer' + (compact ? ' compact' : '')} aria-label="Mezclador">
    <div class="mixer-head"><h2>Mezclador</h2><span class="grow"></span>
      ${chs.some(c => c.kind === 'guitar') || study.value?.usesSeparatedGuitars ? html`<${GuitarOptions} />` : null}
      <span class="muted small">Salida: ${out ? out : '—'}</span></div>
    ${compact ? html`<${Compact} chs=${chs} anySolo=${anySolo} />` : html`<div class="mixer-body">
      <${MasterChannel} />
      <div class="mix-sep tall"></div>
      <div class="mix-chans">${chs.map(c => html`<${Channel} key=${c.id} c=${c} dim=${c.muted || (anySolo && !c.solo)} meters=${meters} />`)}</div>
    </div>`}
    ${chs.length === 0 ? html`<p class="muted small">Este tema no tiene stems con fichero que mezclar.</p>` : null}
  </section>`;
}
