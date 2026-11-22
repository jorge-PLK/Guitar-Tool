// Panel «Partes» (RecordBody.partsPanel), botones de toma con su menú y las hojas «Añadir parte» y «¿Borrar la toma?».
import { useState } from 'preact/hooks';
import { html } from '../html.js';
import { Modal, PopupMenu } from '../ui.js';
import { snap, locked, selectPart, selectTake, markBest, startPunch, adjustOffset, deleteTake, addPart, takesOf, guitarName } from './store.js';
import { RIcon } from './bits.js';

const STATUS = { done: ['Hecha', 'ok'], recording: ['Grabando', 'rec'], pending: ['Pendiente', 'neutral'] };

function TakeButton({ take, number, part, best, onView, onMenu }) {
  const s = snap.value;
  const busy = locked.value;
  const selected = s.selectedTakeId === take.id;
  const label = best ? `Toma ${number} · mejor` : `Toma ${number}`;
  // Clic = elegir la toma (acción principal del Mac); segundo clic en la ya elegida, clic derecho o ↓ abren su menú.
  const openMenu = e => {
    const r = e.currentTarget.getBoundingClientRect();
    e.preventDefault();
    onMenu(take, number, best, r.left, r.bottom + 4);
  };
  const click = e => { if (selected) openMenu(e); else selectTake(take.id); };
  return html`<span class="rec-take">
    <button class=${'rec-take-btn' + (best ? ' best' : '') + (selected ? ' sel' : '')} disabled=${busy} aria-pressed=${selected}
      aria-label=${`Toma ${number}${best ? ', mejor' : ''}`} onClick=${click} onContextMenu=${openMenu}
      onKeyDown=${e => { if (e.key === 'ArrowDown') openMenu(e); }}>${label}</button>
    <button class="rec-take-play" disabled=${busy || !take.audioPath || take.songStart == null} title="Ver toma" aria-label=${`Ver toma ${number}`}
      onClick=${() => onView(take, number, part)}>${RIcon.play(11)}</button></span>`;
}

function PartBox({ part, onView, onMenu }) {
  const s = snap.value;
  const active = part.id === s.activePartId;
  const [text, tone] = STATUS[part.status] ?? STATUS.pending;
  const takes = takesOf(part);
  return html`<div class=${'rec-part' + (active ? ' active' : '')} onClick=${() => { if (!active && !locked.value) selectPart(part.id); }} aria-label=${part.name} aria-current=${active}>
    <div class="rec-part-head"><span class="rec-part-name">${part.name}</span><span class=${'rec-chip ' + tone}>${text}</span></div>
    <div class="rec-part-sub">${part.replaces ? `Sustituye: ${guitarName(s, part.replaces)}` : 'Parte añadida'}</div>
    ${takes.length ? html`<div class="rec-takes">${takes.map((t, i) => html`<${TakeButton} key=${t.id} take=${t} number=${i + 1} part=${part}
      best=${part.bestTakeId === t.id} onView=${onView} onMenu=${onMenu} />`)}</div>` : null}</div>`;
}

export function PartsPanel({ onView, onAdd, onMenu }) {
  const s = snap.value;
  return html`<aside class="rec-parts"><div class="card rec-parts-card">
    <h2>Partes</h2>
    <p class="rec-parts-help">En cada toma suena el backing sin esa parte y con tus tomas anteriores.</p>
    ${s.parts.map(p => html`<${PartBox} key=${p.id} part=${p} onView=${onView} onMenu=${onMenu} />`)}
    <button class="rec-add" disabled=${locked.value} onClick=${onAdd}>Añadir parte</button></div></aside>`;
}

/// Menú de una toma (Menu del Mac): marcar como mejor, ajustar desfase, punch-in y borrar.
export function TakeMenu({ menu, onClose, onDelete }) {
  const { take, best } = menu;
  return html`<${PopupMenu} x=${menu.x} y=${menu.y} onClose=${onClose} items=${[
    { label: 'Marcar como mejor', disabled: best, onSelect: () => markBest(take.id) },
    { label: 'Ajustar desfase…', disabled: !take.hasVideo, onSelect: () => adjustOffset(take.id) },
    { label: 'Punch-in', onSelect: () => startPunch(take.id) },
    'sep',
    { label: 'Borrar…', danger: true, onSelect: () => onDelete(take.id) },
  ]} />`;
}

/// Confirmación de borrado (confirmationDialog del Mac).
export function DeleteTake({ takeId, onClose }) {
  return html`<${Modal} title="¿Borrar la toma?" width=${420} onClose=${onClose} labelledBy="rec-del-title">
    <p>Se borra su carpeta (audio y vídeo). No se puede deshacer.</p>
    <div class="modal-actions"><button class="btn secondary" onClick=${onClose}>Cancelar</button>
      <button class="btn danger" onClick=${() => { onClose(); deleteTake(takeId); }}>Borrar toma</button></div></${Modal}>`;
}

export function AddPart({ onClose }) {
  const s = snap.value;
  const [name, setName] = useState('');
  const [role, setRole] = useState('');
  const ok = name.trim() !== '';
  const submit = () => { if (!ok) return; addPart(name.trim(), role || null); onClose(); };
  return html`<${Modal} title="Añadir parte" width=${420} autofocus="input" onClose=${onClose} labelledBy="rec-add-title">
    <div class="rec-sheet rec-addpart">
      <input class="rec-field" type="text" placeholder="Nombre de la parte" aria-label="Nombre de la parte" value=${name}
        onInput=${e => setName(e.currentTarget.value)} onKeyDown=${e => { if (e.key === 'Enter') submit(); }} />
      <label class="labeled rec-role">Guitarra que sustituye
        <select class="select" value=${role} onChange=${e => setRole(e.currentTarget.value)}>
          <option value="">Ninguna (parte añadida)</option>
          ${(s.guitarRoles ?? []).map(g => html`<option value=${g.role}>${g.name}</option>`)}</select></label>
      <div class="modal-actions"><button class="btn secondary" onClick=${onClose}>Cancelar</button>
        <button class="btn primary" disabled=${!ok} onClick=${submit}>Añadir</button></div></div></${Modal}>`;
}
