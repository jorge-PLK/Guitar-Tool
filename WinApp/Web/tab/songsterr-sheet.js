// Hoja «Tablatura de Songsterr» (App/Sources/TabSourceSheet.swift) sobre `tab.songsterr.*` (contrato W2-G).
// La vista previa no puede ser un <iframe> (Songsterr manda x-frame-options: Deny): el anfitrión pone un panel nativo encima de
// la página (`host.preview.show/hide`) y aquí solo se reserva el recuadro y se le pasa su rectángulo.
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { signal } from '@preact/signals';
import { Fragment as Fragment_ } from 'preact';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { call, on, transportName } from '../bridge.js';
import { Modal, AccentBar } from '../ui.js';
import { notify } from '../state.js';
import { applyTabState } from './store.js';

// La hoja carga su propia hoja de estilos (index.html no se toca).
if (!document.querySelector('link[data-songsterr-sheet]')) {
  const l = document.createElement('link');
  l.rel = 'stylesheet'; l.href = 'tab/songsterr-sheet.css'; l.dataset.songsterrSheet = '';
  document.head.appendChild(l);
}

/// Medidas de la hoja del Mac (TabSourceSheet.listWidth / previewWidth / sheetHeight).
const LIST_WIDTH = 612;
const PREVIEW_WIDTH = 640;
const SHEET_HEIGHT = 640;
const SHEET_PAD = 24;
const SHEET_GAP = 20;
/// El Mac deja que la hoja sea más ancha que la ventana; aquí el modal no puede salirse de ella (24 px de margen por lado).
const WINDOW_MARGIN = 24;
const LIST_WIDTH_MIN = 520;
/// Rebote al cambiar el tamaño de la ventana antes de recolocar el panel nativo.
const PREVIEW_DEBOUNCE_MS = 120;
/// Confianza: solo color orientativo de la lista del Mac (TabSourceSheet.goodConfidence / fairConfidence), no son umbrales de la spec.
const GOOD_CONFIDENCE = 0.6;
const FAIR_CONFIDENCE = 0.35;

/// SheetState del núcleo (`{open:false}` = cerrada).
export const sheet = signal(null);
/// «Vista previa» abierta (Mac: `previewOpen`): se abre al marcar un resultado y con el botón; «Cerrar» y cerrar la hoja la quitan.
const previewOpen = signal(false);
/// El anfitrión respondió `unsupported` a `host.preview.show`: sin vista previa.
const previewUnsupported = signal(false);

const apply = s => {
  if (!s || s.open === false) { sheet.value = null; previewOpen.value = false; return; }
  sheet.value = s;
};

on('tab.songsterr.state', s => { if (sheet.value) apply(s); });

/// Llama a un método de la hoja y aplica el SheetState de la respuesta. Los errores se avisan.
async function act(method, params = {}) {
  try { const s = await call(method, params); apply(s); return s; }
  catch (e) { if (e.code !== 'not-open') notify('error', e.message); else sheet.value = null; return null; }
}

export const openSongsterr = () => act('tab.songsterr.open');
export const reviewSongsterr = () => act('tab.songsterr.review');
export const closeSongsterr = () => act('tab.songsterr.close');
/// Al salir de la pantalla: sin hoja (el núcleo cierra la suya con `tab.close`).
export function resetSongsterr() { sheet.value = null; previewOpen.value = false; }

/// «Transcribir automáticamente» desde la hoja: TabState (cierra la hoja).
export async function chooseAutomaticFromSheet() {
  try { applyTabState(await call('tab.songsterr.automatic')); sheet.value = null; previewOpen.value = false; }
  catch (e) { notify('error', e.message); }
}
async function accept() {
  try { applyTabState(await call('tab.songsterr.accept')); sheet.value = null; previewOpen.value = false; }   // applyTabState lanza tab.transcribe de las `queued`
  catch (e) { notify('error', e.message); }
}

// ---- Vista previa nativa ---------------------------------------------------------------------

let hostQueue = Promise.resolve();
const hostCall = (method, params) => {
  hostQueue = hostQueue.then(() => call(method, params, { timeout: 10000 })).catch(e => {
    if (e.code === 'unsupported') previewUnsupported.value = true;
    else console.error(method, e.code, e.message);
  });
};

