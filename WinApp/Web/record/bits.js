// Piezas pequeñas de Grabar: iconos (SF Symbols del Mac) y formatos.
import { html } from '../html.js';

export const RIcon = {
  /// `video` fino de 40 pt de la vista previa.
  video: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linejoin="round">
    <rect x="1.5" y="5.5" width="14" height="13" rx="3.2"/><path d="M16.5 10.2l5.2-3.2v10l-5.2-3.2z"/></svg>`,
  rotate: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="2 3 20 19" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
    <rect x="9.5" y="10.5" width="11" height="10.5" rx="2.4"/><path d="M3.5 12.5v-.6a5 5 0 0 1 5-5H13"/><path d="M10.8 4l2.9 2.9-2.9 2.9"/></svg>`,
  play: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24"><path d="M6 3.5l15 8.5-15 8.5z" fill="currentColor"/></svg>`,
  pause: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24"><rect x="5" y="3.5" width="5" height="17" rx="1.2" fill="currentColor"/><rect x="14" y="3.5" width="5" height="17" rx="1.2" fill="currentColor"/></svg>`,
  playpause: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24"><path d="M2 5l10 7-10 7z" fill="currentColor"/><rect x="14" y="5" width="3.2" height="14" rx="1" fill="currentColor"/><rect x="19" y="5" width="3.2" height="14" rx="1" fill="currentColor"/></svg>`,
  begin: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24"><rect x="3" y="5" width="3" height="14" rx="1" fill="currentColor"/><path d="M21 5v14L8.5 12z" fill="currentColor" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>`,
  close: size => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg>`,
  speaker: (size, on) => html`<svg aria-hidden="true" width=${size} height=${size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d="M3 9.5h4l5-4v13l-5-4H3z" fill="currentColor"/>${on ? html`<path d="M16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11"/>` : html`<path d="M16 9.5l5 5M21 9.5l-5 5"/>`}</svg>`,
};

/// Fmt.duration del Mac (m:ss redondeado) y Fmt.clock (m:ss truncado).
export const fmtDuration = s => { const t = Math.round(Math.max(s || 0, 0)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
/// PunchTimeline.summary: m:ss,d con coma.
export const fmtPunch = t => (t == null ? '—' : `${Math.floor(t / 60)}:${(t % 60).toFixed(1).padStart(4, '0').replace('.', ',')}`);
/// Número con hasta un decimal y coma (Fotograma = 33,3 ms).
export const fmtMs = v => (Math.round(v * 10) / 10).toString().replace('.', ',');
export const TF_PALETTE = ['#6C9BD2', '#6FB58A', '#9C86C9', '#C97F9E', '#5DB5B5', '#A6B85C', '#C8706A'];
