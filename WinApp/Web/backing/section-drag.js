// Arrastre de un borde de sección, igual en la tira y en la rejilla: la cuenta de vista de `Store.SectionEdgeDrag` del Mac
// (posición → tiempo por celdas, borde medido desde donde está dibujado, imán al acorde dibujado o, con Alt, al compás).
// Las REGLAS (mínimo 0,5 s, empuje de la vecina, freno de los solos: `SectionEditor.clampedEdge`) las aplica el núcleo al
// soltar (`study.updateSection`). La vista previa pide las secciones recortadas al núcleo (`study.previewSectionEdge`, ~10/s,
// solo vale la última respuesta) y entre respuestas sigue el puntero en local, para que no vaya a tirones.
import { signal } from '@preact/signals';
import { call } from '../bridge.js';
import { updateSection } from './store.js';

/// Mac (SectionEdgeHandle.grab): anchura de la zona que agarra una asa, centrada en el borde.
export const HANDLE_GRAB = 16;
/// Mac (SectionEdgeHandle): barra visible de 6 de ancho, alto `min(max(h - 10, 16), 30)`.
const HANDLE_W = 6;
/// Mac (DragGesture minimumDistance: 1): por debajo de esto el asa no arrastra.
const DRAG_MIN = 1;

/// Sección resaltada con asas (Mac: SectionSelection.selected; la ventana abierta va aparte, `sectionPanel`).
export const selectedSection = signal(null);

const gap = (lo, hi, v) => (v < lo ? lo - v : v > hi ? v - hi : 0);
const rowAt = (y, cells) => cells.reduce((b, c) => (!b || gap(c.y0, c.y1, y) < gap(b.y0, b.y1, y) ? c : b), null)?.row;

/// Tiempo bajo `p` sin imán: interpolado dentro de la celda de la fila más cercana (Mac: SectionEdgeDrag.time).
/// cells: [{ row, x0, x1, y0, y1, time, end, chordStart }] en orden de reproducción.
export function timeAt(p, cells) {
  const r = rowAt(p.y, cells);
  if (r == null) return null;
  let c = null;
  for (const k of cells) if (k.row === r && (!c || gap(k.x0, k.x1, p.x) < gap(c.x0, c.x1, p.x))) c = k;
  const w = c.x1 - c.x0;
  const f = w > 0 ? Math.min(Math.max((p.x - c.x0) / w, 0), 1) : 0;
  return c.time + f * (c.end - c.time);
}

/// Punto donde se dibuja `time`, en la fila que lo contiene más cercana a `near` (Mac: SectionEdgeDrag.point).
function pointFor(time, near, cells) {
  const SAME = 0.01;   // SectionEditor.sameTime
  const rows = new Map();
  for (const c of cells) { const a = rows.get(c.row); if (a) a.push(c); else rows.set(c.row, [c]); }
  let best = null;
  for (const rc of rows.values()) {
    if (!(rc[0].time - SAME <= time && time <= rc[rc.length - 1].end + SAME)) continue;
    if (!best || gap(rc[0].y0, rc[0].y1, near.y) < gap(best[0].y0, best[0].y1, near.y)) best = rc;
  }
  if (!best) return null;
  const c = best.find(k => k.time <= time && time <= k.end) ?? (time < best[0].time ? best[0] : best[best.length - 1]);
  const f = c.end > c.time ? Math.min(Math.max((time - c.time) / (c.end - c.time), 0), 1) : 0;
  return { x: c.x0 + f * (c.x1 - c.x0), y: Math.min(Math.max(near.y, c.y0), c.y1) };
}

/// Mac (SectionEditor.snap): el límite más cercano (la lista nunca está vacía: lleva el borde original).
const nearest = (t, list) => list.reduce((b, v) => (Math.abs(v - t) < Math.abs(b - t) ? v : b), list[0]);

/// Empieza el arrastre del borde (`isStart`) de la sección `id` agarrado en `grab` (coordenadas del contenido). `bars`:
/// límites de compás (imán con Alt). Null si la sección no existe.
/// Mac (SectionEdgeDrag: la vista previa se recalcula con cada movimiento); aquí, como mucho cada 100 ms.
const PREVIEW_EVERY_MS = 100;
/// SectionEditor.minLength.
const MIN_LENGTH = 0.5;