function PreviewBox({ url }) {
  const box = useRef(null);
  const show = () => {
    const el = box.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return;
    hostCall('host.preview.show', { url, x: Math.round(r.left), y: Math.round(r.top), width: Math.round(r.width), height: Math.round(r.height) });
  };
  useLayoutEffect(() => {
    const raf = requestAnimationFrame(show);
    return () => cancelAnimationFrame(raf);
  }, [url]);
  useEffect(() => {
    let timer = 0;
    const later = () => { clearTimeout(timer); timer = setTimeout(show, PREVIEW_DEBOUNCE_MS); };
    window.addEventListener('resize', later);
    const ro = new ResizeObserver(later);
    ro.observe(box.current);
    return () => { clearTimeout(timer); window.removeEventListener('resize', later); ro.disconnect(); hostCall('host.preview.hide', {}); };
  }, []);
  useEffect(() => {
    document.body.classList.add('ss-preview-on');
    return () => document.body.classList.remove('ss-preview-on');
  }, []);
  const mock = transportName() === 'mock';
  return html`<div class="ss-preview-box" ref=${box}>
    <span class="ss-preview-ph muted">${previewUnsupported.value ? 'Sin vista previa en este programa.' : mock ? 'Aquí va la página de Songsterr (panel nativo del anfitrión).' : ''}</span></div>`;
}

// ---- Piezas ----------------------------------------------------------------------------------

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const arrow = dir => html`<svg class="ss-arrow" aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">${dir === 'right' ? html`<path d="M5 12h14M13 6l6 6-6 6"/>` : html`<path d="M19 12H5M11 6l-6 6 6 6"/>`}</svg>`;
const radio = on_ => html`<svg class=${'ss-radio' + (on_ ? ' on' : '')} aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <circle cx="12" cy="12" r="9"/>${on_ ? html`<circle cx="12" cy="12" r="5" fill="currentColor" stroke="none"/>` : null}</svg>`;
const Busy = ({ text }) => html`<div class="ss-busy"><span class="spinner" aria-hidden="true"></span><span>${text}</span></div>`;

const confidenceClass = v => (v == null ? 'muted' : v >= GOOD_CONFIDENCE ? 'good' : v >= FAIR_CONFIDENCE ? 'fair' : 'bad');
const confText = text => text ?? 'sin medir';

/// «E A D G B E» de la cuerda más grave a la más aguda (el núcleo manda `tuningText`; esta es la alternativa si falta).
const tuningText = t => (t.tuningText ?? (t.tuning?.length ? [...t.tuning].reverse().map(n => NOTE_NAMES[((n % 12) + 12) % 12]).join(' ') : '-'));

function IssueBox({ issue, retry }) {
  return html`<div class="ss-issue"><div class="ss-issue-msg">${issue.message}</div>
    ${issue.suggestion ? html`<div class="muted">${issue.suggestion}</div>` : null}
    ${issue.canRetry ? html`<div><button class="btn secondary ss-h32" onClick=${retry}>Reintentar</button></div>` : null}</div>`;
}

function Results({ s }) {
  const sel = s.selected;
  return html`<div class="ss-results">
    ${sel ? html`<div class="ss-detail"><div class="ss-detail-title">${sel.artist} · ${sel.title}</div>
        ${(sel.tracks ?? []).map(t => html`<div class="ss-track" key=${t.partId}>
          <span class="ss-t-name">${t.name}</span><span class="ss-t-inst muted">${t.instrument}</span><span class="ss-t-tun muted">${tuningText(t)}</span></div>`)}</div>`
      : s.loadingSongId != null ? html`<${Busy} text="Leyendo las pistas…" />`
      : s.detailIssue ? html`<${IssueBox} issue=${s.detailIssue} retry=${() => act('tab.songsterr.retry')} />` : null}
    <div class="muted">Otros resultados</div>
    <div class="ss-list" role="listbox" aria-label="Otros resultados">${(s.results ?? []).map(r => html`<button class=${'ss-row' + (r.selected ? ' on' : '')} key=${r.songId}
      role="option" aria-selected=${!!r.selected} onClick=${() => { previewOpen.value = true; act('tab.songsterr.select', { songId: r.songId }); }}>
      ${radio(r.selected)}<span class="ss-row-text">${r.artist} · ${r.title}</span></button>`)}</div></div>`;
}

