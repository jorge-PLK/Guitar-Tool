// Rejilla de acordes por compases en canvas (ChordGridView del Mac): filas de 4 compases (8 si cabe), un pulso por celda,
// secciones como cajas (seleccionables, con asas: SectionGridBoxes.swift), cursor por compás/pulso y autoscroll a la fila
// actual. Clic = saltar; arrastrar = bucle; asa de la sección seleccionada = mover su borde.
import { html } from '../html.js';
import { Fragment } from 'preact';
import { useRef, useMemo, useState, useEffect } from 'preact/hooks';
import { colors, font, roundRect, fitText, useCanvas } from './canvas.js';
import { pos, study } from './store.js';
import { chordEditMode, ChordEditor, Popover } from './chord-editor.js';
import { chordName, transposed, isChord } from './chords.js';
import { buildGrid, barIndexAt, sectionTint, snapRange } from './model.js';
import { hexA } from './strip.js';
import { selectedSection, startEdgeDrag, inHandle, drawHandle, drawSectionLabel } from './section-drag.js';
import { openSectionMenu } from './sections.js';

// Medidas de ChordGridView.swift.
const LABEL_W = 84, ROW_H = 46, ROW_SPACING = 4, SECTION_GUTTER = 18, BAR_GAP = 4;
/// Ancho mínimo de un compás para pasar de 4 a 8 por fila.
const MIN_BAR_W_FOR_8 = 112;
const VISIBLE_ROWS = 4;
const CLICK_SLOP = 4;
/// Mac: mantener pulsada una cabecera de sección (0,5 s) activa o quita su bucle.
const LONG_PRESS_MS = 500;
const ROW_PITCH = SECTION_GUTTER + ROW_H + ROW_SPACING;
export const GRID_HEIGHT = VISIBLE_ROWS * (SECTION_GUTTER + ROW_H) + (VISIBLE_ROWS - 1) * ROW_SPACING;
/// Mac (GridSectionBoxes.inset): cuánto sobresale la caja de las celdas, a los lados y por debajo.
const BOX_INSET = 2;
const BOX_H = SECTION_GUTTER + ROW_H + BOX_INSET;

/// Marco (x) de un pulso: la celda `k` de `n` del compás `c` de la fila (Mac: ChordGridGeometry.cellFrame).
const cellX = (c, k, n, barW) => { const cw = (barW - BAR_GAP) / n, x = LABEL_W + c * barW + k * cw; return [x, x + cw]; };

/// Mac (GridSectionBoxes.pieces): un trozo de caja por fila, de la primera a la última celda cuyo punto medio cae dentro de
/// la sección. Coordenadas del contenido (y = 0 arriba de la primera fila).
function pieces(s, bars, perRow, barW) {
  const out = [];
  for (let r = 0; r * perRow < bars.length; r++) {
    let lo = Infinity, hi = -Infinity;
    for (let c = 0; c < perRow; c++) {
      const bar = bars[r * perRow + c];
      if (!bar) break;
      bar.cells.forEach((cell, k) => {
        const mid = (cell.time + cell.end) / 2;
        if (s.start <= mid && mid < s.end) { const [a, b] = cellX(c, k, bar.cells.length, barW); lo = Math.min(lo, a); hi = Math.max(hi, b); }
      });
    }
    if (lo <= hi) out.push({ row: r, x0: lo - BOX_INSET, x1: hi + BOX_INSET, y0: r * ROW_PITCH });
  }
  return out;
}

/// Mac (GridSectionBoxes.cells): pulsos con la franja de la fila entera en vertical; el límite de acorde dibujado es el inicio
/// del acorde en las celdas donde cambia (y en la primera).
function dragCells(bars, perRow, barW, chords) {
  const out = [];
  bars.forEach((bar, i) => {
    const r = Math.floor(i / perRow), c = i % perRow;
    bar.cells.forEach((cell, k) => {
      const [x0, x1] = cellX(c, k, bar.cells.length, barW);
      const shows = cell.isChange || !out.length;
      out.push({ row: r, x0, x1, y0: r * ROW_PITCH, y1: r * ROW_PITCH + ROW_PITCH - ROW_SPACING, time: cell.time, end: cell.end,
        chordStart: shows ? (cell.chord != null ? chords[cell.chord].start : cell.time) : null });
    });
  });
  return out;
}

