// Secciones de Backing (SectionBoxes.swift, SectionPopover, SectionMenu, SectionKeyMonitor y SectionApplyButtons del Mac):
// marcar el bucle como sección o solo, selección con asas (el arrastre está en section-drag.js), ventana de la sección
// (nombre, color, solo, bordes ◀ ▶, bucle, eliminar), menú contextual, Supr/Esc y «Descartar» / «Aplicar». Los cambios son
// locales (`study.sections`) hasta `study.applySections`.
import { signal, effect } from '@preact/signals';
import { Fragment } from 'preact';
import { html } from '../html.js';
import { useState, useRef, useEffect } from 'preact/hooks';
import { icon } from '../icons.js';
import {
  study, transport, pos, markSection, updateSection, nudgeSectionEdge, deleteSection, applySections, discardSections,
  setLoop, seek, play, chordsExpanded,
} from './store.js';
import { selectedSection } from './section-drag.js';
import { chordEditMode } from './chord-editor.js';
import { PopupMenu } from '../ui.js';
import { SECTION_PALETTE } from './model.js';
import { Popover } from './chord-editor.js';

/// Mac (SectionPopover.suggestions).
const SUGGESTIONS = ['Intro', 'Estrofa', 'Estribillo', 'Puente', 'Final'];

/// Sección con la ventana abierta: `{ id, x, y }` (punto de anclaje en la ventana).
export const sectionPanel = signal(null);
/// Mac (SectionSelection.select): seleccionar (asas) y abrir su ventana.
export const openSectionPanel = (id, x, y) => { selectedSection.value = id; sectionPanel.value = { id, x, y }; };
const closeSectionPanel = () => { sectionPanel.value = null; };
/// Mac (SectionSelection.clear).
const clearSelection = () => { selectedSection.value = null; sectionPanel.value = null; };
const removeSection = id => { clearSelection(); deleteSection(id); };

/// Menú contextual abierto: `{ id, x, y }`.
const sectionMenu = signal(null);
export const openSectionMenu = (id, x, y) => { sectionMenu.value = { id, x, y }; };

// Mac (BackingTimelineCard): cambiar el modo edición limpia la selección; plegar/expandir cierra la ventana.
{
  let edit = chordEditMode.peek(), expanded = chordsExpanded.peek();
  effect(() => {
    const e = chordEditMode.value, x = chordsExpanded.value;
    if (e !== edit) clearSelection();
    else if (x !== expanded) sectionPanel.value = null;
    edit = e; expanded = x;
  });
}

// Mac (SectionKeyMonitor): Supr / Retroceso borran la sección seleccionada y Esc la deselecciona (si no hay ventana abierta),
// salvo escribiendo en un campo o con otro menú/diálogo delante. Solo con la tira o la rejilla en pantalla.
document.addEventListener('keydown', e => {
  const id = selectedSection.value;
  if (!id || e.ctrlKey || e.metaKey || e.altKey) return;
  const t = e.target;
  if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
  if (!document.querySelector('.strip-canvas, .grid-canvas') || document.querySelector('.menu, .modal, .popover')) return;
  if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); removeSection(id); }
  else if (e.key === 'Escape' && !sectionPanel.value) { e.preventDefault(); clearSelection(); }
});

