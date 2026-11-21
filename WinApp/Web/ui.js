import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from './html.js';
import { icon } from './icons.js';
import { notices, dismissNotice } from './state.js';

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [href], select, textarea, [tabindex]:not([tabindex="-1"])';

/// Hoja modal reutilizable: fondo (no se cierra al pulsar fuera, como las hojas del Mac), foco atrapado, Esc (si `onClose`), devuelve el foco al cerrar.
/// `autofocus`: selector del elemento que recibe el foco (por defecto el primero enfocable).
export function Modal({ title, onClose, width = 480, autofocus, children, labelledBy = 'modal-title' }) {
  const box = useRef(null);
  useEffect(() => {
    const previous = document.activeElement;
    const el = box.current;
    const first = (autofocus && el.querySelector(autofocus)) ?? el.querySelector(FOCUSABLE) ?? el;
    first.focus();
    return () => { if (previous?.isConnected) previous.focus(); };
  }, []);
  const onKeyDown = e => {
    if (e.key === 'Escape' && onClose) { e.stopPropagation(); e.preventDefault(); onClose(); return; }
    if (e.key !== 'Tab') return;
    const items = [...box.current.querySelectorAll(FOCUSABLE)].filter(n => n.offsetParent !== null);
    if (!items.length) { e.preventDefault(); return; }
    const a = items[0], z = items[items.length - 1];
    if (e.shiftKey && (document.activeElement === a || !box.current.contains(document.activeElement))) { e.preventDefault(); z.focus(); }
    else if (!e.shiftKey && (document.activeElement === z || !box.current.contains(document.activeElement))) { e.preventDefault(); a.focus(); }
  };
  return html`<div class="modal-backdrop" onKeyDown=${onKeyDown}>
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby=${labelledBy} ref=${box} tabindex="-1" style=${`width:${width}px`}>
      <h2 class="modal-title" id=${labelledBy}>${title}</h2>${children}</div></div>`;
}

/// Menú desplegable anclado a un punto (`x`,`y` de ventana). Se cierra con clic fuera, Esc o al elegir.
/// `above`: `y` es el borde inferior del menú (se abre hacia arriba, p. ej. desde una barra al pie).
/// items: [{label, onSelect, danger?, disabled?} | 'sep']
export function PopupMenu({ x, y, items, onClose, align = 'left', above = false }) {
  const ref = useRef(null);
  const [pos, setPos] = useState({ left: x, top: y });
  useEffect(() => {
    const r = ref.current.getBoundingClientRect();
    let left = align === 'right' ? x - r.width : x;
    left = Math.max(8, Math.min(left, window.innerWidth - r.width - 8));
    const top = Math.max(8, Math.min(above ? y - r.height : y, window.innerHeight - r.height - 8));
    setPos({ left, top });
    ref.current.querySelector('button:not([disabled])')?.focus();
    const down = e => { if (!ref.current.contains(e.target)) onClose(); };
    document.addEventListener('mousedown', down, true);
    window.addEventListener('blur', onClose);
    return () => { document.removeEventListener('mousedown', down, true); window.removeEventListener('blur', onClose); };
  }, []);
  const onKeyDown = e => {
    const btns = [...ref.current.querySelectorAll('button:not([disabled])')];
    const i = btns.indexOf(document.activeElement);
    if (e.key === 'Escape') { e.preventDefault(); onClose(); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); btns[(i + 1) % btns.length]?.focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); btns[(i - 1 + btns.length) % btns.length]?.focus(); }
    else if (e.key === 'Tab') { e.preventDefault(); onClose(); }
  };
  return html`<div class="menu" role="menu" ref=${ref} style=${`left:${pos.left}px;top:${pos.top}px`} onKeyDown=${onKeyDown}>
    ${items.map((it, i) => it === 'sep' ? html`<div class="menu-sep" key=${i} role="separator"></div>`
      : html`<button key=${i} role="menuitem" class=${'menu-item' + (it.danger ? ' danger' : '')} disabled=${it.disabled}
        onClick=${() => { onClose(); it.onSelect?.(); }}>${it.label}</button>`)}</div>`;
}

/// Avisos suaves (arriba a la derecha). Los de error se quedan hasta cerrarlos.
export function Notices() {
  if (!notices.value.length) return null;
  return html`<div class="notices" role="status" aria-live="polite">${notices.value.map(n => html`<div class=${'notice ' + n.kind} key=${n.id}>
    <span class="notice-text">${n.text}</span>
    ${n.action ? html`<button class="notice-action" onClick=${() => { dismissNotice(n.id); n.action.run(); }}>${n.action.label}</button>` : null}
    <button class="notice-close" aria-label="Cerrar aviso" onClick=${() => dismissNotice(n.id)}>${icon('close', 14)}</button></div>`)}</div>`;
}

/// Barra de progreso en el acento (`fraction` null = indeterminada).
export function AccentBar({ fraction }) {
  return html`<div class=${'bar' + (fraction == null ? ' indet' : '')} role="progressbar" aria-valuemin="0" aria-valuemax="100"
    aria-valuenow=${fraction == null ? undefined : Math.round(fraction * 100)}>
    <div class="bar-fill" style=${fraction == null ? undefined : `width:${Math.max(0, Math.min(1, fraction)) * 100}%`}></div></div>`;
}