/// `onRemote`: se llama (sin argumentos) cuando llega una respuesta del núcleo, para repintar.
export function startEdgeDrag({ sections, id, isStart, cells, bars, grab, onRemote }) {
  const s = sections.find(x => x.id === id);
  if (!s || !cells.length) return null;
  const original = isStart ? s.start : s.end;
  const chords = cells.filter(c => c.chordStart != null).map(c => c.chordStart);
  chords.push(cells[0].time, cells[cells.length - 1].end);
  const chordMagnet = [...new Set(chords)].sort((a, b) => a - b);
  const barMagnet = [...new Set(bars)].sort((a, b) => a - b);
  const anchor = pointFor(original, grab, cells) ?? grab;
  // Vista previa del núcleo: { t (pedido), edge (resultante), sections } de la última respuesta válida.
  let remote = null, seq = 0, lastAsked = null, lastSent = -Infinity, timer = 0, dead = false;
  const send = t => {
    clearTimeout(timer); timer = 0;
    const mine = ++seq;
    lastSent = performance.now();
    call('study.previewSectionEdge', { id, start: isStart, to: t }).then(r => {
      if (dead || mine !== seq || !r?.sections) return;   // respuesta vieja: solo se pinta la última pedida
      const me = r.sections.find(x => x.id === id);
      remote = { t, edge: me ? (isStart ? me.start : me.end) : t, sections: r.sections };
      onRemote?.();
    }).catch(() => { /* sin vista previa del núcleo: sigue la local */ });
  };
  const ask = t => {
    if (lastAsked != null && Math.abs(t - lastAsked) < 1e-6) return;
    lastAsked = t;
    const wait = PREVIEW_EVERY_MS - (performance.now() - lastSent);
    if (wait <= 0) send(t);
    else { clearTimeout(timer); timer = setTimeout(() => send(t), wait); }
  };
  /// Entre respuestas: la última del núcleo con el borde en `t` (frenado donde el núcleo lo frenó) y la vecina empujada.
  const blend = t => {
    const r = remote;
    const lim = r.edge;
    const e = Math.abs(lim - r.t) < 1e-6 ? t : (lim > r.t ? Math.max(t, lim) : Math.min(t, lim));
    const me = r.sections.find(x => x.id === id);
    return r.sections.map(x => {
      if (x.id === id) return { ...x, [isStart ? 'start' : 'end']: e };
      if (isStart && x.end > e && x.start < me.start) return { ...x, end: Math.min(x.end, e) };
      if (!isStart && x.start < e && x.end > me.end) return { ...x, start: Math.min(Math.max(x.start, e), x.end - MIN_LENGTH) };
      return x;
    });
  };
  return {
    id, isStart, original, sections, grab, moved: false,
    /// Deja de pedir y de pintar respuestas (al soltar o cancelar).
    dispose() { dead = true; clearTimeout(timer); },
    /// Tiempo imantado con el puntero en `loc` (sin las reglas de SectionEditor: las pone el núcleo al soltar).
    edge(loc, bar) {
      const t = timeAt({ x: anchor.x + loc.x - grab.x, y: anchor.y + loc.y - grab.y }, cells);
      if (t == null) return original;
      return nearest(t, [...(bar && barMagnet.length ? barMagnet : chordMagnet), original]);
    },
    /// Vista previa: las secciones con el borde arrastrado en su sitio imantado.
    preview(loc, bar) {
      const t = this.edge(loc, bar);
      ask(t);
      if (remote) return blend(t);
      return sections.map(x => (x.id === id ? { ...x, [isStart ? 'start' : 'end']: t } : x));
    },
    track(loc) { if (Math.hypot(loc.x - grab.x, loc.y - grab.y) >= DRAG_MIN) this.moved = true; },
    /// Al soltar: el núcleo recorta el borde (`clampedEdge`) y empuja a la vecina; se repinta con su `EditState.sections`.
    commit(loc, bar) {
      this.dispose();
      if (!this.moved) return null;
      const t = this.edge(loc, bar);
      if (Math.abs(t - original) < 1e-6) return null;
      return updateSection(id, { [isStart ? 'start' : 'end']: t, snap: 'none' });
    },
  };
}

/// Asa de un borde: zona de agarre de 16 centrada en `x` entre `top` y `top + h`.
export const inHandle = (p, x, top, h) => Math.abs(p.x - x) <= HANDLE_GRAB / 2 && p.y >= top && p.y <= top + h;

/// Dibuja el asa (Mac: cápsula del color de la sección con sombra negra al 50 %, radio 2).
export function drawHandle(ctx, x, top, h, tint) {
  const ch = Math.min(Math.max(h - 10, 16), 30);
  const y = top + (h - ch) / 2;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 4;
  ctx.beginPath();
  ctx.roundRect ? ctx.roundRect(x - HANDLE_W / 2, y, HANDLE_W, ch, HANDLE_W / 2) : ctx.rect(x - HANDLE_W / 2, y, HANDLE_W, ch);
  ctx.fillStyle = tint; ctx.fill();
  ctx.restore();
}

/// Mac (SectionBoxPiece.label): los solos llevan `guitars.fill` (10 pt, semibold) delante del nombre, a 4 de distancia, todo en
/// naranja; si no cabe con el nombre, solo el icono. Las demás secciones, solo el nombre (aquí recortado con «…»).
/// `x`: borde izquierdo del texto; `cy`: centro vertical; `maxW`: ancho disponible; `fit`: fitText de canvas.js.
const ICON = 10, ICON_GAP = 4;
export function drawSectionLabel(ctx, s, x, cy, maxW, color, fit) {
  ctx.fillStyle = color;
  if (!s.solo) { const t = fit(ctx, s.name, maxW); if (t) ctx.fillText(t, x, cy); return; }
  const full = ICON + ICON_GAP + ctx.measureText(s.name).width;
  if (full <= maxW) ctx.fillText(s.name, x + ICON + ICON_GAP, cy);
  if (ICON > maxW) return;
  // Aproximación de la insignia de guitarras: cuerpo redondo y mástil en diagonal.
  ctx.save();
  ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.arc(x + 3.4, cy + 2.4, 3.2, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.moveTo(x + 5.6, cy); ctx.lineTo(x + 9.2, cy - 3.6); ctx.stroke();
  ctx.restore();
}
