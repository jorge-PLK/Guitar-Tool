// Barra de grabación (RecordBar) y líneas de estado (RecordBody.status) del Mac.
import { useRef, useEffect, useLayoutEffect } from 'preact/hooks';
import { html } from '../html.js';
import { snap, audioInfo, locked, pos, onPosition, startTake, stopTake, setStartSection, setCountIn, setPreRoll, setPunch, selectTake } from './store.js';
import { fmtDuration } from './bits.js';

/// RecordStatus.uncalibratedWarning del Mac.
const UNCALIBRATED = 'Sin calibrar: la toma puede ir desfasada decenas de ms; se corregirá al calibrar.';
const AUDIO_ONLY = 'Se grabará solo el audio.';

/// Reloj «0:00 / 5:23»; la posición se pinta sin re-render.
function Clock({ total }) {
  const el = useRef(null);
  useEffect(() => {
    const paint = () => { if (el.current) el.current.textContent = fmtDuration(pos.seconds); };
    paint();
    return onPosition(paint);
  }, []);
  return html`<span class="rec-clock" title=${snap.value.plannedStop == null ? 'Duración del tema' : 'Para sola al acabar la sección más el margen'}>
    <span class="now" ref=${el}>0:00</span><span class="total"> / ${fmtDuration(total)}</span></span>`;
}

/// Mac: `.minimumScaleFactor(0.75)`; el texto se encoge hasta el 75 % antes de salirse de la barra.
const MIN_SCALE = 0.75;
function OffsetLabel() {
  const d = snap.value.camera?.defaultOffsetMs;
  const el = useRef(null);
  const ms = d == null ? null : Math.round(d);
  useLayoutEffect(() => {
    const label = el.current;
    if (!label) return undefined;
    const fit = () => {
      label.style.fontSize = '';
      const room = label.parentElement.clientWidth - [...label.parentElement.children].filter(c => c !== label && !c.classList.contains('grow'))
        .reduce((w, c) => w + c.offsetWidth + 14, 0) - 14;
      const need = label.scrollWidth;
      if (need > room && room > 0) label.style.fontSize = `${Math.max(MIN_SCALE, room / need) * 13}px`;
    };
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(label.parentElement);
    return () => ro.disconnect();
  }, [ms]);
  if (ms == null) return null;
  return html`<span ref=${el} class=${'rec-offset-label' + (ms === 0 ? '' : ' set')}>${ms === 0 ? 'Desfase de la cámara: sin ajustar' : `Desfase de la cámara: ${ms > 0 ? '+' : ''}${ms} ms`}</span>`;
}

export function RecordBar() {
  const s = snap.value;
  const blocked = s.phase === 'idle' && !!s.blockReason;
  const recording = s.phase === 'recording' || s.phase === 'counting';
  const off = blocked || s.phase === 'finishing' || s.phase === 'adjusting';
  const part = s.parts.find(p => p.id === s.activePartId);
  const busy = locked.value;
  const punchOn = !!s.punch?.enabled;
  const togglePunch = on => {
    if (on && !s.selectedTakeId && part?.bestTakeId) selectTake(part.bestTakeId);
    setPunch({ enabled: on });
  };
  return html`<section class="rec-bar" aria-label="Grabación">
    <div class="rec-bar-row">
      <button class=${'rec-btn' + (off ? ' off' : '')} disabled=${off} onClick=${() => (recording ? stopTake() : startTake())}
        aria-label=${recording ? 'Parar la grabación' : 'Grabar'}>
        ${recording ? html`<i class="sq"></i>` : html`<i class="dot"></i>`}<span>${recording ? 'Parar' : 'Grabar'}</span></button>
      <${Clock} total=${s.plannedStop ?? s.duration} />
      <span class="grow"></span>
      <${OffsetLabel} />
    </div>
    <div class="rec-opts">
      <label class="labeled rec-opt">Empezar en
        <select class="select" disabled=${busy || punchOn} value=${s.startSectionId ?? ''}
          onChange=${e => setStartSection(e.currentTarget.value || null)}>
          <option value="">Principio</option>
          ${s.sections.map(x => html`<option value=${x.id}>${x.name}</option>`)}</select></label>
      <label class=${'check rec-opt' + (busy ? ' disabled' : '')}><input type="checkbox" checked=${s.countIn} disabled=${busy}
        onChange=${e => setCountIn(e.currentTarget.checked)} />Cuenta de 1 compás</label>
      <label class="labeled rec-opt">Margen
        <select class="select" disabled=${busy} value=${String(s.preRollBars)} onChange=${e => setPreRoll(+e.currentTarget.value)}>
          <option value="2">2 compases</option><option value="1">1 compás</option><option value="0">Sin margen</option></select></label>
      <label class=${'check rec-opt' + (busy || !part?.takes?.length ? ' disabled' : '')} title="Vuelve a grabar un tramo de una toma">
        <input type="checkbox" checked=${punchOn} disabled=${busy || !(part?.takes?.length)} onChange=${e => togglePunch(e.currentTarget.checked)} />Punch-in</label>
    </div></section>`;
}

export function Status() {
  const s = snap.value;
  const a = audioInfo.value;
  const cam = s.camera ?? {};
  const line = (t, cls) => html`<p class=${'rec-line ' + cls} key=${cls + t}>${t}</p>`;
  const withAudioOnly = m => (m.includes(AUDIO_ONLY) ? m : `${m} ${AUDIO_ONLY}`);
  const lines = [];
  if (s.blockReason) lines.push(line(s.blockReason, 'muted'));
  if (!s.blockReason && s.phase === 'idle' && !a.calibrationValid) lines.push(line(UNCALIBRATED, 'accent'));
  if (cam.state === 'none' || cam.state === 'failed') lines.push(line(withAudioOnly(cam.message ?? ''), 'accent'));
  if (cam.state === 'denied') lines.push(line(cam.message ?? `Sin permiso de cámara: ${AUDIO_ONLY.toLowerCase()}`, 'accent'));
  for (const m of s.messages ?? []) lines.push(line(m, 'accent'));
  for (const m of s.notices ?? []) lines.push(line(m, 'accent'));
  if (s.loadError) lines.push(line(s.loadError, 'danger'));
  if (s.takeSaveError) lines.push(line(s.takeSaveError, 'danger'));
  return lines.length ? html`<div class="rec-status" role="status">${lines}</div>` : null;
}
