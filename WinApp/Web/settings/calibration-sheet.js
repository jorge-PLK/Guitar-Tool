import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { Modal, AccentBar } from '../ui.js';
import { fmtPercent, fail } from './common.js';

const IDLE = { phase: 'idle' };

/// Hoja «Calibrar latencia» (CalibrationSheet del Mac): instrucciones, progreso y resultado en números, o el motivo del
/// fallo con qué hacer. Los textos de instrucciones y de fallo los manda el núcleo (con los literales del Mac).
export function CalibrationSheet({ instructions, block, onClose }) {
  const [cal, setCal] = useState(IDLE);
  const calRef = useRef(cal);
  calRef.current = cal;
  const running = cal.phase === 'running';
  useEffect(() => {
    const off = on('audio.calibration', c => setCal(c));
    // Como `onDisappear` del Mac: al salir se descarta el resultado (y se cancela si aún medía).
    return () => { off(); call(calRef.current.phase === 'running' ? 'audio.cancelCalibration' : 'audio.dismissCalibration').catch(() => {}); };
  }, []);
  const start = async () => {
    setCal({ phase: 'running', progress: 0 });
    try { setCal(await call('audio.calibrate', {}, { timeout: 60000 })); } catch (e) { setCal(IDLE); fail('No se pudo calibrar', e); }
  };
  const again = async () => { try { setCal(await call('audio.dismissCalibration').then(() => IDLE)); } catch { setCal(IDLE); } };
  return html`<${Modal} title="Calibrar latencia" width=${540} onClose=${running ? undefined : onClose}>
    ${cal.phase === 'idle' ? html`<${Instructions} lines=${instructions} block=${block} onCancel=${onClose} onStart=${start} />`
      : running ? html`<${Running} p=${cal.progress ?? 0} />`
      : html`<${Result} cal=${cal} onAgain=${again} onClose=${onClose} />`}
  <//>`;
}

function Instructions({ lines, block, onCancel, onStart }) {
  return html`<div class="cal-col">
    ${lines.map((t, i) => html`<p key=${i} class=${'cal-text' + (i === 2 ? ' muted' : '')}>${t}</p>`)}
    ${block ? html`<p class="cal-block">${block}</p>` : null}
    <div class="modal-actions"><button class="btn secondary" onClick=${onCancel}>Cancelar</button>
      <button class="btn primary" disabled=${!!block} onClick=${onStart}>Empezar</button></div></div>`;
}

function Running({ p }) {
  return html`<div class="cal-col">
    <p class="cal-text">Midiendo… no toques la guitarra ni muevas el cable.</p>
    <div class="cal-bar"><${AccentBar} fraction=${p} /></div>
    <span class="cal-pct">${fmtPercent(p)}</span></div>`;
}

function Result({ cal, onAgain, onClose }) {
  const ok = cal.outcome === 'success';
  return html`<div class="cal-col">
    ${ok ? html`<div class="cal-col tight"><span class="chip ok cal-chip">Calibrada</span>
        <div class="cal-rows">${cal.success.rows.map(r => html`<div class="cal-row" key=${r.label}>
          <span class="cal-row-label">${r.label}</span><span class="cal-row-value">${r.value}</span></div>`)}</div></div>`
      : cal.outcome === 'failure' ? html`<div class="cal-col tight"><h3 class="cal-fail">${cal.failure.title}</h3><p class="cal-text">${cal.failure.hint}</p></div>`
      : html`<div class="cal-col tight"><h3 class="cal-fail">No se pudo calibrar</h3><p class="cal-text">${cal.error}</p></div>`}
    <div class="modal-actions">${ok ? null : html`<button class="btn secondary" onClick=${onAgain}>Repetir</button>`}
      <button class="btn primary" onClick=${onClose}>Cerrar</button></div></div>`;
}
