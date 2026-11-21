// Teclado de la pantalla Tablatura. El núcleo decide qué hace cada tecla (`tab.edit {op:"key"}`, mismas reglas que el
// `handleKey` del Mac); aquí solo se decide qué teclas se le reenvían y cuáles se consumen para que el navegador no las use.
import { tab, edit, spanAction } from './store.js';

const PURE_MODIFIERS = new Set(['Shift', 'Control', 'Alt', 'Meta', 'AltGraph', 'CapsLock', 'ContextMenu']);
const CONSUMED = new Set(['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Backspace', 'Delete', 'Escape']);

/// Devuelve true si la tecla se reenvió al núcleo (y el evento debe consumirse).
export function forwardEditKey(e) {
  const st = tab.value;
  if (!st || st.phase !== 'ready') return false;
  const cmd = e.ctrlKey || e.metaKey;
  if (e.key === 'Escape' && !cmd && !e.altKey && !e.shiftKey && !st.editMode) {
    if (st.span) { spanAction('clear'); return true; }
    return false;
  }
  if (!st.editMode) return false;
  if (PURE_MODIFIERS.has(e.key) || e.key === ' ' || e.key === 'Tab' || e.key === 'Enter' || /^F\d+$/.test(e.key)) return false;
  // Ctrl+Y rehace en Windows (el Mac solo tiene ⇧⌘Z).
  if (cmd && !e.altKey && e.key.toLowerCase() === 'y') { edit('redo', {}, { quiet: true }); return true; }
  const single = e.key.length === 1;
  const known = CONSUMED.has(e.key) || (single && (!cmd && !e.altKey || (cmd && e.key.toLowerCase() === 'z') || (e.altKey && e.key.toLowerCase() === 'y')));
  if (!known) return false;
  edit('key', { key: e.key, shift: e.shiftKey, ctrl: cmd, alt: e.altKey }, { quiet: true });
  return true;
}
