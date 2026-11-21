import { html } from './html.js';

// Iconos de trazo (24x24, stroke currentColor), estilo del boceto.
const svg = (size, body) => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

const paths = {
  library: html`<path d="M3 7h10M3 12h10M3 17h5"/><path d="M18 17V6c0 2 3 2.5 3 5"/><circle cx="15.5" cy="17" r="2.5" fill="currentColor"/>`,
  backing: html`<path d="M5 3v18M12 3v18M19 3v18"/><rect x="2.8" y="13" width="4.4" height="4" rx="1.5" fill="currentColor"/><rect x="9.8" y="7" width="4.4" height="4" rx="1.5" fill="currentColor"/><rect x="16.8" y="11" width="4.4" height="4" rx="1.5" fill="currentColor"/>`,
  tab: html`<path d="M7 17V6l9-1.5V15"/><path d="M7 9l9-1.5"/><circle cx="5" cy="17.5" r="2.3" fill="currentColor"/><circle cx="14" cy="16" r="2.3" fill="currentColor"/><path d="M21 17V9" /><circle cx="19" cy="17.5" r="2.3" fill="currentColor"/>`,
  record: html`<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4.5" fill="currentColor"/>`,
  montage: html`<rect x="2" y="3" width="20" height="18" rx="2"/><path d="M7 3v18M17 3v18M2 8h5M2 12h5M2 16h5M17 8h5M17 12h5M17 16h5"/>`,
  settings: html`<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>`,
  search: html`<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>`,
  trash: html`<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6"/>`,
  folder: html`<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>`,
  pencil: html`<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>`,
  chevronLeft: html`<path d="M15 18l-6-6 6-6"/>`,
  close: html`<path d="M18 6L6 18M6 6l12 12"/>`,
  check: html`<circle cx="12" cy="12" r="10"/><path d="M8 12l3 3 5-6"/>`,
  info: html`<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>`,
  warning: html`<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01"/>`,
  external: html`<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14L21 3"/>`,
  play: html`<path d="M7 4l13 8-13 8z" fill="currentColor"/>`,
  swap: html`<path d="M8 20V4M4 8l4-4 4 4M16 4v16M12 16l4 4 4-4"/>`,
  person: html`<circle cx="12" cy="8" r="4" fill="currentColor"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7z" fill="currentColor"/>`,
  undo: html`<path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>`,
  redo: html`<path d="M15 14l5-5-5-5"/><path d="M20 9H9.5a5.5 5.5 0 0 0 0 11H13"/>`,
  plus: html`<path d="M12 5v14M5 12h14"/>`,
  minus: html`<path d="M5 12h14"/>`,
  music: html`<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>`,
};

export const icon = (name, size = 18) => svg(size, paths[name]);
