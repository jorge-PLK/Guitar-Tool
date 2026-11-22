import { signal, effect } from '@preact/signals';
import { on } from '../bridge.js';
import { notify, info } from '../state.js';

// Estado compartido de la importación de listas (contrato W2-J, `playlist.*`): el indicador de la Biblioteca
// (`model.playlistImport?.indicator` del Mac), el aviso de «No se pudo separar…» y el reconocimiento de enlaces de lista.

/// `{ text, live }` mientras hay lista abierta con indicador (cápsula de la cabecera de la Biblioteca); null = nada que mostrar.
export const playlistIndicator = signal(null);

/// Tiempo de espera de `link.resolve` con un enlace de lista: el núcleo lee la lista entera antes de responder
/// (el límite normal del puente es CALL_TIMEOUT_MS = 15 s y una lista larga puede pasar de ahí). `link.cancel` la corta.
export const PLAYLIST_RESOLVE_TIMEOUT_MS = 300000;

const PLAYLIST_URL = [
  /^https?:\/\/(?:www\.|music\.|m\.)?youtube\.com\/playlist\b/i,
  /^https?:\/\/open\.spotify\.com\/(?:intl-[a-z-]+\/)?(?:playlist|album)\//i,
  /^spotify:(?:playlist|album):/i,
];
/// El enlace pedido es de una lista o álbum (lo mismo que decide `SourceInput.parse` del Mac): la página pinta «Leyendo la lista…».
export const isPlaylistURL = u => PLAYLIST_URL.some(r => r.test((u ?? '').trim()));

// «No se pudo separar <tema>: …» no es un fallo de la lista: el Mac lo notifica (`notify("No se pudo separar …")`).
let notified = new Set();
export function resetPlaylistNotices() { notified = new Set(); }

/// Aplica un Snapshot: indicador de la Biblioteca y avisos nuevos.
export function applySnapshot(s) {
  if (!s) return;
  playlistIndicator.value = s.indicator ? { text: s.indicator, live: !!s.isLive } : null;
  for (const w of s.warnings ?? []) {
    if (notified.has(w)) continue;
    notified.add(w);
    notify('error', w);
  }
}

/// La lista se descartó (cierre sin trabajo vivo, «Probar con otro enlace», cancelar la lectura).
export function clearPlaylist() { playlistIndicator.value = null; resetPlaylistNotices(); }

on('playlist.changed', applySnapshot);
// Recarga de la página con una lista viva en el núcleo: `app.info.playlist` la anuncia (cápsula de la Biblioteca).
effect(() => applySnapshot(info.value?.playlist));