export function ChordGrid({ chords, sections, analysis, transpose, loop, onSeek, onLoop, onSection }) {
  const grid = useMemo(() => buildGrid(analysis, chords), [analysis, chords]);
  const st = useRef({ scrollY: 0, lastRow: -1, perRow: 4, width: 0, drag: null, g: null });
  const drag = useRef(null);
  const preview = useRef(null);    // secciones con el borde en arrastre (vista previa), o null
  const props = useRef(null);
  const edit = chordEditMode.value;
  const selected = selectedSection.value;
  const [ed, setEd] = useState(null);                  // editor abierto: { time (pulso pulsado), x, y }
  const segIdx = ed ? chords.findIndex(c => c.start <= ed.time + 1e-6 && ed.time < c.end) : -1;   // sigue al tramo tras editarlo
  props.current = { analysis, onSeek, onLoop, onSection, loop, grid, chords, edit, segIdx, sections, selected };

  const draw = (ctx, w, h) => {
    const C = colors();
    const S = st.current;
    if (!grid) {
      ctx.fillStyle = C.muted; ctx.font = font(13); ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText('Sin rejilla de compases todavía.', w / 2, h / 2);
      return;
    }
    const perRow = (w - LABEL_W) / 8 >= MIN_BAR_W_FOR_8 ? 8 : 4;
    const barW = (w - LABEL_W) / perRow, drawnBarW = barW - BAR_GAP;
    S.perRow = perRow; S.width = w;
    const bars = grid.bars;
    const rowsCount = Math.ceil(bars.length / perRow);
    const t = pos.seconds;
    const curBar = barIndexAt(bars, t);
    const curRow = Math.floor(curBar / perRow);
    const maxScroll = Math.max(rowsCount * ROW_PITCH - ROW_SPACING - h, 0);
    if (S.lastRow !== curRow || S.lastPer !== perRow) {   // autoscroll: la fila actual al centro cuando cambia
      S.lastRow = curRow; S.lastPer = perRow;
      S.scrollY = curRow * ROW_PITCH + SECTION_GUTTER + ROW_H / 2 - h / 2;
    }
    S.scrollY = Math.min(Math.max(S.scrollY, 0), maxScroll);
    const dr = drag.current;
    const lp = dr ? [dr[0], dr[1]] : (loop ? [loop.start, loop.end] : null);

    const r0 = Math.max(Math.floor(S.scrollY / ROW_PITCH) - 0, 0);
    const r1 = Math.min(Math.ceil((S.scrollY + h) / ROW_PITCH), rowsCount - 1);
    ctx.textBaseline = 'middle';
    S.boxes = [];
    S.barW = barW;
    for (let r = r0; r <= r1; r++) {
      const y0 = r * ROW_PITCH - S.scrollY;             // arriba de la franja de secciones
      const y = y0 + SECTION_GUTTER;
      ctx.font = font(11); ctx.fillStyle = C.muted; ctx.textAlign = 'left';
      ctx.fillText('c. ' + bars[r * perRow].number, 0, y + ROW_H / 2);
      for (let c = 0; c < perRow; c++) {
        const bar = bars[r * perRow + c];
        if (!bar) break;
        const x = LABEL_W + c * barW;
        const isCur = bar.start <= t + 1e-6 && t < bar.end;
        roundRect(ctx, x + 0.5, y + 0.5, drawnBarW - 1, ROW_H - 1, 8);
        ctx.fillStyle = isCur ? C.accentBg : C.field; ctx.fill();
        ctx.strokeStyle = isCur ? C.accent : C.fieldLine; ctx.lineWidth = 1; ctx.stroke();
        const cw = drawnBarW / bar.cells.length;
        bar.cells.forEach((cell, k) => {
          const cx = x + k * cw;
          const inLoop = lp && (cell.time + cell.end) / 2 >= lp[0] && (cell.time + cell.end) / 2 <= lp[1];
          if (inLoop) { roundRect(ctx, cx + 1, y + 3, cw - 2, ROW_H - 6, 6); ctx.fillStyle = 'rgba(242,163,58,0.28)'; ctx.fill(); }
          const named = k === 0 || cell.isChange;
          const real = isChord(cell.label);
          const label = named ? chordName(transposed(cell.label, transpose)) : '·';
          ctx.font = font(named ? 14 : 13, named ? 700 : 400);
          ctx.fillStyle = named && real ? C.text : C.muted;
          ctx.textAlign = named ? 'left' : 'center';
          const tx = named ? cx + 6 : cx + cw / 2;
          const txt = fitText(ctx, label, cw - (named ? 8 : 0));
          ctx.fillText(txt, tx, y + ROW_H / 2 + 0.5);
          if (isCur && cell.time <= t + 1e-6 && t < cell.end) {
            roundRect(ctx, cx + 4, y + ROW_H - 7, Math.max(cw - 8, 4), 3, 1.5);
            ctx.fillStyle = C.accent; ctx.fill();
          }
        });
      }
    }
    // Cajas de sección (un trozo por fila; Mac: SectionBoxPiece) y asas de la seleccionada en sus bordes reales.
    const sel = props.current.selected;
    S.handles = null;
    for (const s of preview.current ?? sections) {
      const ps = pieces(s, bars, perRow, barW);
      const tint = sectionTint(s, C.accent);
      const isLoop = loop && Math.abs(loop.start - s.start) < 0.01 && Math.abs(loop.end - s.end) < 0.01;
      const on = s.id === sel;
      ps.forEach((p, i) => {
        const y0 = p.y0 - S.scrollY;
        S.boxes.push({ s, x0: p.x0, x1: p.x1, y0, y1: y0 + SECTION_GUTTER });
        if (y0 > h || y0 + BOX_H < 0) return;
        roundRect(ctx, p.x0 + 0.5, y0 + 0.5, p.x1 - p.x0 - 1, BOX_H - 1, 9);
        ctx.fillStyle = hexA(tint, on ? 0.16 : 0.07); ctx.fill();
        ctx.strokeStyle = on ? tint : (isLoop ? C.accent : hexA(tint, 0.85)); ctx.lineWidth = on || isLoop ? 2 : 1.2; ctx.stroke();
        ctx.save();
        roundRect(ctx, p.x0 + 0.5, y0 + 0.5, p.x1 - p.x0 - 1, BOX_H - 1, 9); ctx.clip();
        ctx.fillStyle = s.solo ? C.accentBg : hexA(tint, 0.2);
        ctx.fillRect(p.x0, y0, p.x1 - p.x0, SECTION_GUTTER);
        ctx.restore();
        if (i === 0) {
          ctx.font = font(12, 600); ctx.textAlign = 'left';
          drawSectionLabel(ctx, s, p.x0 + 8, y0 + SECTION_GUTTER / 2 + 0.5, p.x1 - p.x0 - 16, s.solo ? C.accent : tint, fitText);
        }
      });
      if (on && ps.length) {
        const a = ps[0], z = ps[ps.length - 1];
        S.handles = { s, start: { x: a.x0, top: a.y0 + SECTION_GUTTER }, end: { x: z.x1, top: z.y0 + SECTION_GUTTER } };
        drawHandle(ctx, a.x0, a.y0 + SECTION_GUTTER - S.scrollY, BOX_H - SECTION_GUTTER, tint);
        drawHandle(ctx, z.x1, z.y0 + SECTION_GUTTER - S.scrollY, BOX_H - SECTION_GUTTER, tint);
      }
    }
  };

  const { ref, repaint } = useCanvas(draw);

  const hit = (cx, cy) => {
    const S = st.current, bars = props.current.grid?.bars;
    if (!bars) return null;
    const rowsCount = Math.ceil(bars.length / S.perRow);
    const barW = (S.width - LABEL_W) / S.perRow, drawnBarW = barW - BAR_GAP;
    const r = Math.min(Math.max(Math.floor((cy + S.scrollY) / ROW_PITCH), 0), rowsCount - 1);
    const x = Math.max(cx - LABEL_W, 0);
    const rowBars = bars.slice(r * S.perRow, r * S.perRow + S.perRow);
    const col = Math.min(Math.max(Math.floor(x / barW), 0), rowBars.length - 1);
    const n = rowBars[col].cells.length;
    const frac = Math.min(Math.max((x - col * barW) / drawnBarW, 0), 0.999999);
    return rowBars[col].cells[Math.min(Math.floor(frac * n), n - 1)];
  };
  /// Cabecera de sección bajo el punto (como el Mac, también en modo edición).
  const headerAt = (x, y) => st.current.boxes?.find(b => x >= b.x0 && x <= b.x1 && y >= b.y0 && y <= b.y1)?.s ?? null;
  const local = e => { const r = ref.current.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
  /// Punto del puntero en el contenido de la rejilla (con el desplazamiento vertical).
  const content = e => { const [x, y] = local(e); return { x, y: y + st.current.scrollY }; };
  /// Asa bajo el punto: { s, isStart } o null.
  const handleAt = p => {
    const H = st.current.handles;
    if (!H) return null;
    if (inHandle(p, H.start.x, H.start.top, BOX_H - SECTION_GUTTER)) return { s: H.s, isStart: true };
    if (inHandle(p, H.end.x, H.end.top, BOX_H - SECTION_GUTTER)) return { s: H.s, isStart: false };
    return null;
  };

  const down = e => {
    if (e.button !== 0 || !props.current.grid) return;
    const [x, y] = local(e);
    const h = handleAt(content(e));
    if (h) {
      const P = props.current, S = st.current;
      const edge = startEdgeDrag({ sections: P.sections, id: h.s.id, isStart: h.isStart, grab: content(e),
        cells: dragCells(P.grid.bars, S.perRow, S.barW, P.chords), bars: P.grid.bars.flatMap(b => [b.start, b.end]),
        onRemote: () => repaint() });
      if (edge) {
        ref.current._st = { edge };
        try { ref.current.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
        return;
      }
    }
    const section = headerAt(x, y);
    if (props.current.edit && !section) { ref.current._edit = hit(x, y); return; }   // en edición no se salta ni se marcan bucles
    const st0 = { x0: e.clientX, y0: e.clientY, a: hit(x, y), moved: false, section, long: false, timer: 0 };
    if (section) {
      // Mac: mantener pulsada la cabecera (0,5 s) activa o quita el bucle de la sección.
      st0.timer = setTimeout(() => {
        st0.long = true;
        const lp = props.current.loop;
        if (lp && Math.abs(lp.start - section.start) < 0.01 && Math.abs(lp.end - section.end) < 0.01) props.current.onLoop(null);
        else props.current.onLoop(section.start, section.end, section.name);
      }, LONG_PRESS_MS);
    }
    ref.current._st = st0;
    try { ref.current.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
  };
  const move = e => {
    const s = ref.current?._st;
    if (!s) { ref.current.style.cursor = handleAt(content(e)) ? 'col-resize' : ''; return; }
    if (s.edge) {
      const p = content(e);
      s.edge.track(p);
      if (s.edge.moved) { preview.current = s.edge.preview(p, e.altKey); repaint(); }
      return;
    }
    if (Math.hypot(e.clientX - s.x0, e.clientY - s.y0) >= CLICK_SLOP) {
      s.moved = true;
      clearTimeout(s.timer);
      if (s.long || props.current.edit) return;
      const b = hit(...local(e));
      if (s.a && b) { const lo = s.a.time <= b.time ? s.a : b, hi = s.a.time <= b.time ? b : s.a; drag.current = [lo.time, hi.end]; repaint(); }
    }
  };
  const up = e => {
    const es = ref.current?._st;
    if (es?.edge) {
      ref.current._st = null;
      const done = es.edge.commit(content(e), e.altKey);
      const clear = () => { preview.current = null; repaint(); };
      if (done) done.finally(clear); else clear();
      return;
    }
    if (props.current.edit && !ref.current._st) {
      const a = ref.current._edit; ref.current._edit = null;
      const b = a && hit(...local(e));
      if (a && b === a && a.chord != null) setEd({ time: a.time, x: e.clientX, y: e.clientY });
      return;
    }
    const s = ref.current?._st;
    if (!s) return;
    ref.current._st = null;
    clearTimeout(s.timer);
    if (s.long) return;
    if (!s.moved && s.section) { props.current.onSection?.(s.section.id, e.clientX, e.clientY + 12); return; }
    if (props.current.edit) return;
    const b = hit(...local(e));
    const range = drag.current;
    drag.current = null;
    repaint();
    if (!s.a || !b) return;
    if (!s.moved) { props.current.onSeek(s.a.time); return; }
    if (range) {
      const [a, z] = snapRange(props.current.analysis, range[0], range[1], e.altKey);
      props.current.onLoop(a, z, e.altKey ? 'compases' : 'acordes');
    }
  };
  const wheel = e => {
    e.preventDefault();
    st.current.scrollY += e.deltaY;
    repaint();
  };

  /// Clic derecho en la cabecera de un trozo de sección: su menú (Mac: SectionMenu, en todos los trozos).
  const menu = e => {
    const s = headerAt(...local(e));
    if (!s) return;
    e.preventDefault();
    openSectionMenu(s.id, e.clientX, e.clientY);
  };
  // Salir del modo edición cierra el editor; el editor resalta su tramo en el lienzo.
  useEffect(() => { if (!edit) setEd(null); }, [edit]);
  useEffect(() => { repaint(); }, [ed, chords, edit]);
  const seg = segIdx >= 0 ? chords[segIdx] : null;

  return html`<${Fragment}><canvas ref=${ref} class=${'grid-canvas' + (edit ? ' editing' : '')} style=${`height:${GRID_HEIGHT}px`} role="img"
    aria-label=${edit ? 'Rejilla de acordes en edición: clic en un acorde para cambiarlo o partirlo' : 'Rejilla de acordes por compases: clic para saltar, arrastrar para marcar un bucle'}
    onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onContextMenu=${menu}
    onPointerCancel=${() => { ref.current?._st?.edge?.dispose(); if (ref.current) ref.current._st = null; drag.current = null; preview.current = null; repaint(); }}
    onWheel=${wheel} />
    ${seg ? html`<${Popover} key=${ed.time} x=${ed.x + 8} y=${ed.y + 8} label="Editar acorde" onClose=${() => setEd(null)}>
      <${ChordEditor} seg=${seg} time=${ed.time} transpose=${transpose} beats=${analysis?.beats} overrides=${study.value?.chordOverrides}
        /></${Popover}>` : null}
  </${Fragment}>`;
}
