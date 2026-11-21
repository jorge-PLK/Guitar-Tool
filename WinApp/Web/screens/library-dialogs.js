import { useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call } from '../bridge.js';
import { Modal } from '../ui.js';
import { icon } from '../icons.js';
import { loadLibrary, forgetProject, refreshDetail } from '../state.js';

const errText = e => e?.message || String(e);

/// Campos «Título» y «Artista» con el botón de intercambiar (SongInfoFields del Mac); los comparten la hoja y la página del tema.
export function SongInfoFields({ title, artist, setTitle, setArtist, onSubmit, autofocus = false }) {
  const onKey = e => { if (e.key === 'Enter') { e.preventDefault(); onSubmit(); } };
  return html`<div class="info-fields">
    <div class="info-fields-col">
      <label class="field"><span>Título</span><input value=${title} autofocus=${autofocus} onInput=${e => setTitle(e.currentTarget.value)} onKeyDown=${onKey} /></label>
      <label class="field"><span>Artista</span><input value=${artist} onInput=${e => setArtist(e.currentTarget.value)} onKeyDown=${onKey} /></label>
    </div>
    <button class="swap-btn" aria-label="Intercambiar título y artista" title="Intercambiar título y artista"
      onClick=${() => { setTitle(artist); setArtist(title); }}>${icon('swap', 16)}</button></div>`;
}

/// Guarda título y artista (library.rename). Artista vacío = sin artista. Devuelve el texto de error o null.
export async function saveSongInfo(id, title, artist) {
  try {
    await call('library.rename', { id, title, artist: artist.trim() === '' ? null : artist });
    await loadLibrary(); refreshDetail();
    return null;
  } catch (e) {
    return e.code === 'empty-title' ? 'El título no puede quedar vacío.' : errText(e);
  }
}

