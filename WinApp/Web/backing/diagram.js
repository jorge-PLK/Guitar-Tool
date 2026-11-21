// Diagrama de acorde (ChordDiagram.swift del Mac): 6 cuerdas, 5 trastes visibles. SVG: cambia solo con el acorde, no a 30 Hz.
import { html } from '../html.js';

const FRET_ROWS = 5, TOP = 16, LEFT = 22;

export function ChordDiagram({ shape, width = 72, height = 84 }) {
  if (!shape) return html`<svg width=${width} height=${height} role="img" aria-label="Sin diagrama"></svg>`;
  const pressed = shape.frets.filter(f => f != null && f > 0);
  const hasOpen = shape.frets.some(f => f === 0);
  // Sin cuerdas al aire y sin traste 1: el diagrama arranca en el traste más bajo.
  const base = !hasOpen && pressed.length && Math.min(...pressed) > 1 ? Math.min(...pressed) : shape.baseFret;
  const right = width - 6, bottom = height - 4;
  const sg = (right - LEFT) / 5, fg = (bottom - TOP) / FRET_ROWS;
  const x = s => LEFT + s * sg, y = r => TOP + r * fg;
  const out = [];
  for (let r = 0; r <= FRET_ROWS; r++) {
    const nut = r === 0 && base === 1;
    out.push(html`<line x1=${LEFT} x2=${right} y1=${y(r)} y2=${y(r)} stroke=${nut ? 'var(--text-2)' : 'rgba(154,163,173,.8)'} stroke-width=${nut ? 3 : 1} />`);
  }
  for (let s = 0; s < 6; s++) out.push(html`<line x1=${x(s)} x2=${x(s)} y1=${TOP} y2=${bottom} stroke="rgba(154,163,173,.8)" stroke-width="1" />`);
  if (base > 1) out.push(html`<text x="10" y=${y(0) + fg / 2} text-anchor="middle" dominant-baseline="central" font-size="10" font-weight="600" fill="var(--text-2)">${base}fr</text>`);
  if (shape.barre) {
    const b = shape.barre, row = b.fret - base;
    const a = 6 - Math.max(b.fromString, b.toString), z = 6 - Math.min(b.fromString, b.toString);
    out.push(html`<rect x=${x(a) - 4} y=${y(row) + fg / 2 - 4} width=${x(z) - x(a) + 8} height="8" rx="4" fill="var(--accent)" />`);
  }
  shape.frets.forEach((fret, s) => {
    if (fret == null) out.push(html`<text x=${x(s)} y="7" text-anchor="middle" dominant-baseline="central" font-size="11" font-weight="700" fill="var(--muted)">×</text>`);
    else if (fret === 0) out.push(html`<circle cx=${x(s)} cy="7" r="3.5" fill="none" stroke="var(--text-2)" stroke-width="1" />`);
    else {
      const row = fret - base;
      if (row >= 0 && row < FRET_ROWS) out.push(html`<circle cx=${x(s)} cy=${y(row) + fg / 2} r="5" fill="var(--accent)" />`);
    }
  });
  return html`<svg width=${width} height=${height} viewBox=${`0 0 ${width} ${height}`} role="img" aria-label="Diagrama del acorde" style="font-family:var(--font-body)">${out}</svg>`;
}
