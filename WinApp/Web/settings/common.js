import { html } from '../html.js';
import { notify } from '../state.js';

/// ByteCountFormatter(.file) del Mac (Fmt.bytes): bytes enteros, KB sin decimales, MB con 1, GB con 2 hasta 10 y 1 después.
export const fmtBytes = n => {
  if (n === 1) return '1 byte';
  if (n < 1000) return `${n} bytes`;
  const units = [['KB', 0], ['MB', 1], ['GB', 2], ['TB', 2]];
  let v = n / 1000, i = 0;
  const digits = k => (k === 2 && v >= 10 ? 1 : units[k][1]);
  while (i < units.length - 1 && Number(v.toFixed(digits(i))) >= 1000) { v /= 1000; i++; }
  return `${v.toLocaleString('es-ES', { maximumFractionDigits: digits(i) })} ${units[i][0]}`;
};
export const fmtPercent = f => `${Math.round(f * 100)} %`;
export const errText = e => e?.message || String(e);
export const fail = (title, e) => notify('error', `${title}: ${errText(e)}`);

/// SettingsGroup del Mac: tarjeta con título, nota y contenido.
export function Group({ title, note, children }) {
  return html`<section class="card sgroup"><div class="sgroup-head"><h2>${title}</h2><p>${note}</p></div>${children}</section>`;
}

/// InfoRow del Mac: etiqueta a la izquierda y control o valor a la derecha, sobre fondo de campo.
export function InfoRow({ label, children }) {
  return html`<div class="inforow"><span class="inforow-label">${label}</span><span class="inforow-trail">${children}</span></div>`;
}

/// Picker desplegable del Mac. options: [{value, label}]; `value` se compara como texto.
/// Ancho al contenido: el de la opción más larga (<select> nativo); el tope (320 pt) lo pone CSS (`.inforow .popup`).
export function Select({ label, value, options, onChange, disabled }) {
  const text = String(value ?? '');
  return html`<select class="popup" aria-label=${label} disabled=${disabled}
    value=${text} onChange=${e => onChange(e.currentTarget.value)}>
    ${options.map(o => html`<option key=${o.value} value=${String(o.value)} selected=${String(o.value) === text}>${o.label}</option>`)}</select>`;
}

/// Toggle(.switch) del Mac.
export function Switch({ label, on, onChange }) {
  return html`<button class=${'switch' + (on ? ' on' : '')} role="switch" aria-checked=${on ? 'true' : 'false'} aria-label=${label}
    onClick=${() => onChange(!on)}><span class="knob"></span></button>`;
}
