// Edición de acordes y tonalidad de Backing (ChordEditor y menú de tonalidad del Mac). Ventana flotante anclada a un punto
// (no ocupa sitio en la pantalla). Acordes y tonalidades viajan siempre «guardados» (sin transponer): aquí se convierten.
import { signal } from '@preact/signals';
import { html } from '../html.js';
import { useRef, useEffect, useState } from 'preact/hooks';
import { icon } from '../icons.js';
import {
  QUALITY_COUNT, NO_CHORD_INDEX, SPANISH_NOTES, isChord, rootOf, qualityOf, transposed, chordName, qualityLabel, keyParts, storedKeyLabel,
} from './chords.js';
import { study, transport, pos, onPosition, setChord, removeChordOverrides, clearChordOverrides, splitChord, setKey } from './store.js';

/// Modo «Editar acordes» (BackingView.chordsEdit del Mac): con él, clic en un acorde lo edita y no se marcan bucles.
export const chordEditMode = signal(false);

/// Mac (ChordEditor.splitBeat): «Partir aquí» solo si el pulso más cercano queda a más de 50 ms de ambos extremos.
const SPLIT_MARGIN = 0.05;

/// Ventana flotante: se coloca junto al punto (`x`,`y`), dentro de la ventana; se cierra con clic fuera o Esc.
export function Popover({ x, y, onClose, label, children, align = 'left' }) {
  const ref = useRef(null);
  const [at, setAt] = useState({ left: x, top: y, ready: false });
  useEffect(() => {
    const r = ref.current.getBoundingClientRect();
    let left = align === 'right' ? x - r.width : x;
    left = Math.max(8, Math.min(left, window.innerWidth - r.width - 8));
    let top = y;
    if (top + r.height > window.innerHeight - 8) top = Math.max(8, y - r.height - 8);   // si no cabe debajo, encima del punto
    setAt({ left, top, ready: true });
    const down = e => { if (!ref.current?.contains(e.target)) onClose('outside'); };
    const key = e => { if (e.key === 'Escape') { e.stopPropagation(); onClose('escape'); } };
    const onBlur = () => onClose('outside');
    document.addEventListener('mousedown', down, true);
    window.addEventListener('keydown', key, true);
    window.addEventListener('blur', onBlur);
    return () => { document.removeEventListener('mousedown', down, true); window.removeEventListener('keydown', key, true); window.removeEventListener('blur', onBlur); };
  }, []);
  return html`<div class="popover" ref=${ref} role="dialog" aria-label=${label}
    style=${`left:${at.left}px;top:${at.top}px;visibility:${at.ready ? 'visible' : 'hidden'}`}>${children}</div>`;
}

const Chip = ({ on, children, ...rest }) => html`<button class=${'pchip' + (on ? ' on' : '')} aria-pressed=${on} ...${rest}>${children}</button>`;

/// Editor de un acorde (tramo): raíz + calidad, «N (sin acorde)», «Partir aquí», «Quitar corrección» (ChordEditor del Mac).
/// `seg` = tramo de `analysis.chords`; `time` = instante de partida: un número fijo (rejilla: el pulso pulsado) o `null` para
/// seguir la posición de reproducción (tira, como el Mac); `transpose` = el del transporte.
export function ChordEditor({ seg, time, transpose, beats, overrides }) {
  const shown = transposed(seg.index, transpose);
  const [root, setRoot] = useState(rootOf(shown));
  const [quality, setQuality] = useState(qualityOf(shown));
  const [live, setLive] = useState(pos.seconds);
  useEffect(() => (time == null ? onPosition(() => setLive(pos.seconds)) : undefined), [time]);
  const at = time ?? live;
  const store = idx => transposed(idx, -transpose);
  const commit = (r, q) => { if (r != null && q != null) setChord(seg.start, seg.end, store(r * QUALITY_COUNT + q)); };
  // Pulso más cercano a `at`, si queda dentro del tramo con margen.
  const splitAt = (() => {
    if (!(at > seg.start && at < seg.end) || !beats?.length) return null;
    const b = beats.reduce((best, t) => (Math.abs(t - at) < Math.abs(best - at) ? t : best), beats[0]);
    return b > seg.start + SPLIT_MARGIN && b < seg.end - SPLIT_MARGIN ? b : null;
  })();
  const corrected = (overrides ?? []).some(o => o.start < seg.end && o.end > seg.start);
  return html`<div class="chord-editor">
    <div class="pop-title">Acorde</div>
    <div class="pgrid roots">${Array.from({ length: 12 }, (_, r) => html`<${Chip} key=${r} on=${root === r}
      onClick=${() => { setRoot(r); commit(r, quality); }}>${chordName(r * QUALITY_COUNT + 1)}</${Chip}>`)}</div>
    <div class="pgrid qualities">${Array.from({ length: QUALITY_COUNT }, (_, q) => html`<${Chip} key=${q} on=${quality === q}
      onClick=${() => { setQuality(q); commit(root, q); }}>${qualityLabel(q)}</${Chip}>`)}</div>
    <div class="prow"><${Chip} on=${seg.index === NO_CHORD_INDEX} onClick=${() => setChord(seg.start, seg.end, NO_CHORD_INDEX)}>N (sin acorde)</${Chip}></div>
    <div class="psep"></div>
    <div class="prow between">
      <button class="btn secondary xs" disabled=${splitAt == null} title="Parte el tramo en el pulso más cercano al cursor de reproducción"
        onClick=${() => splitChord(splitAt)}>Partir aquí</button>
      <button class="btn secondary xs" disabled=${!corrected}
        onClick=${() => removeChordOverrides(seg.start, seg.end)}>Quitar corrección</button>
    </div>
  </div>`;
}

