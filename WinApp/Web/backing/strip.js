// Tira de acordes plegada en canvas (BackingTimelineCard.chordStrip del Mac): chips de acorde con las secciones como
// cajas encima (seleccionables, con asas en los bordes: SectionBoxes.swift), compases numerados debajo. Como el Mac, la tira
// salta con animación al centrar el acorde actual cuando cambia (ScrollViewReader.scrollTo con withAnimation).
import { html } from '../html.js';
import { Fragment } from 'preact';
import { useRef, useState, useEffect } from 'preact/hooks';
import { colors, font, roundRect, fitText, useCanvas } from './canvas.js';
import { pos } from './store.js';
import { ChordEditor, Popover } from './chord-editor.js';
import { chordName, transposed, isChord } from './chords.js';
import { chordAt, sectionTint, snapRange } from './model.js';
import { selectedSection, startEdgeDrag, inHandle, drawHandle, drawSectionLabel } from './section-drag.js';
import { openSectionMenu } from './sections.js';

// Medidas del Mac (BackingTimelineCard / SectionBoxes): chip de 36 pt, mínimo 52 de ancho, hueco de 6 entre chips, cabecera de
// sección de 22 sobre los acordes, la caja sobresale 2, fila de 12 para el número de compás; alto total 40 + 22 + 3 + 2 + 12.
const HEAD_H = 22, CHIP_H = 36, CHIP_MIN_W = 52, CHIP_PAD = 6, CHIP_GAP = 6, INSET = 2, BAR_ROW_H = 12;
const CHIP_Y = HEAD_H + 3;
/// Alto de una caja de sección: hasta el pie de los chips más lo que sobresale (Mac: SectionBoxes.rect).
const BOX_H = CHIP_Y + CHIP_H + INSET;
export const STRIP_HEIGHT = 40 + HEAD_H + 3 + INSET + BAR_ROW_H;
/// Mac (barMatchTolerance): tolerancia al emparejar el inicio de un acorde con un primer tiempo si no hay BPM.
const BAR_MATCH_TOLERANCE = 0.05;

/// Mac (BackingTimelineCard.barNumbers): número de compás de los acordes que abren compás; tolerancia de medio pulso
/// (los cambios de acorde detectados no caen exactamente en el primer tiempo). Cada primer tiempo se usa una sola vez.
export function barNumbers(chords, downbeats, bpm) {
  const tol = bpm ? 30 / bpm : BAR_MATCH_TOLERANCE;
  const out = new Map();
  let d = 0;
  chords.forEach((c, i) => {
    while (d < downbeats.length && downbeats[d] < c.start - tol) d++;
    if (d < downbeats.length && Math.abs(downbeats[d] - c.start) <= tol) { out.set(i, d + 1); d++; }
  });
  return out;
}

/// Mac (SectionBoxes.x(at:)): x de un instante en la tira, interpolado dentro del chip que lo contiene; entre dos
/// chips, borde del siguiente (inicio) o del anterior (fin). La caja sigue los tiempos de la sección, no los acordes.
function xAtTime(chords, L, t, isStart) {
  let i = -1;
  if (isStart) i = chords.findIndex(c => c.end > t);
  else for (let k = chords.length - 1; k >= 0; k--) if (chords[k].start < t) { i = k; break; }
  if (i < 0) return null;
  const c = chords[i], span = c.end - c.start;
  const k = span > 0 ? Math.min(Math.max((t - c.start) / span, 0), 1) : (isStart ? 0 : 1);
  return L.xs[i] + L.ws[i] * k;
}
/// Mac (ChordGridView.clickSlop): menos de esto es un clic, no un arrastre.
const CLICK_SLOP = 4;
/// Mac: mantener pulsada una cabecera de sección (0,5 s) activa o quita su bucle.
const LONG_PRESS_MS = 500;
/// Mac: `withAnimation { proxy.scrollTo(c, anchor: .center) }` = animación por defecto de SwiftUI (muelle «smooth», sin
/// rebote, 0,5 s). Aquí, muelle críticamente amortiguado con ese periodo.
const SCROLL_SPRING_S = 0.5;
/// Al llegar a menos de esto (px) del destino, la animación termina.
const SCROLL_DONE_PX = 0.25;

