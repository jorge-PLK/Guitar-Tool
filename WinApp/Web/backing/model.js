// Cálculos puros de Backing: formatos, secciones, rejilla de compases y bucles. Sin DOM ni señales.
import { NO_CHORD_INDEX } from './chords.js';

/// Paleta de secciones (Theme.swift: TF.sectionPalette); los solos van en el acento.
export const SECTION_PALETTE = ['#6C9BD2', '#6FB58A', '#9C86C9', '#C97F9E', '#5DB5B5', '#A6B85C', '#C8706A'];
/// Mac (ChordGridLayout.probeFraction): el acorde de un pulso se toma un poco después del pulso.
export const PROBE_FRACTION = 0.35;

export const fmtClock = s => { const t = Math.floor(Math.max(s || 0, 0)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
export const fmtDb = v => `${v.toFixed(1).replace('.', ',')} dB`;
export const fmtPercent = f => `${Math.round(f * 100)} %`;
export const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

/// Color efectivo de una sección: elegido, o el automático (`paletteIndex`), o el primero.
export function sectionTint(s, accent) {
  if (s.solo) return accent;
  return SECTION_PALETTE[(s.color ?? s.paletteIndex ?? 0) % SECTION_PALETTE.length];
}

/// Índice del último elemento con `start <= t` (-1 si t es anterior al primero). `items` ordenado por `start`.
export function indexAt(items, t, key = 'start') {
  let lo = 0, hi = items.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (items[mid][key] <= t) { ans = mid; lo = mid + 1; } else hi = mid - 1;
  }
  return ans;
}

/// Acorde que suena en `t` (posición en `chords`), o -1.
export function chordAt(chords, t) {
  const i = indexAt(chords, t);
  return i >= 0 && t < chords[i].end ? i : -1;
}

/// Mac (BeatGrid): primer índice con a[i] >= x, y primero con a[i] > x.
const lowerBound = (a, x) => { let lo = 0, hi = a.length; while (lo < hi) { const m = (lo + hi) >> 1; if (a[m] < x) lo = m + 1; else hi = m; } return lo; };
const upperBound = (a, x) => { let lo = 0, hi = a.length; while (lo < hi) { const m = (lo + hi) >> 1; if (a[m] <= x) lo = m + 1; else hi = m; } return lo; };
/// Mac (BeatGrid.nearest): el empate va al anterior.
const nearest = (a, x) => {
  if (!a.length) return null;
  const i = lowerBound(a, x);
  if (i === 0) return a[0];
  if (i === a.length) return a[a.length - 1];
  return x - a[i - 1] <= a[i] - x ? a[i - 1] : a[i];
};

/// Bucle desde un arrastre, igual que `BeatGrid.snap` del Mac: extremos al pulso más cercano (al compás con `bar`, como ⌥;
/// sin compases no ajusta). Si caen en el mismo punto, el final pasa al siguiente (o el inicio al anterior).
export function snapRange(analysis, a, b, bar = false) {
  const grid = (bar ? analysis?.downbeats : analysis?.beats) ?? [];
  const lo = nearest(grid, a);
  let hi = nearest(grid, b);
  if (lo == null || hi == null) return [a, b];
  let start = lo;
  if (hi <= start) {
    const next = upperBound(grid, start);
    if (next < grid.length) hi = grid[next];
    else {
      const prev = lowerBound(grid, start) - 1;
      if (prev < 0) return [a, b];
      start = grid[prev];
      hi = lo;
    }
  }
  return [start, hi];
}

/// Rejilla de compases (ChordGridLayout del Mac): compases por downbeats, celdas por pulsos.
export function buildGrid(analysis, chords) {
  const beats = analysis?.beats ?? [], downs = analysis?.downbeats ?? [];
  if (!downs.length || !beats.length) return null;
  const beatDur = analysis.bpm ? 60 / analysis.bpm : 0.5;
  const bars = [];
  let j = 0, previous = null, ptr = 0;
  downs.forEach((start, n) => {
    const end = n + 1 < downs.length ? downs[n + 1] : Math.max(beats[beats.length - 1] + beatDur, start + beatDur);
    while (j < beats.length && beats[j] < start - 1e-6) j++;
    const times = [];
    while (j < beats.length && beats[j] < end - 1e-6) times.push(beats[j++]);
    if (!times.length) return;
    const cells = times.map((t, k) => {
      const e = k + 1 < times.length ? times[k + 1] : end;
      const probe = t + PROBE_FRACTION * (e - t);
      while (ptr + 1 < chords.length && chords[ptr + 1].start <= probe) ptr++;
      const seg = ptr < chords.length && chords[ptr].start <= probe && probe < chords[ptr].end ? ptr : null;
      const label = seg != null ? chords[seg].index : NO_CHORD_INDEX;
      const cell = { time: t, end: e, chord: seg, label, isChange: label !== previous };
      previous = label;
      return cell;
    });
    bars.push({ number: n + 1, start, end, cells });
  });
  return bars.length ? { bars } : null;
}

export function barIndexAt(bars, t) {
  let lo = 0, hi = bars.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (bars[mid].start <= t + 1e-6) lo = mid; else hi = mid - 1;
  }
  return lo;
}

/// Siguiente acorde distinto y real tras el actual (diagrama: «Siguiente: F»).
export function nextChord(chords, current) {
  if (current < 0) return null;
  for (let i = current + 1; i < chords.length; i++) {
    if (chords[i].index !== chords[current].index && chords[i].index < 168) return chords[i];
  }
  return null;
}
