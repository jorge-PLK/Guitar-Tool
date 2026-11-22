// Línea de tiempo de Montaje (MontageTimelineView): tramo del vídeo, secciones, carril «Plano», un carril por parte
// (arrastrables para reordenar los recuadros), cortes arrastrables y cabezal. Todo en DOM con posiciones en %.
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import {
  snap, lanes, previewReady, cutMenu, sheetTake, framingOf, moveLane, addCut, moveCut, setCutPart, removeCut, clearCuts,
  rotateTake, seek, setScrubbing, onPosition, pos,
} from './store.js';
import { entries } from '../state.js';
import { AXIS_MARGIN_FRACTION, laneColor, fmtDur, clamp } from './model.js';

/// Medidas del Mac (MontageTimelineView).
const LABEL_WIDTH = 270, ROW_SPACING = 6, LANE_H = 30, SECTION_H = 24, BAND_H = 8, CUT_W = 8;
/// Mac (DragGesture minimumDistance: 4) del arrastre de un corte.
const CUT_DRAG_MIN = 4;
/// Movimiento mínimo para empezar a reordenar un carril.
const LANE_DRAG_MIN = 4;

const gripIcon = html`<svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>`;
// Mismo icono que «Rotar» de Grabar (SF Symbol rotate.right del Mac): cuadrado con flecha.
const rotateIcon = html`<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="9" width="11" height="11" rx="2"/><path d="M9 5.5h5a4 4 0 0 1 4 4v1"/><path d="M15.5 8.5l2.5 2.5 2.5-2.5"/></svg>`;
const checkIcon = html`<svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5 9-10"/></svg>`;

function axisOf(s, songDuration) {
  const spanDur = s.span.end - s.span.start;
  const songEnd = Math.max(songDuration || 0, s.span.end, 1);
  const margin = Math.max(spanDur * AXIS_MARGIN_FRACTION, s.barDuration || 0);
  const start = Math.max(0, s.span.start - margin), end = Math.min(songEnd, s.span.end + margin);
  return { start, end, dur: Math.max(end - start, 1) };
}

function LaneLabel({ lane, drag, setDrag, onDrop }) {
  const f = framingOf(lane.takeId);
  const down = e => {
    if (e.button !== 0 || e.target.closest('button')) return;
    const startY = e.clientY;
    let on = false;
    const rows = () => [...document.querySelectorAll('.mt-lane-label[data-lane]')];
    const over = y => {
      const rs = rows();
      for (const r of rs) { const b = r.getBoundingClientRect(); if (y >= b.top - ROW_SPACING / 2 && y <= b.bottom + ROW_SPACING / 2) return r.dataset.lane; }
      return y < rs[0].getBoundingClientRect().top ? rs[0].dataset.lane : rs[rs.length - 1].dataset.lane;
    };
    const move = ev => {
      if (!on && Math.abs(ev.clientY - startY) < LANE_DRAG_MIN) return;
      on = true;
      setDrag({ id: lane.id, over: over(ev.clientY) });
    };
    const up = ev => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', up);
      if (on) onDrop(lane.id, over(ev.clientY));
      setDrag(null);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);
  };
  const ids = lanes.value.map(l => l.id);
  const above = drag ? ids.indexOf(drag.id) > ids.indexOf(lane.id) : true;
  const target = drag && drag.over === lane.id && drag.id !== lane.id;
  return html`<div class=${'mt-lane-label' + (drag?.id === lane.id ? ' dragging' : '')} data-lane=${lane.id} onPointerDown=${down}>
    <span class="grip" title="Arrastra para reordenar los recuadros">${gripIcon}</span>
    <span class="name">${lane.partName}</span><span class="grow"></span>
    ${lane.presence.length === 0 ? html`<span class="tiny muted">Sin solos marcados</span>`
      : lane.hasVideo ? html`${f.status === 'analyzing' ? html`<span class="spinner mini" aria-hidden="true"></span>` : null}
        <button class="mt-mini" aria-label=${'Encuadre de ' + lane.partName} onClick=${() => { sheetTake.value = lane.takeId; }}>Encuadre</button>
        <button class=${'mt-mini sq' + (lane.rotation ? ' rot' : '')} aria-label=${'Rotar ' + lane.partName} title=${`Rotar 90° (ahora ${lane.rotation ?? 0}°)`}
          onClick=${() => rotateTake(lane.takeId)}>${rotateIcon}</button>`
      : html`<span class="tiny muted">Solo audio</span>`}
    ${target ? html`<span class=${'drop-line ' + (above ? 'top' : 'bottom')}></span>` : null}
  </div>`;
}

