import { render } from 'preact';
import { html } from './html.js';
import { icon } from './icons.js';
import { on } from './bridge.js';
import {
  SCREENS, SETTINGS, screen, screenById, info, bootError, boot, go, loadLibrary,
  selectedEntry, detail, openProject, refreshDetail,
} from './state.js';
import { Library } from './screens/library.js';
import { Backing } from './screens/backing.js';
import { Tab } from './screens/tab.js';
import { Notices } from './ui.js';
import { ImportDuplicate, installFileDrop } from './screens/import-files.js';

function NavItem({ item }) {
  const active = screen.value === item.id;
  return html`<button class=${'nav-item' + (active ? ' active' : '')} aria-current=${active ? 'page' : undefined}
    onClick=${() => go(item.id)}>${icon(item.icon)}<span>${item.label}</span></button>`;
}

function SelectedCard() {
  const e = selectedEntry.value;
  if (!e) return null;
  const active = screen.value === 'library' && detail.value?.id === e.id;
  return html`<button class=${'sel-card' + (active ? ' active' : '')} title="Abrir la página del tema"
    aria-label=${'Tema seleccionado: ' + e.title} onClick=${() => openProject(e.id)}>
    <${Marquee} cls="t" text=${e.title} /><${Marquee} cls="a" text=${e.artist ?? ''} /></button>`;
}

/// MarqueeText del Mac: una línea con «…»; al pasar el ratón se desplaza hasta verse entera (30 px/s) y vuelve al salir.
const MARQUEE_SPEED = 30;
function Marquee({ text, cls }) {
  const move = (box, on) => {
    box.style.textOverflow = 'ellipsis'; box.style.textIndent = '0';
    const over = Math.max(0, box.scrollWidth - box.clientWidth);
    if (on && over > 0) {
      box.style.transition = `text-indent ${over / MARQUEE_SPEED}s linear`;
      box.style.textOverflow = 'clip'; box.style.textIndent = `${-over}px`;
    } else box.style.transition = 'text-indent .2s ease-out';
  };
  return html`<span class=${'marquee ' + cls} onMouseEnter=${e => move(e.currentTarget, true)} onMouseLeave=${e => move(e.currentTarget, false)}>
    <span class="marquee-in">${text || '\u00a0'}</span></span>`;
}

function DeviceCard() {
  // Como el Mac sin dispositivo elegido (AudioDeviceMonitor): «Salida del sistema · Por defecto» con punto verde.
  return html`<div class="device-card"><div class="row"><span class="dot ok" aria-hidden="true"></span><span>Salida del sistema</span></div>
    <div class="sub">Por defecto</div></div>`;
}

function Sidebar() {
  return html`<nav class="sidebar" aria-label="Secciones">
    <div class="logo">Tone<span>Forge</span></div>
    ${SCREENS.map(s => html`<${NavItem} key=${s.id} item=${s} />`)}
    <div class="nav-spacer"></div>
    <${NavItem} item=${SETTINGS} />
    <${SelectedCard} />
    <${DeviceCard} />
  </nav>`;
}

function Placeholder({ id }) {
  const s = screenById(id);
  return html`<div class="screen"><div class="placeholder">
    <div class="name">${s.label}</div><div>Esta pantalla llega en una parte posterior.</div></div></div>`;
}

function Main() {
  if (bootError.value) {
    return html`<div class="screen"><div class="placeholder">
      <div class="name">No se pudo arrancar</div>
      <div>${bootError.value.message} <code>(${bootError.value.code})</code></div>
      <button class="btn secondary" style="margin-top:12px" onClick=${boot}>Reintentar</button></div></div>`;
  }
  if (!info.value) return html`<div class="screen"></div>`;
  if (screen.value === 'backing') return html`<${Backing} />`;
  if (screen.value === 'tab') return html`<${Tab} />`;
  return screen.value === 'library' ? html`<${Library} />` : html`<${Placeholder} id=${screen.value} />`;
}

function App() {
  return html`<${Sidebar} /><main class="main"><${Main} /></main><${Notices} /><${ImportDuplicate} />`;
}

on('library.changed', () => { loadLibrary(); refreshDetail(); });
installFileDrop();
render(html`<${App} />`, document.getElementById('app'));
boot();