/// «Corregir título y artista» (SongInfoSheet del Mac) -> library.rename.
export function RenameSheet({ id, title: t0, artist: a0, onClose }) {
  const [title, setTitle] = useState(t0 ?? '');
  const [artist, setArtist] = useState(a0 ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const canSave = title.trim() !== '' && !busy;
  const save = async () => {
    if (!canSave) return;
    setBusy(true); setError(null);
    const err = await saveSongInfo(id, title, artist);
    if (err) { setError(err); setBusy(false); } else onClose();
  };
  return html`<${Modal} title="Corregir título y artista" width=${520} onClose=${busy ? null : onClose} autofocus="input">
    <${SongInfoFields} title=${title} artist=${artist} setTitle=${setTitle} setArtist=${setArtist} onSubmit=${save} />
    ${error ? html`<div class="modal-error" role="alert">${error}</div>` : null}
    <div class="modal-actions">
      <button class="btn secondary sm" onClick=${onClose} disabled=${busy}>Cancelar</button>
      <button class="btn primary" onClick=${save} disabled=${!canSave}>Guardar</button></div></${Modal}>`;
}

/// Tema repetido al importar un fichero (alerta del Mac, RootView.swift).
export function DuplicateDialog({ id, onOpen, onClose }) {
  return html`<${Modal} title="Este tema ya está en la biblioteca" width=${480} onClose=${onClose} autofocus=".primary">
    <p>Ya hay un proyecto con el mismo audio (mismo SHA-256) o con el mismo vídeo de origen. ¿Quieres abrirlo?</p>
    <div class="modal-actions">
      <button class="btn secondary sm" onClick=${onClose}>Cancelar</button>
      <button class="btn primary sm" onClick=${() => { onClose(); onOpen(id); }}>Abrir el existente</button></div></${Modal}>`;
}

/// Lo que se va con el tema (TrashRequest.contents del Mac).
export function trashContents(stems, takes, videos) {
  const parts = [stems === 0 ? 'sus stems' : stems === 1 ? '1 stem' : `${stems} stems`];
  if (takes > 0) parts.push(takes === 1 ? '1 toma' : `${takes} tomas`);
  if (videos > 0) parts.push(videos === 1 ? '1 vídeo' : `${videos} vídeos`);
  return parts.join(', ');
}

/// Confirmación de borrado: Mover a la Papelera / Eliminar del disco / Cancelar -> library.trash | library.delete.
export function TrashDialog({ entry, onClose }) {
  const [videos, setVideos] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  useEffect(() => {
    call('library.project', { id: entry.id }).then(d => setVideos(d.videoCount ?? 0)).catch(() => {});
  }, [entry.id]);
  const run = async method => {
    setBusy(true); setError(null);
    try {
      await call(method, { id: entry.id });
      forgetProject(entry.id);
      await loadLibrary();
      onClose();
    } catch (e) { setError(errText(e)); setBusy(false); }
  };
  return html`<${Modal} title=${`¿Eliminar “${entry.title}”?`} width=${640} onClose=${busy ? null : onClose} autofocus=".primary">
    <p>Se va con el tema: ${trashContents(entry.stemCount, entry.takeCount, videos)}. Si se está separando o está abierto en Backing, se detiene primero.${'\n'}Eliminar del disco no se puede deshacer. La Papelera conserva la carpeta hasta que la vacíes.</p>
    ${error ? html`<div class="modal-error" role="alert">${error}</div>` : null}
    <div class="modal-actions nowrap">
      <button class="btn primary sm" onClick=${() => run('library.trash')} disabled=${busy}>Mover a la Papelera</button>
      <button class="btn danger sm" onClick=${() => run('library.delete')} disabled=${busy}>Eliminar del disco</button>
      <button class="btn secondary sm" onClick=${onClose} disabled=${busy}>Cancelar</button></div></${Modal}>`;
}

/// «Limpiar…» (confirmationDialog de LibraryView del Mac): `bytes` ya formateados -> library.cleanup.
export function CleanupDialog({ id, title, bytes, onClose }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const run = async () => {
    setBusy(true); setError(null);
    try {
      await call('library.cleanup', { id });
      await loadLibrary(); refreshDetail();
      onClose();
    } catch (e) { setError(`No se pudo limpiar: ${errText(e)}`); setBusy(false); }
  };
  return html`<${Modal} title=${title} width=${520} onClose=${busy ? null : onClose} autofocus=".secondary">
    <p>Se borrarán tomas descartadas y stems por ${bytes}. Los stems se pueden volver a generar.</p>
    ${error ? html`<div class="modal-error" role="alert">${error}</div>` : null}
    <div class="modal-actions">
      <button class="btn secondary sm" onClick=${onClose} disabled=${busy}>Cancelar</button>
      <button class="btn danger sm" onClick=${run} disabled=${busy}>Limpiar ${bytes}</button></div></${Modal}>`;
}

/// «¿Eliminar la toma?» (confirmationDialog de ProjectRecordingsView del Mac) -> library.deleteTake.
export function DeleteTakeDialog({ id, takeId, label, onClose }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const run = async () => {
    setBusy(true); setError(null);
    try {
      await call('library.deleteTake', { id, takeId });
      await loadLibrary(); refreshDetail();
      onClose();
    } catch (e) { setError(`No se pudo eliminar la toma (${errText(e)}).`); setBusy(false); }
  };
  return html`<${Modal} title="¿Eliminar la toma?" width=${520} onClose=${busy ? null : onClose} autofocus=".secondary">
    <p>Se borra su carpeta (audio y vídeo). No se puede deshacer.</p>
    ${error ? html`<div class="modal-error" role="alert">${error}</div>` : null}
    <div class="modal-actions">
      <button class="btn secondary sm" onClick=${onClose} disabled=${busy}>Cancelar</button>
      <button class="btn danger sm" onClick=${run} disabled=${busy}>Eliminar ${label}</button></div></${Modal}>`;
}

/// Primera ejecución sin carpeta de proyectos (FirstRunSheet del Mac) -> host.pickProjectsFolder.
export function FirstRunSheet() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [restart, setRestart] = useState(false);
  const choose = async () => {
    setBusy(true); setError(null);
    try {
      const r = await call('host.pickProjectsFolder', {}, { timeout: 10 * 60 * 1000 });
      if (r.path && r.restartRequired) setRestart(true);
      else if (r.path) await loadLibrary();
    } catch (e) { setError(e.code === 'unsupported' ? 'Este anfitrión no puede elegir la carpeta. Arranca con --projects-folder.' : errText(e)); }
    setBusy(false);
  };
  return html`<${Modal} title=${restart ? 'Reinicia ToneForge' : 'Elige tu carpeta de proyectos'} width=${480}>
    ${restart
      ? html`<p class="body-text">Carpeta guardada. Cierra ToneForge y vuelve a abrirlo para empezar a usarla.</p>`
      : html`<p>Cada tema vive en su propia carpeta, con sus stems, tomas y vídeo. Puedes cambiarla más tarde en Ajustes.</p>`}
    ${error ? html`<div class="modal-error" role="alert">${error}</div>` : null}
    ${restart ? null : html`<div class="modal-actions"><button class="btn primary" onClick=${choose} disabled=${busy}>Elegir carpeta…</button></div>`}
  </${Modal}>`;
}