/// Parte elegible para un corte en `t`: con imagen en ese instante (aproximación con la toma; el contrato no da `cutEligibleParts`).
const eligible = (lane, cut) => cut.eligible ? cut.eligible.includes(lane.id) : lane.hasVideo && cut.time >= lane.take.start && cut.time < lane.take.end;

function CutMenu() {
  const m = cutMenu.value;
  const ref = useRef(null);
  const [at, setAt] = useState({ left: -999, top: -999 });
  const s = snap.value;
  const cut = s.cuts.find(c => c.id === m.id);
  useLayoutEffect(() => {
    const el = document.querySelector(`[data-cut="${m.id}"]`);
    const r = el?.getBoundingClientRect(), box = ref.current.getBoundingClientRect();
    const cx = r ? r.left + r.width / 2 : m.x ?? 0, top = r ? r.bottom + 8 : m.y ?? 0;
    setAt({ left: clamp(cx - box.width / 2, 8, window.innerWidth - box.width - 8), top: Math.min(top, window.innerHeight - box.height - 8) });
  }, [m.id, !!cut]);
  useEffect(() => {
    const close = () => { cutMenu.value = null; };
    const down = e => { if (!ref.current?.contains(e.target) && !e.target.closest?.('[data-cut]')) close(); };
    const key = e => { if (e.key === 'Escape') close(); };
    document.addEventListener('mousedown', down, true);
    document.addEventListener('keydown', key);
    return () => { document.removeEventListener('mousedown', down, true); document.removeEventListener('keydown', key); };
  }, []);
  if (!cut) { cutMenu.value = null; return null; }
  const choose = partId => { setCutPart(cut.id, partId); cutMenu.value = null; };
  const choice = (label, selected, onClick, ok = true, title) => html`<button class="mt-choice" disabled=${!ok} title=${title} onClick=${onClick}>
    <span class="ck">${selected ? checkIcon : null}</span><span>${label}</span></button>`;
  const cands = s.cutCandidates.map(id => lanes.value.find(l => l.id === id)).filter(Boolean);
  return html`<div class="mt-pop mt-cutmenu" ref=${ref} role="menu" style=${`left:${at.left}px;top:${at.top}px`}>
    <div class="small muted">Desde ${fmtDur(cut.time)} manda</div>
    ${cands.map(l => { const ok = eligible(l, cut);
      return html`${choice(l.partName, cut.partId === l.id, () => choose(l.id), ok, ok ? '' : `Sin toma en ${fmtDur(cut.time)}`)}`; })}
    ${choice('Automático', cut.partId == null, () => choose(null))}
    <div class="sep"></div>
    <button class="mt-choice danger" onClick=${() => { removeCut(cut.id); cutMenu.value = null; }}>Eliminar corte</button>
  </div>`;
}