/// Botón «Editar acordes» y, en modo edición, «Quitar todas las correcciones» (si las hay).
export function ChordEditToggle() {
  const edit = chordEditMode.value;
  const n = study.value?.chordOverrides?.length ?? 0;
  return html`<span class="chord-edit-ctl">
    <button class=${'btn xs chord-edit-btn' + (edit ? ' on' : ' secondary')} aria-pressed=${edit}
      onClick=${() => { chordEditMode.value = !edit; }}>${icon('pencil', 14)}Editar acordes</button>
    ${edit && n > 0 ? html`<button class="btn secondary xs" title="Quita todas las correcciones de acordes de este tema"
      onClick=${() => clearChordOverrides()}>Quitar todas (${n})</button>` : null}
  </span>`;
}

/// Menú de tonalidad (Mac: Menu con 24 tonalidades + «Volver a la detectada»; deshabilitado sin análisis).
export function KeyMenu() {
  const a = study.value?.analysis, tr = transport.value?.transpose ?? 0;
  const [at, setAt] = useState(null);
  const key = a?.key;
  const eff = keyParts(key?.effective);
  const enabled = a?.state === 'ready';
  const name = eff ? SPANISH_NOTES[(eff.root + tr + 120) % 12] + (eff.minor ? ' menor' : ' mayor') : '—';
  const pick = async (r, minor) => { setAt(null); await setKey(storedKeyLabel(r, minor, tr)); };
  // Misma lista que el Mac: 12 mayores y 12 menores en una sola columna, sin marca de la actual.
  const items = Array.from({ length: 24 }, (_, n) => ({ r: n % 12, minor: n >= 12 }));
  return html`<span class="stat">Tonalidad:
    <button class="key-btn" disabled=${!enabled} aria-haspopup="dialog" aria-expanded=${!!at} title=${enabled ? 'Corregir la tonalidad' : 'Hace falta el análisis'}
      onClick=${e => { const r = e.currentTarget.getBoundingClientRect(); setAt({ x: r.left, y: r.bottom + 4 }); }}>
      <b>${name}${key?.override ? ' (corregida)' : ''}</b><span class="key-caret" aria-hidden="true">▾</span></button>
    ${at ? html`<${Popover} x=${at.x} y=${at.y} label="Tonalidad" onClose=${() => setAt(null)}>
      <div class="key-menu">${items.map(k => html`<button key=${k.r + (k.minor ? 12 : 0)} class="pitem" onClick=${() => pick(k.r, k.minor)}>${SPANISH_NOTES[k.r]} ${k.minor ? 'menor' : 'mayor'}</button>`)}
        ${key?.override ? html`<div class="psep"></div>
          <button class="pitem" onClick=${async () => { setAt(null); await setKey(null); }}>Volver a la detectada</button>` : null}
      </div></${Popover}>` : null}
  </span>`;
}
