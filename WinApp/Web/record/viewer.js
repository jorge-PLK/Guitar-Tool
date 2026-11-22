// Visor «Ver toma» (TakeViewer del Mac): vídeo y audio procesado sincronizados, reproducir/pausa, barra de posición,
// marcar como mejor, eliminar y cerrar. No decide nada por su cuenta: quien lo abre ejecuta las acciones.
//
// W2-V: la toma y el backing suenan en el núcleo (`takeview.*`, como el `AVPlayer` único del Mac); el `<video>` sigue a ese
// reloj (CoreTakeSync en take-sync.js). «Backing» encendido al abrir, como en el Mac; apagado = «Backing mudo».
import { Fragment } from 'preact';
import { useState } from 'preact/hooks';
import { html } from '../html.js';
import { Modal } from '../ui.js';
import { RIcon } from './bits.js';
import { useCoreTakePlayer, TakeScreen } from './take-screen.js';
import { snap } from './store.js';

/// `take`: {id, videoPath, songStart, videoOffsetMs, videoRotation, punches:[{start,end,videoPath,videoOffsetMs}]}.
export function TakeViewer({ title, isBest, take, onMarkBest, onDelete, onClose }) {
  const [confirm, setConfirm] = useState(false);
  const player = useCoreTakePlayer({ projectId: snap.value.projectId, takeId: take.id, videoPath: take.videoPath, punches: take.punches,
    offsetMs: take.videoOffsetMs ?? 0 });
  const max = Math.max(player.d, 0.1);
  const close = () => onClose();
  const confirmSheet = confirm ? html`<${Modal} title="¿Eliminar la toma?" width=${420} onClose=${() => setConfirm(false)} labelledBy="rec-viewdel-title">
      <p>Se borra su carpeta (audio y vídeo). No se puede deshacer.</p>
      <div class="modal-actions"><button class="btn secondary" onClick=${() => setConfirm(false)}>Cancelar</button>
        <button class="btn danger" onClick=${() => onDelete()}>Eliminar toma</button></div></${Modal}>` : null;
  return html`<${Fragment}><${Modal} title=${title} width=${720} onClose=${close} labelledBy="rec-view-title">
    <div class="rec-sheet rec-viewer">
      <div class="rec-vhead"><span class="rec-vtitle">${title}</span>
        ${isBest ? html`<span class="rec-chip ok">★ mejor</span>` : null}<span class="grow"></span>
        <button class="rec-x" title="Cerrar" aria-label="Cerrar" onClick=${close}>${RIcon.close(13)}</button></div>
      <${TakeScreen} player=${player} rotation=${take.videoRotation ?? 0}>
        ${player.error ? null : player.ready && !player.hasVideo ? html`<span class="rec-tmsg muted">Sin vídeo: solo audio</span>`
          : !player.ready ? html`<span class="spinner" aria-hidden="true"></span>` : null}</${TakeScreen}>
      <div class="rec-vctl">
        <button class="rec-vplay" disabled=${!player.ready} onClick=${player.toggle} aria-label=${player.playing ? 'Pausa' : 'Reproducir'}>
          ${player.playing ? RIcon.pause(15) : RIcon.play(15)}</button>
        <span class="rec-vtime">${fmtClockT(player.t)}</span>
        <input type="range" class="rec-range rec-vslider" min="0" max=${max} step="0.01" value=${Math.min(player.t, max)} disabled=${!player.ready}
          style=${`--p:${(Math.min(player.t, max) / max) * 100}%`} aria-label="Posición" onInput=${e => player.seek(+e.currentTarget.value)} />
        <span class="rec-vtime">${fmtClockT(player.d)}</span>
        <button class="rec-backing" disabled=${!player.ready || !player.hasBacking} onClick=${player.toggleBacking}
          title=${player.backingOn ? 'Silenciar el backing' : 'Oír el backing'} style=${player.backingOn ? null : 'color:var(--accent)'}>
          ${RIcon.speaker(14, player.backingOn)}<span>${player.backingOn ? 'Backing' : 'Backing mudo'}</span></button></div>
      ${player.error ? html`<p class="rec-line danger">${player.error}</p>` : null}
      <div class="rec-vactions">
        <button class="btn secondary" disabled=${isBest} onClick=${onMarkBest}>Marcar como mejor</button><span class="grow"></span>
        <button class="btn secondary" onClick=${() => setConfirm(true)}>Eliminar…</button></div></div></${Modal}>${confirmSheet}</${Fragment}>`;
}

/// Fmt.clock del Mac (m:ss truncado).
const fmtClockT = s => { const t = Math.floor(Math.max(s || 0, 0)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
