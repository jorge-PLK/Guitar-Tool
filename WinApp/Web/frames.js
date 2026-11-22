// Fotogramas del núcleo en un canvas (paso 8, W2-E1). El núcleo emite `frames.<canal>` con
// {seq, width, height, ptsMs, jpeg} (JPEG en base64, ya reducido); aquí se decodifica y se pinta el más reciente.
//
// - Como mucho una decodificación en curso; si llegan más mientras tanto, solo se guarda la última (nunca hay cola).
// - Se descartan los que llegan con `seq` menor o igual que el último pintado. `seq` = 1 reinicia (relevo nuevo).
// - El canvas toma el tamaño del fotograma; el CSS decide cómo se ve.
// Sin dependencias salvo `bridge.js`.
import { on } from './bridge.js';

function bytesOf(b64) {
  if (typeof Uint8Array.fromBase64 === 'function') return Uint8Array.fromBase64(b64);
  const s = atob(b64), out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

async function decode(frame) {
  const blob = new Blob([bytesOf(frame.jpeg)], { type: 'image/jpeg' });
  if (typeof createImageBitmap === 'function') return createImageBitmap(blob);
  const url = URL.createObjectURL(blob);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    return img;
  } finally {
    URL.revokeObjectURL(url);
  }
}

/// Pinta `frames.<channel>` en `canvas`. `onFrame(frame, stats)` opcional tras cada pintado (sin `jpeg`).
/// Devuelve la función que desengancha. `stats`: {drawn, skipped, failed}.
export function attachFrames(canvas, channel, { onFrame } = {}) {
  const ctx = canvas.getContext('2d');
  const stats = { drawn: 0, skipped: 0, failed: 0 };
  let last = 0, busy = false, pending = null, alive = true;

  async function pump() {
    busy = true;
    while (pending && alive) {
      const frame = pending;
      pending = null;
      if (frame.seq !== 1 && frame.seq <= last) { stats.skipped++; continue; }
      let image;
      try {
        image = await decode(frame);
      } catch (e) {
        stats.failed++;
        continue;
      }
      if (!alive || (frame.seq !== 1 && frame.seq <= last)) { image.close?.(); stats.skipped++; continue; }
      if (canvas.width !== frame.width || canvas.height !== frame.height) {
        canvas.width = frame.width;
        canvas.height = frame.height;
      }
      ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
      image.close?.();
      last = frame.seq;
      stats.drawn++;
      onFrame?.({ seq: frame.seq, width: frame.width, height: frame.height, ptsMs: frame.ptsMs }, stats);
    }
    busy = false;
  }

  const off = on(`frames.${channel}`, frame => {
    if (!alive || !frame || typeof frame.jpeg !== 'string') return;
    if (pending) stats.skipped++;   // el que esperaba ya es viejo
    pending = frame;
    if (!busy) pump();
  });

  return () => { alive = false; pending = null; off(); };
}