export function Timeline() {
  const s = snap.value;
  const all = lanes.value;
  const nonSolo = all.filter(l => !l.isSolo);
  const entry = entries.value.find(e => e.id === s.projectId);
  const ax = axisOf(s, s.songDuration || entry?.duration);
  const x = t => ((t - ax.start) / ax.dur) * 100;
  const showCuts = s.isSingleShot;
  const missing = s.missingParts ?? [];
  const [drag, setDrag] = useState(null);
  const [dragCut, setDragCut] = useState(null);   // { id, time }
  const track = useRef(null), head = useRef(null);
  const colorOf = l => laneColor(l, Math.max(nonSolo.findIndex(n => n.id === l.id), 0));
  const partColors = Object.fromEntries(all.map(l => [l.id, colorOf(l)]));
  const segs = s.segments ?? [];
  const gaps = segs.slice(1).map((g, i) => [segs[i].end, g.start]);
  const rows = all.length + missing.length + (showCuts ? 1 : 0);
  const height = BAND_H + SECTION_H + rows * LANE_H + (rows + 1) * ROW_SPACING;

  useEffect(() => {
    const paint = () => { if (head.current) head.current.style.left = `calc(${x(pos.seconds)}% - 1px)`; };
    paint();
    return onPosition(paint);
  }, [ax.start, ax.dur]);

  const timeAt = e => { const r = track.current.getBoundingClientRect(); return ax.start + clamp((e.clientX - r.left) / r.width, 0, 1) * ax.dur; };
  const down = e => {
    if (e.button !== 0 || e.target.closest('[data-cut]') || e.target.closest('.mt-plane-hit')) return;
    try { track.current.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
    setScrubbing(true);
    track.current.dataset.scrub = '1';
    seek(timeAt(e), { final: false });
  };
  const move = e => { if (track.current.dataset.scrub) seek(timeAt(e), { final: false }); };
  const up = e => { if (!track.current.dataset.scrub) return; delete track.current.dataset.scrub; setScrubbing(false); seek(timeAt(e)); };

  const planeClick = async e => {
    const t = timeAt(e), cx = e.clientX, cy = e.clientY;
    const id = await addCut(t);
    if (id) cutMenu.value = { id, x: cx, y: cy };
  };
  const addAtHead = async () => { const id = await addCut(pos.seconds); if (id) cutMenu.value = { id }; };

  const cutDown = (cut, e) => {
    if (e.button !== 0) return;
    e.stopPropagation();
    const sx = e.clientX;
    let moved = false;
    const mv = ev => {
      if (!moved && Math.abs(ev.clientX - sx) < CUT_DRAG_MIN) return;
      moved = true;
      setDragCut({ id: cut.id, time: timeAt(ev) });
    };
    const end = ev => {
      window.removeEventListener('pointermove', mv);
      window.removeEventListener('pointerup', end);
      window.removeEventListener('pointercancel', end);
      if (moved) { const t = timeAt(ev); moveCut(cut.id, t).then(() => setDragCut(null)); }
      else cutMenu.value = { id: cut.id };
    };
    window.addEventListener('pointermove', mv);
    window.addEventListener('pointerup', end);
    window.addEventListener('pointercancel', end);
  };

  const bar = s.barDuration ?? 0;
  // Paridad con el Mac: allí el ancho de los fundidos es `x(bar)` (posición absoluta del compás, no su duración), con mínimo 2 pt.
  const fadeIn = segs[0]?.fadeIn, fadeOut = segs[segs.length - 1]?.fadeOut;
  const planeSpans = (s.planeShots ?? []).map(p => ({ ...p, a: Math.max(p.start, ax.start), b: Math.min(p.end, ax.end) })).filter(p => p.b > p.a);
  const nameOf = id => all.find(l => l.id === id)?.partName;

  return html`<section class="card mt-card mt-timeline" aria-label="Línea de tiempo del montaje">
    <div class="mt-tl-main">
      <div class="mt-tl-labels" style=${`width:${LABEL_WIDTH}px`}>
        <div class="tiny muted band-label">Tramo del vídeo</div>
        <div style=${`height:${SECTION_H}px`}></div>
        ${showCuts ? html`<div class="mt-plane-label"><span class="name">Plano</span><span class="grow"></span>
          <button class="mt-mini" disabled=${!previewReady.value} title="Crea un corte en la posición de la vista previa" onClick=${addAtHead}>Añadir corte</button></div>` : null}
        ${all.map(l => html`<${LaneLabel} key=${l.id} lane=${l} drag=${drag} setDrag=${setDrag} onDrop=${(id, to) => { if (id !== to) moveLane(id, to); }} />`)}
        ${missing.map(n => html`<div class="mt-missing-label" key=${n}><span class="name">${n}</span><span class="grow"></span><span class="tiny muted">Sin toma</span></div>`)}
      </div>
      <div class="mt-track" ref=${track} style=${`height:${height}px`} onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onPointerCancel=${up}>
        <div class="mt-track-rows">
          <div class="mt-band">
            <i class="fill" style=${`left:${x(s.span.start)}%;width:${x(s.span.end) - x(s.span.start)}%`}></i>
            ${fadeIn ? html`<i class="fade in" style=${`left:${x(s.span.start)}%;width:max(2px, ${x(bar)}%)`}></i>` : null}
            ${fadeOut ? html`<i class="fade out" style=${`left:${x(s.span.end - bar)}%;width:max(2px, ${x(bar)}%)`}></i>` : null}
          </div>
          <div class="mt-sections">
            ${(s.sections ?? []).filter(z => Math.min(z.end, ax.end) > Math.max(z.start, ax.start)).map(z => {
              const a = Math.max(z.start, ax.start), b = Math.min(z.end, ax.end);
              return html`<span class=${'sec' + (z.solo ? ' solo' : '')} key=${z.id} style=${`left:${x(a)}%;width:calc(${x(b) - x(a)}% - 2px)`}>${z.name}</span>`;
            })}
          </div>
          ${showCuts ? html`<div class="mt-lane mt-plane" role="group" aria-label=${`Plano: ${s.cuts.length} ${s.cuts.length === 1 ? 'corte' : 'cortes'}`}>
            ${planeSpans.map((p, i) => { const c = p.partId ? partColors[p.partId] : null;
              const st = `left:${x(p.a)}%;width:calc(${x(p.b) - x(p.a)}% - 1px)`;
              return html`<i key=${i} class=${'shot' + (p.black ? ' black' : c ? '' : ' auto')} style=${st + (c ? (p.black ? `;--c:${c}` : `;background:${c}d9`) : '')}></i>`; })}
            <div class="mt-plane-hit" onClick=${planeClick}></div>
            ${s.cuts.map(c => { const t = dragCut?.id === c.id ? dragCut.time : c.time;
              const tip = c.covered ? fmtDur(t) : `${fmtDur(t)} · ${nameOf(c.partId) ?? 'La parte'} no tiene toma aquí: se ve el automático`;
              return html`<i key=${c.id} class=${'cut' + (c.covered ? '' : ' warn')} data-cut=${c.id} title=${tip}
                style=${`left:calc(${x(t)}% - ${CUT_W / 2}px)`} onPointerDown=${e => cutDown(c, e)}></i>`; })}
          </div>` : null}
          ${all.map(l => { const c = colorOf(l);
            return html`<div class="mt-lane" key=${l.id} role="img" aria-label=${`${l.partName}: ${l.presence.length} ${l.presence.length === 1 ? 'tramo' : 'tramos'} en pantalla`}>
              <i class="take" style=${`left:${x(l.take.start)}%;width:${x(l.take.end) - x(l.take.start)}%;border-color:${c}99`}></i>
              ${l.presence.map((p, i) => html`<i class="pres" key=${i} style=${`left:${x(p.start)}%;width:${x(p.end) - x(p.start)}%;background:${l.hasVideo ? c : c + '59'}`}></i>`)}
            </div>`; })}
          ${missing.map(n => html`<div class="mt-lane" key=${n}></div>`)}
        </div>
        <i class="dim" style=${`left:0;width:${x(s.span.start)}%`}></i>
        <i class="dim" style=${`left:${x(s.span.end)}%;right:0`}></i>
        ${gaps.map((g, i) => html`<i class="gap" key=${i} style=${`left:${x(g[0])}%;min-width:2px;width:${x(g[1]) - x(g[0])}%`}></i>`)}
        <i class="head" ref=${head}></i>
      </div>
    </div>
    <div class="mt-tl-note"><span>Barra llena = en pantalla; el contorno discontinuo es lo grabado; lo rayado son huecos cortados. La solista solo aparece en el solo y su entrada empieza ${s.anticipationLabel} antes de la primera nota. Clic para mover la vista previa.${showCuts ? ' En el carril Plano, clic para añadir un corte (se ajusta al pulso), clic en una marca para elegir la guitarra y arrastra para moverla.' : ''}</span>
      <span class="grow"></span>
      ${showCuts && s.cuts.length ? html`<button class="mt-link" onClick=${clearCuts}>Quitar cortes</button>` : null}</div>
    ${cutMenu.value ? html`<${CutMenu} />` : null}
  </section>`;
}
