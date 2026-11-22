import { html } from '../html.js';
import { transportName } from '../bridge.js';
import { settingsTab } from '../state.js';
import { AudioSettings } from '../settings/audio.js';
import { VideoSettings } from '../settings/video.js';
import { LibrarySettings } from '../settings/library.js';

if (transportName() === 'mock') await import('../mock/settings.js');   // simulador de settings.* (solo con --mock)

/// Pestañas de Ajustes (SettingsTab del Mac, mismo orden y nombres).
const TABS = [
  { id: 'audio', label: 'Audio', view: AudioSettings },
  { id: 'video', label: 'Cámara y vídeo', view: VideoSettings },
  { id: 'library', label: 'Biblioteca', view: LibrarySettings },
];

/// Pantalla Ajustes (App/Sources/SettingsView.swift).
export function Settings() {
  const current = TABS.find(t => t.id === settingsTab.value) ?? TABS[0];
  const View = current.view;
  return html`<div class="screen settings screen-scroll">
    <div class="settings-inner">
      <header><h1 class="settings-title">Ajustes</h1>
        <p class="page-sub">Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo.</p></header>
      <div class="stabs" role="tablist">${TABS.map(t => html`<button key=${t.id} role="tab" aria-selected=${t === current ? 'true' : 'false'}
        class=${t === current ? 'on' : ''} onClick=${() => { settingsTab.value = t.id; }}>${t.label}</button>`)}</div>
      <${View} key=${current.id} />
    </div></div>`;
}