function LinkField({ s }) {
  const [text, setText] = useState('');
  const trimmed = text.trim();
  const submit = () => { if (trimmed && !s.busy) act('tab.songsterr.link', { link: trimmed }); };
  return html`<div class="ss-link"><div class="ss-link-row">
      <input class="ss-input" value=${text} placeholder="O pega un enlace de Songsterr" aria-label="Enlace de Songsterr"
        onInput=${e => setText(e.currentTarget.value)} onKeyDown=${e => { if (e.key === 'Enter') { e.preventDefault(); submit(); } }} />
      <button class="btn secondary ss-h32" disabled=${!trimmed || !!s.busy} onClick=${submit}>Usar enlace</button></div>
    ${s.linkIssue ? html`<div class="ss-link-err">${s.linkIssue.message}</div>` : null}</div>`;
}

function Choosing({ s }) {
  const phase = s.search?.phase ?? 'idle';
  const selectedId = (s.results ?? []).find(r => r.selected)?.songId ?? s.selected?.songId ?? null;
  return html`<${Fragment_}>
    <div class="muted">Búsqueda: ${s.query}</div>
    ${phase === 'idle' || phase === 'searching' ? html`<div class="ss-center"><${Busy} text="Buscando en Songsterr…" /></div>`
      : phase === 'failed' ? html`<${IssueBox} issue=${s.search.issue ?? { message: 'No se pudo buscar.', canRetry: true }} retry=${() => act('tab.songsterr.retry')} /><div class="ss-grow"></div>`
      : html`<${Results} s=${s} />`}
    <${LinkField} s=${s} />
    <div class="ss-actions">
      <button class="btn secondary sm" onClick=${() => act('tab.songsterr.close')}>Cancelar</button><span class="ss-grow"></span>
      ${!previewOpen.value ? html`<button class="btn secondary sm" disabled=${selectedId == null} onClick=${() => { previewOpen.value = true; }}>Vista previa</button>` : null}
      <button class="btn secondary sm" onClick=${chooseAutomaticFromSheet}>Transcribir automáticamente</button>
      <button class="btn primary" disabled=${!s.canUse} onClick=${() => act('tab.songsterr.use')}>Usar esta</button></div></${Fragment_}>`;
}

function Working({ s }) {
  return html`<div class="ss-working"><div>${s.workingText}</div><div class="ss-bar"><${AccentBar} fraction=${null} /></div><div class="ss-grow"></div>
    <div class="ss-actions"><button class="btn secondary sm" onClick=${() => act('tab.songsterr.back')}>Cancelar</button></div></div>`;
}

function Failed({ s }) {
  return html`<${Fragment_}><${IssueBox} issue=${s.failure ?? { message: 'No se pudo importar.', canRetry: true }} retry=${() => act('tab.songsterr.retryImport')} />
    <div class="ss-grow"></div>
    <div class="ss-actions"><button class="btn secondary sm" onClick=${() => act('tab.songsterr.back')}>Volver</button><span class="ss-grow"></span>
      <button class="btn secondary sm" onClick=${chooseAutomaticFromSheet}>Transcribir automáticamente</button></div></${Fragment_}>`;
}

const trackValue = t => (t == null ? '' : String(t));
const toTrack = v => (v === '' ? null : Number(v));

function Picker({ label, value, choices, none, width, onChange }) {
  return html`<select class="ss-select" style=${`width:${width}px`} aria-label=${label} value=${trackValue(value)} onChange=${e => onChange(toTrack(e.currentTarget.value))}>
    <option value="" selected=${value == null}>${none}</option>
    ${(choices ?? []).map(c => html`<option value=${String(c.track)} selected=${c.track === value}>${c.label ?? c.name}</option>`)}</select>`;
}

function Conf({ track, confidence, text }) {
  return track == null ? null : html`<span class=${'ss-conf ' + confidenceClass(confidence)}>${confText(text)}</span>`;
}

function PairRow({ slot }) {
  if (slot.role === 'lead') {
    const solos = slot.solos ?? [];
    if (!solos.length) {
      return html`<div class="ss-pair"><span class="ss-p-name">${slot.name}</span>${arrow('right')}
        <span class="muted">Transcripción automática (el tema no tiene secciones de solo)</span></div>`;
    }
    return html`<div>${solos.map((so, k) => html`<div class="ss-pair" key=${k}>
      <span class="ss-p-name">${k === 0 ? slot.name : ''}</span>
      <span class="ss-solo">Solo ${k + 1} (${so.clock})</span>${arrow('left')}
      <${Picker} label=${`Solo ${k + 1}`} value=${so.track} choices=${so.choices} none="Ninguna" width=${200}
        onChange=${track => act('tab.songsterr.assign', { stemId: slot.stemId, track, solo: so.index ?? k })} />
      <span class="ss-grow"></span><${Conf} track=${so.track} confidence=${so.confidence} text=${so.confidenceText} /></div>`)}</div>`;
  }
  return html`<div class="ss-pair"><span class="ss-p-name">${slot.name}</span>${arrow('right')}
    <${Picker} label=${slot.name} value=${slot.track} choices=${slot.choices} none="Transcripción automática" width=${260}
      onChange=${track => act('tab.songsterr.assign', { stemId: slot.stemId, track })} />
    <span class="ss-grow"></span><${Conf} track=${slot.track} confidence=${slot.confidence} text=${slot.confidenceText} /></div>`;
}