/// Paso del muelle sin rebote: 0 → 1 en `t` segundos (respuesta de un sistema críticamente amortiguado de periodo `SCROLL_SPRING_S`).
const springStep = t => { const w = 2 * Math.PI / SCROLL_SPRING_S; return 1 - (1 + w * t) * Math.exp(-w * t); };

export function ChordStrip({ chords, sections, analysis, transpose, loop, edit, overrides, onSeek, onLoop, onSection }) {
  const [ed, setEd] = useState(null);              // editor abierto (modo edición): { i, x, y }
  useEffect(() => { if (!edit) setEd(null); }, [edit]);
  const lay = useRef({ key: null, xs: [], ws: [], total: 0, scroll: 0, width: 0 });
  const drag = useRef(null);       // { a, b } posiciones de acordes mientras se arrastra
  const preview = useRef(null);    // secciones con el borde en arrastre (vista previa), o null
  const props = useRef(null);
  const selected = selectedSection.value;
  props.current = { chords, sections, analysis, transpose, loop, edit, onSeek, onLoop, onSection, selected };

  const layout = (ctx) => {
    const L = lay.current;
    if (L.chordsRef === chords && L.tr === transpose) return L;
    ctx.font = font(14, 700);
    let x = INSET + 1;
    L.xs = []; L.ws = []; L.names = [];
    for (const c of chords) {
      const name = chordName(transposed(c.index, transpose));
      const w = Math.max(CHIP_MIN_W, ctx.measureText(name).width) + CHIP_PAD * 2;
      L.names.push(name); L.xs.push(x); L.ws.push(w);
      x += w + CHIP_GAP;
    }
    L.total = x - CHIP_GAP + INSET + 1;
    L.tr = transpose; L.chordsRef = chords;
    return L;
  };

  const draw = (ctx, w, h) => {
    const C = colors();
    const L = layout(ctx);
    L.width = w;
    const t = pos.seconds;
    const cur = chordAt(chords, t);
    // Mac: al cambiar el acorde actual, la tira se desplaza con animación hasta dejarlo centrado (sin acorde actual no se
    // mueve); al aparecer, salta sin animación. Entre saltos, la rueda (horizontal) la mueve a mano, como el ScrollView.
    const maxScroll = Math.max(L.total - w, 0);
    const centered = i => Math.min(Math.max(L.xs[i] + L.ws[i] / 2 - w / 2, 0), maxScroll);
    const now = performance.now() / 1000;
    if (cur >= 0 && (cur !== L.cur || L.chordsCur !== chords)) {
      if (L.cur === undefined || L.chordsCur !== chords) { L.scroll = centered(cur); L.anim = null; }
      else L.anim = { from: L.scroll, to: centered(cur), t0: now };
      L.cur = cur; L.chordsCur = chords;
    }
    if (L.anim) {
      const k = springStep(now - L.anim.t0);
      L.scroll = L.anim.from + (L.anim.to - L.anim.from) * k;
      if (Math.abs(L.anim.to - L.scroll) < SCROLL_DONE_PX) { L.scroll = L.anim.to; L.anim = null; } else repaint();
    }
    L.scroll = Math.min(Math.max(L.scroll, 0), maxScroll);
    ctx.save();
    ctx.translate(-L.scroll, 0);

    const dr = drag.current;
    const lp = dr ? [chords[Math.min(dr.a, dr.b)].start, chords[Math.max(dr.a, dr.b)].end] : (loop ? [loop.start, loop.end] : null);

    // Chips
    ctx.textBaseline = 'middle';
    for (let i = 0; i < chords.length; i++) {
      const x = L.xs[i], cw = L.ws[i];
      if (x + cw < L.scroll - 2 || x > L.scroll + w + 2) continue;
      const mid = (chords[i].start + chords[i].end) / 2;
      const inLoop = lp && mid >= lp[0] && mid <= lp[1];
      const on = i === cur;
      roundRect(ctx, x + 0.5, CHIP_Y + 0.5, cw - 1, CHIP_H - 1, 8);
      ctx.fillStyle = on ? C.accent : (inLoop ? 'rgba(242,163,58,0.22)' : C.field);
      ctx.fill();
      if (!on) { ctx.strokeStyle = inLoop ? C.accent : C.fieldLine; ctx.lineWidth = 1; ctx.stroke(); }
      ctx.font = font(14, 700);
      ctx.textAlign = 'center';
      ctx.fillStyle = on ? C.accentInk : (cur >= 0 && i < cur ? 'rgba(154,163,173,0.7)' : C.text);
      ctx.fillText(L.names[i], x + cw / 2, CHIP_Y + CHIP_H / 2 + 0.5);
    }

    // Número de compás bajo el chip que abre un compás.
    const bars = barNumbers(chords, analysis?.downbeats ?? [], analysis?.bpm);
    if (bars.size) {
      ctx.font = font(10, 400); ctx.textAlign = 'left'; ctx.fillStyle = C.muted;
      for (const [i, n] of bars) {
        if (L.xs[i] + L.ws[i] > L.scroll && L.xs[i] < L.scroll + w) ctx.fillText(String(n), L.xs[i] + 2, CHIP_Y + CHIP_H + BAR_ROW_H / 2);
      }
    }

    // Cajas de sección sobre los chips que envuelven (Mac: SectionBoxes.rect); la seleccionada, con asas en sus bordes.
    L.boxes = [];
    const sel = props.current.selected;
    for (const s of preview.current ?? sections) {
      if (!chords.length || !(s.end > chords[0].start && s.start < chords[chords.length - 1].end)) continue;
      const p0 = xAtTime(chords, L, s.start, true), p1 = xAtTime(chords, L, s.end, false);
      if (p0 == null || p1 == null) continue;
      const x0 = p0 - INSET, x1 = Math.max(p1 + INSET, x0 + 8);
      if (x1 < L.scroll || x0 > L.scroll + w) { L.boxes.push({ s, x0, x1 }); continue; }
      const tint = sectionTint(s, C.accent);
      const isLoop = loop && Math.abs(loop.start - s.start) < 0.01 && Math.abs(loop.end - s.end) < 0.01;
      const on = s.id === sel;
      // Mac (SectionBoxPiece): relleno 0,07 (0,16 seleccionada); contorno del color (seleccionada), naranja (bucle) o 0,85.
      roundRect(ctx, x0 + 0.5, 0.5, x1 - x0 - 1, BOX_H - 1, 9);
      ctx.fillStyle = hexA(tint, on ? 0.16 : 0.07); ctx.fill();
      ctx.strokeStyle = on ? tint : (isLoop ? C.accent : hexA(tint, 0.85)); ctx.lineWidth = on || isLoop ? 2 : 1.2; ctx.stroke();
      // Cabecera con el nombre.
      ctx.save();
      roundRect(ctx, x0 + 0.5, 0.5, x1 - x0 - 1, BOX_H - 1, 9); ctx.clip();
      ctx.fillStyle = s.solo ? C.accentBg : hexA(tint, 0.2);
      ctx.fillRect(x0, 0, x1 - x0, HEAD_H);
      ctx.restore();
      ctx.font = font(12, 600); ctx.textAlign = 'left';
      // El nombre se queda pegado al borde visible mientras la caja asoma.
      const tx = Math.min(Math.max(x0 + 8, L.scroll + 6), x1 - 40);
      drawSectionLabel(ctx, s, tx, HEAD_H / 2 + 0.5, x1 - tx - 8, s.solo ? C.accent : tint, fitText);
      L.boxes.push({ s, x0, x1 });
    }
    const sb = L.boxes.find(b => b.s.id === sel);
    if (sb) {
      const tint = sectionTint(sb.s, C.accent);
      drawHandle(ctx, sb.x0, HEAD_H, BOX_H - HEAD_H, tint);
      drawHandle(ctx, sb.x1, HEAD_H, BOX_H - HEAD_H, tint);
    }
    ctx.restore();
  };

  const { ref, repaint } = useCanvas(draw);

  const chipAt = (x) => {
    const L = lay.current, px = x + L.scroll;
    let best = -1, bd = Infinity;
    for (let i = 0; i < L.xs.length; i++) {
      if (px >= L.xs[i] && px <= L.xs[i] + L.ws[i]) return i;
      const d = Math.abs(L.xs[i] + L.ws[i] / 2 - px);
      if (d < bd) { bd = d; best = i; }
    }
    return best;
  };
  const sectionAt = (x) => {
    const px = x + lay.current.scroll;
    return lay.current.boxes?.find(b => px >= b.x0 && px <= b.x1)?.s ?? null;
  };

  /// Punto del puntero en el contenido de la tira (con el desplazamiento).
  const content = e => { const r = ref.current.getBoundingClientRect(); return { x: e.clientX - r.left + lay.current.scroll, y: e.clientY - r.top }; };
  /// Asa bajo el punto (solo la sección seleccionada tiene asas): { s, isStart } o null.
  const handleAt = p => {
    const b = lay.current.boxes?.find(x => x.s.id === props.current.selected);
    if (!b) return null;
    if (inHandle(p, b.x0, HEAD_H, BOX_H - HEAD_H)) return { s: b.s, isStart: true };
    if (inHandle(p, b.x1, HEAD_H, BOX_H - HEAD_H)) return { s: b.s, isStart: false };
    return null;
  };
  /// Celdas de SectionEdgeDrag: un chip por acorde, con la franja entera de la tira en vertical.
  const cells = () => props.current.chords.map((c, i) => ({ row: 0, x0: lay.current.xs[i], x1: lay.current.xs[i] + lay.current.ws[i], y0: 0,
    y1: CHIP_Y + CHIP_H, time: c.start, end: c.end, chordStart: c.start }));

  const down = (e) => {
    if (e.button !== 0 || !chords.length) return;
    const r = ref.current.getBoundingClientRect();
    const x = e.clientX - r.left, y = e.clientY - r.top;
    const h = handleAt(content(e));
    if (h) {
      const edge = startEdgeDrag({ sections: props.current.sections, id: h.s.id, isStart: h.isStart, cells: cells(),
        bars: props.current.analysis?.downbeats ?? [], grab: content(e), onRemote: () => repaint() });
      if (edge) {
        ref.current._st = { edge };
        try { ref.current.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
        return;
      }
    }
    const st = { x0: e.clientX, a: chipAt(x), moved: false, long: false, timer: 0, section: y < HEAD_H ? sectionAt(x) : null };
    if (st.section) {
      st.timer = setTimeout(() => {
        st.long = true;
        const { loop: lp, onLoop: set, sections: _s } = props.current;
        const s = st.section;
        if (lp && Math.abs(lp.start - s.start) < 0.01 && Math.abs(lp.end - s.end) < 0.01) set(null);
        else set(s.start, s.end, s.name);
      }, LONG_PRESS_MS);
    }
    try { ref.current.setPointerCapture(e.pointerId); } catch { /* puntero sintético */ }
    ref.current._st = st;
  };
  const move = (e) => {
    const st = ref.current?._st;
    if (!st) { ref.current.style.cursor = handleAt(content(e)) ? 'col-resize' : ''; return; }
    if (st.edge) {
      const p = content(e);
      st.edge.track(p);
      if (st.edge.moved) { preview.current = st.edge.preview(p, e.altKey); repaint(); }
      return;
    }
    if (Math.abs(e.clientX - st.x0) >= CLICK_SLOP) {
      st.moved = true;
      clearTimeout(st.timer);
      if (st.long || props.current.edit) return;
      const r = ref.current.getBoundingClientRect();
      drag.current = { a: st.a, b: chipAt(e.clientX - r.left) };
      repaint();
    }
  };
  const up = (e) => {
    const st = ref.current?._st;
    if (!st) return;
    ref.current._st = null;
    if (st.edge) {
      const done = st.edge.commit(content(e), e.altKey);
      const clear = () => { preview.current = null; repaint(); };
      if (done) done.finally(clear); else clear();
      return;
    }
    clearTimeout(st.timer);
    const r = ref.current.getBoundingClientRect();
    const b = chipAt(e.clientX - r.left);
    drag.current = null;
    repaint();
    if (st.long || b < 0 || st.a < 0) return;
    if (!st.moved) {
      // Clic en la cabecera de una sección: abre su ventana (Mac: SectionBoxPiece); en un acorde, salta (o, en modo
      // edición, abre el editor del acorde, anclado bajo su chip).
      if (st.section) { props.current.onSection?.(st.section.id, e.clientX, e.clientY + 12); return; }
      if (props.current.edit) {
        const L = lay.current, px = e.clientX - r.left + L.scroll;
        if (px >= L.xs[st.a] && px <= L.xs[st.a] + L.ws[st.a]) setEd({ i: st.a, x: r.left + L.xs[st.a] - L.scroll, y: r.top + CHIP_Y + CHIP_H + 6 });
        return;
      }
      props.current.onSeek(chords[st.a].start);
      return;
    }
    if (props.current.edit) return;
    const lo = Math.min(st.a, b), hi = Math.max(st.a, b);
    const [s, en] = snapRange(analysis, chords[lo].start, chords[hi].end, e.altKey);
    onLoop(s, en, e.altKey ? 'compases' : 'acordes');
  };

  const cancel = () => { ref.current?._st?.edge?.dispose(); if (ref.current) ref.current._st = null; drag.current = null; preview.current = null; repaint(); };
  /// Clic derecho en la cabecera de una sección: su menú (Mac: SectionMenu).
  const menu = e => {
    const r = ref.current.getBoundingClientRect();
    const s = e.clientY - r.top < HEAD_H ? sectionAt(e.clientX - r.left) : null;
    if (!s) return;
    e.preventDefault();
    openSectionMenu(s.id, e.clientX, e.clientY);
  };
  /// Rueda horizontal (o Mayús + rueda): mueve la tira a mano hasta el próximo cambio de acorde, como el ScrollView del Mac.
  const wheel = e => {
    const d = e.deltaX || (e.shiftKey ? e.deltaY : 0);
    if (!d) return;
    e.preventDefault();
    const L = lay.current;
    L.anim = null;
    L.scroll = Math.min(Math.max(L.scroll + d, 0), Math.max(L.total - L.width, 0));
    repaint();
  };
  const seg = ed ? chords[ed.i] : null;
  return html`<${Fragment}><canvas ref=${ref} class=${'strip-canvas' + (edit ? ' editing' : '')} style=${`height:${STRIP_HEIGHT}px`} role="img"
    aria-label=${edit ? 'Tira de acordes en edición: clic en un acorde para cambiarlo o partirlo' : 'Tira de acordes: clic para saltar, arrastrar para marcar un bucle'}
    onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onPointerCancel=${cancel} onContextMenu=${menu} onWheel=${wheel} />
    ${seg ? html`<${Popover} key=${ed.i} x=${ed.x} y=${ed.y} label="Editar acorde" onClose=${() => setEd(null)}>
      <${ChordEditor} seg=${seg} time=${null} transpose=${transpose} beats=${analysis?.beats} overrides=${overrides} /></${Popover}>` : null}
  </${Fragment}>`;
}

function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`;
}
export { hexA, isChord };
