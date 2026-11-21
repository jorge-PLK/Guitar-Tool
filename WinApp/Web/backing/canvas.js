// Utilidades de canvas: nitidez con devicePixelRatio, colores de tokens.css y repintado por posición sin re-render de Preact.
import { useRef, useEffect } from 'preact/hooks';
import { onPosition } from './store.js';

let cached = null;
/// Colores de tokens.css (se leen una vez; las variables no cambian en caliente).
export function colors() {
  if (cached) return cached;
  const cs = getComputedStyle(document.documentElement);
  const v = n => cs.getPropertyValue(n).trim();
  cached = {
    bg: v('--bg'), card: v('--card'), field: v('--field'), line: v('--line'), fieldLine: v('--field-line'),
    text: v('--text'), text2: v('--text-2'), muted: v('--muted'), accent: v('--accent'), accentBg: v('--accent-bg'),
    accentInk: v('--accent-ink'), ok: v('--ok'), danger: v('--danger'), progress: '#5BC0EB',
  };
  return cached;
}

export const font = (size, weight = 400, family = 'Inter') => `${weight} ${size}px ${family}, "Segoe UI", system-ui, sans-serif`;

export function roundRect(ctx, x, y, w, h, r) {
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

/// Texto recortado con «…» para que quepa en `maxW`.
export function fitText(ctx, text, maxW) {
  if (ctx.measureText(text).width <= maxW) return text;
  let t = text;
  while (t.length > 1 && ctx.measureText(t + '…').width > maxW) t = t.slice(0, -1);
  return t.length > 1 ? t + '…' : '';
}

/// Canvas nítido: `draw(ctx, w, h)` pinta en píxeles CSS. Devuelve { ref, repaint }.
/// Se repinta al cambiar de tamaño o de devicePixelRatio, al llegar la posición (agrupado en rAF) y con `repaint()`.
/// `draw` se guarda en una ref: usa siempre la última versión sin re-suscribir.
export function useCanvas(draw, { onPos = true } = {}) {
  const ref = useRef(null);
  const drawRef = useRef(draw);
  drawRef.current = draw;
  const api = useRef(null);
  if (!api.current) {
    let raf = 0;
    const paint = () => {
      raf = 0;
      const c = ref.current;
      if (!c) return;
      const dpr = window.devicePixelRatio || 1;
      const w = c.clientWidth, h = c.clientHeight;
      if (!w || !h) return;
      const pw = Math.round(w * dpr), ph = Math.round(h * dpr);
      if (c.width !== pw || c.height !== ph) { c.width = pw; c.height = ph; }
      const ctx = c.getContext('2d');
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      try { drawRef.current(ctx, w, h); } catch (e) { console.error('canvas draw', e); }
    };
    api.current = { paint, repaint() { if (!raf) raf = requestAnimationFrame(paint); }, cancel() { if (raf) cancelAnimationFrame(raf); raf = 0; } };
  }
  useEffect(() => {
    const a = api.current;
    const ro = new ResizeObserver(() => a.repaint());
    if (ref.current) ro.observe(ref.current);
    const onResize = () => a.repaint();
    window.addEventListener('resize', onResize);
    const off = onPos ? onPosition(() => a.repaint()) : null;
    document.fonts?.ready.then(() => a.repaint());
    a.repaint();
    return () => { ro.disconnect(); window.removeEventListener('resize', onResize); off?.(); a.cancel(); };
  }, []);
  // Cada render (datos nuevos) repinta.
  useEffect(() => { api.current.repaint(); });
  return { ref, repaint: api.current.repaint };
}