const glyph = body => html`<svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
/// Mac: `rectangle.dashed`, `guitars.fill` y `repeat` (SF Symbols), aproximados.
const DASHED = glyph(html`<rect x="3" y="5" width="18" height="14" rx="2.5" stroke-dasharray="3.2 3"/>`);
const GUITARS = glyph(html`<circle cx="8" cy="16" r="4.5" fill="currentColor"/><path d="M11 13l8-8M17 3l4 4"/>`);
const REPEAT = glyph(html`<path d="M17 2l4 4-4 4M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4M21 13v2a3 3 0 0 1-3 3H3"/>`);

/// m:ss.d (SectionPopover.precise).
const precise = s => { const t = Math.max(s, 0), m = Math.floor(t / 60); return `${m}:${(t - m * 60).toFixed(1).padStart(4, '0')}`; };

/// Marca el bucle activo y abre al momento la ventana de la sección nueva (Mac: BackingTimelineCard.markLoop).
async function markLoop(solo, e) {
  const loop = transport.value?.loop;
  if (!loop) return;
  const r = e.currentTarget.getBoundingClientRect();
  const es = await markSection(loop.start, loop.end, solo);
  if (es?.added) openSectionPanel(es.added, r.left, r.bottom + 6);
}

/// Botones de la cabecera de la tarjeta: «Marcar sección» / «Marcar como solo» (con bucle y acordes) y «Descartar» / «Aplicar»
/// (solo con secciones sin aplicar).
export function SectionTools({ editMode, hasChords }) {
  const loop = transport.value?.loop;
  const unapplied = !!study.value?.unappliedSections;
  return html`<span class="section-tools">
    ${!editMode && loop && hasChords ? html`
      <button class="btn secondary xs" title="Marca el bucle como una sección" onClick=${e => markLoop(false, e)}>${DASHED}Marcar sección</button>
      <button class="btn secondary xs solo" title="Marca el bucle como un solo: sus guitarras se separan al aplicar"
        onClick=${e => markLoop(true, e)}>${GUITARS}Marcar como solo</button>` : null}
    ${unapplied ? html`
      <button class="btn secondary sec-discard" title="Vuelve a las secciones guardadas" onClick=${() => { closeSectionPanel(); discardSections(); }}>Descartar</button>
      <button class="btn primary sec-apply" title="Guarda las secciones. Las pistas de guitarra se rehacen, en segundo plano, solo si cambian los solos"
        onClick=${() => applySections()}>Aplicar</button>` : null}
  </span>`;
}

function Swatches({ s }) {
  if (s.solo) return html`<div class="prow sec-row"><span class="sec-label">Color</span><span class="swatch on" style="background:#F2A33A"></span>
    <span class="muted small">Los solos van en naranja</span></div>`;
  return html`<div class="prow sec-row"><span class="sec-label">Color</span>
    ${SECTION_PALETTE.map((c, i) => {
      const cur = s.color ?? s.paletteIndex ?? 0;
      return html`<button key=${i} class=${'swatch' + (cur === i ? ' on' : '')} style=${`background:${c}`} aria-label=${'Color ' + (i + 1)}
        aria-pressed=${cur === i} onClick=${() => updateSection(s.id, { color: s.color === i ? null : i })}></button>`;
    })}</div>`;
}

function EdgeRow({ s, start }) {
  const t = start ? s.start : s.end;
  const nudge = (forward, e) => nudgeSectionEdge(s.id, start, forward, e.altKey);
  return html`<div class="prow sec-row"><span class="sec-label">${start ? 'Inicio' : 'Fin'}</span>
    <button class="pchip nudge" aria-label=${`${start ? 'Inicio' : 'Fin'} antes`} onClick=${e => nudge(false, e)}>${icon('chevronLeft', 12)}</button>
    <span class="sec-time">${precise(t)}</span>
    <button class="pchip nudge fwd" aria-label=${`${start ? 'Inicio' : 'Fin'} después`} onClick=${e => nudge(true, e)}>${icon('chevronLeft', 12)}</button></div>`;
}

function PanelBody({ s }) {
  const [draft, setDraft] = useState(s.name);
  const live = useRef(draft);
  live.current = draft;
  // Mac (SectionBoxes): el nombre por defecto sigue a la marca de solo solo si el borrador no se ha tocado.
  const follow = useRef(false);
  useEffect(() => { setDraft(s.name); follow.current = false; }, [s.id]);
  useEffect(() => { if (follow.current) { follow.current = false; setDraft(s.name); } }, [s.name]);
  const toggleSolo = on => { follow.current = live.current === s.name; updateSection(s.id, { solo: on }); };
  const commit = () => { if (live.current !== s.name) return updateSection(s.id, { name: live.current }); };
  const done = async () => { await commit(); closeSectionPanel(); };
  const listen = () => {
    setLoop(s.start, s.end, s.name);
    seek(s.start);
    if (!pos.playing) play();
  };
  PanelBody.commit = commit;
  return html`<div class="section-panel">
    <div class="pop-title">${s.solo ? 'Solo' : 'Sección'}</div>
    <input class="sec-input" type="text" aria-label="Nombre" value=${draft} autofocus ref=${el => el && !el.__f && (el.__f = 1, setTimeout(() => el.focus(), 0))}
      onInput=${e => setDraft(e.currentTarget.value)} onKeyDown=${e => { if (e.key === 'Enter') done(); }} />
    <div class="sec-suggest">${SUGGESTIONS.map(n => html`<button key=${n} class=${'pchip' + (draft === n ? ' on' : '')} onClick=${() => setDraft(n)}>${n}</button>`)}</div>
    <${Swatches} s=${s} />
    <label class="switch sec-solo">Solo<input type="checkbox" role="switch" checked=${s.solo} onChange=${e => toggleSolo(e.currentTarget.checked)} /></label>
    <div class="psep"></div>
    <${EdgeRow} s=${s} start=${true} />
    <${EdgeRow} s=${s} start=${false} />
    <div class="muted small">◀ ▶ mueven por acorde · Alt por compás</div>
    <div class="prow between sec-actions">
      <button class="btn secondary xs" onClick=${listen}>${REPEAT}Escuchar en bucle</button>
      <button class="btn secondary xs danger" onClick=${() => removeSection(s.id)}>Eliminar</button>
    </div>
    <div class="prow sec-done"><span class="grow"></span><button class="btn primary xs" onClick=${done}>Hecho</button></div>
  </div>`;
}

/// Mac (SectionMenu): «Renombrar y ajustar…», «Marcar como solo» / «Quitar marca de solo», separador, «Eliminar sección».
function SectionMenu() {
  const m = sectionMenu.value;
  const s = m && (study.value?.sections ?? []).find(x => x.id === m.id);
  if (!s) return null;
  const items = [
    { label: 'Renombrar y ajustar…', onSelect: () => openSectionPanel(s.id, m.x, m.y) },
    { label: s.solo ? 'Quitar marca de solo' : 'Marcar como solo', onSelect: () => updateSection(s.id, { solo: !s.solo }) },
    'sep',
    { label: 'Eliminar sección', danger: true, onSelect: () => removeSection(s.id) },
  ];
  return html`<${PopupMenu} key=${m.id} x=${m.x} y=${m.y} items=${items} onClose=${() => { sectionMenu.value = null; }} />`;
}

/// Ventana flotante de la sección abierta y menú contextual. Como el Mac: clic fuera, «Hecho» o Enter guardan el nombre;
/// Esc cierra sin tocarlo. Cerrar la ventana deja la sección seleccionada (con asas).
export function SectionPanel() {
  const p = sectionPanel.value;
  const s = p && (study.value?.sections ?? []).find(x => x.id === p.id);
  if (p && !s) queueMicrotask(closeSectionPanel);
  return html`<${Fragment}>
    ${s ? html`<${Popover} key=${p.id} x=${p.x} y=${p.y} label=${'Sección ' + s.name} onClose=${reason => { if (reason !== 'escape') PanelBody.commit?.(); closeSectionPanel(); }}>
      <${PanelBody} s=${s} /></${Popover}>` : null}
    <${SectionMenu} /></${Fragment}>`;
}