function Pairing({ s }) {
  const p = s.pairing;
  if (!p) return null;
  const warnings = p.warnings ?? [];
  return html`<${Fragment_}>
    <div class="muted">${p.intro}</div>
    <div class="ss-pairs">${(p.slots ?? []).map(slot => html`<${PairRow} slot=${slot} key=${slot.stemId} />`)}</div>
    ${p.extraText ? html`<div class="muted">${p.extraText}</div>` : null}
    ${warnings.length ? html`<div class="ss-warnings">${warnings.map((w, i) => html`<div class="ss-warn" key=${i}>
      <span class="ss-warn-ic">${icon('warning', 14)}</span><span>${w}</span></div>`)}</div>` : null}
    <div class="ss-grow"></div>
    <div class="ss-actions">
      <button class="btn secondary sm" onClick=${() => act('tab.songsterr.back')}>Atrás</button>
      <button class="btn secondary sm" onClick=${() => act('tab.songsterr.allAutomatic')}>Todo automático</button><span class="ss-grow"></span>
      <button class="btn secondary sm" onClick=${() => act('tab.songsterr.close')}>Cancelar</button>
      <button class="btn primary" onClick=${accept}>Aceptar</button></div></${Fragment_}>`;
}

/// URL de la vista previa (Mac: `previewURL`): solo con ella abierta, en la búsqueda y con un resultado marcado.
function previewUrlOf(s) {
  if (!previewOpen.value || s.stage !== 'choosing') return null;
  const row = (s.results ?? []).find(r => r.selected);
  return row?.previewUrl ?? s.selected?.previewUrl ?? null;
}

export function SongsterrSheet() {
  const s = sheet.value;
  const [vw, setVw] = useState(window.innerWidth);
  useEffect(() => {
    const f = () => setVw(window.innerWidth);
    window.addEventListener('resize', f);
    return () => window.removeEventListener('resize', f);
  }, []);
  useEffect(() => {
    if (s) document.getElementById('ss-title')?.closest('.modal')?.setAttribute('aria-labelledby', 'ss-title');
  }, [!s]);
  if (!s) return null;
  const url = previewUrlOf(s);
  const avail = vw - 2 * WINDOW_MARGIN;
  const full = 2 * SHEET_PAD + LIST_WIDTH + (url ? SHEET_GAP + PREVIEW_WIDTH : 0) + 2;   // + borde
  const width = Math.min(full, avail);
  const listWidth = url ? Math.max(LIST_WIDTH_MIN, Math.min(LIST_WIDTH, width - 2 * SHEET_PAD - SHEET_GAP - 2 - 300)) : width - 2 * SHEET_PAD - 2;
  const body = s.stage === 'working' ? html`<${Working} s=${s} />` : s.stage === 'failed' ? html`<${Failed} s=${s} />`
    : s.stage === 'pairing' ? html`<${Pairing} s=${s} />` : html`<${Choosing} s=${s} />`;
  return html`<${Modal} title=${null} width=${width} labelledBy="ss-modal-title" onClose=${() => act('tab.songsterr.close')}>
    <div class="ss-sheet" style=${`--ss-sheet-h:${SHEET_HEIGHT}px`}>
      <div class="ss-col" style=${url ? `width:${listWidth}px` : undefined}>
        <h2 class="ss-title" id="ss-title">Tablatura de Songsterr</h2>${body}</div>
      ${url ? html`<div class="ss-col ss-preview">
        <div class="ss-preview-head"><b>Vista previa</b><span class="ss-grow"></span>
          <button class="btn primary ss-h32p" disabled=${!s.canUse} onClick=${() => act('tab.songsterr.use')}>Usar esta</button>
          <button class="btn secondary ss-h32" onClick=${() => { previewOpen.value = false; }}>Cerrar</button></div>
        <${PreviewBox} url=${url} /></div>` : null}
    </div></${Modal}>`;
}
