import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { AccentBar } from '../ui.js';
import { entries, selectedEntry, go, loaded } from '../state.js';
import {
  target, status, openError, snap, exportStatus, isExporting, previewReady, sheetTake, actionError, openMontage, closeMontage,
  startExport, cancelExport, dismissExport, reveal, togglePlay,
} from '../montage/store.js';
import { LayoutColumn, PreviewColumn, SettingsColumn } from '../montage/columns.js';
import { Timeline } from '../montage/timeline.js';
import { FramingSheet } from '../montage/sheet.js';
import { COMPACT_WIDTH, fmtPercent, num1 } from '../montage/model.js';

/// Mac (MontageBody): alto mínimo de la zona de columnas y tope en portrait.
const PREVIEW_MIN_HEIGHT = 420, PORTRAIT_MAX_HEIGHT = 440;

/// Tema de Montaje: el último elegido (el mismo que Backing); si no, el seleccionado en la biblioteca.
const resolveTarget = () => target.value ?? selectedEntry.value?.id ?? null;

function Chooser() {
  const withTakes = entries.value.filter(e => e.takeCount > 0);
  return html`<div class="screen montage"><div class="mt-chooser">
    <h1 class="page-title">Montaje</h1>
    ${!loaded.value ? null : withTakes.length === 0
      ? html`<p class="muted">Aún no hay temas con tomas grabadas. Graba alguna parte con vídeo en Grabar.</p>
        <button class="btn secondary" onClick=${() => go('record')}>Ir a Grabar</button>`
      : html`<p class="muted">Elige un tema</p>
        <div class="chooser-list">${withTakes.map(e => html`<button class="chooser-item" key=${e.id} onClick=${() => { target.value = e.id; }}>
          <span>${e.title}</span><span class="muted"></span></button>`)}</div>`}
  </div></div>`;
}

function ExportStatus() {
  const e = exportStatus.value;
  if (e.phase === 'running') {
    return html`<div class="mt-export running" role="status"><span class="st">${e.stage ?? 'Exportando'}…</span>
      <div class="bar-wrap"><${AccentBar} fraction=${e.progress} /></div><span class="pc muted">${fmtPercent(e.progress)}</span></div>`;
  }
  if (e.phase === 'done' && e.result) {
    const r = e.result;
    const line = (text, cls) => html`<div class=${'small ' + cls}>${text}</div>`;
    return html`<div class="mt-export done" role="status">
      <div class="top"><span class="ok">${icon('check', 18)}</span><span class="path" title=${r.path}>Vídeo exportado: ${r.path}</span>
        <button class="btn secondary sm" onClick=${reveal}>Mostrar en carpeta</button>
        <button class="btn secondary sm" onClick=${dismissExport}>Cerrar</button></div>
      ${r.finalLUFS != null ? line(`Sonoridad final: ${num1(r.finalLUFS)} LUFS · pico real ${num1(r.finalTruePeakDB)} dBTP`
        + (r.normalized ? (r.limiterEnabled ? (r.limiterApplied ? ` · limitador −${num1(r.limiterMaxReductionDB)} dB` : ' · limitador sin actuar') : '') : ' (sin normalizar)'), 'muted') : null}
      ${r.limitedByPeak ? line('Se limitó la ganancia para no pasar de −1 dBTP: la mezcla queda por debajo de −14 LUFS.', 'accent-text') : null}
      ${r.limiterOutOfTolerance ? line('El limitador no llegó a −14 LUFS y −1 dBTP a la vez: la mezcla queda en los valores mostrados.', 'accent-text') : null}
      ${(r.clippedFiles ?? []).length ? line(r.clippedFiles.map(f => `${f}: recortado`).join(' · '), 'accent-text') : null}
      ${r.tracksDirectory ? line(`WAV por pista en ${r.tracksDirectory}`, 'muted') : null}
    </div>`;
  }
  if (e.phase === 'failed') {
    return html`<div class="mt-export failed" role="alert"><span class="small danger-text">${e.message ?? 'No se pudo exportar el vídeo.'}</span>
      <span class="grow"></span><button class="btn secondary sm" onClick=${dismissExport}>Cerrar</button></div>`;
  }
  if (e.phase === 'cancelled') {
    return html`<div class="mt-export" role="status"><span class="small muted">Exportación cancelada.</span>
      <span class="grow"></span><button class="btn secondary sm" onClick=${dismissExport}>Cerrar</button></div>`;
  }
  return null;
}

function Body() {
  const s = snap.value;
  const row = useRef(null);
  const [compact, setCompact] = useState(false);
  useEffect(() => {
    if (!row.current) return undefined;
    const ro = new ResizeObserver(([en]) => setCompact(en.contentRect.width < COMPACT_WIDTH));
    ro.observe(row.current);
    return () => ro.disconnect();
  }, [s.hasPlan]);
  const noVideo = !s.hasPlan || !s.lanes.some(l => l.hasVideo);
  const audioOnly = s.audioOnlyParts ?? [];
  const previewErr = s.preview?.phase === 'error' ? s.preview.error : null;
  const audioErr = s.transport?.audioError;
  const n = s.lanes.length;
  const songLine = [s.artist, s.title, `${n} ${n === 1 ? 'toma' : 'tomas'}`].filter(Boolean).join(' · ');
  const exporting = isExporting.value;
  return html`<div class="screen montage ${compact ? 'compact' : ''}">
    <div class="mt-head">
      <div><div class="muted song">${songLine}</div><h1 class="page-title mt-title">Montaje</h1></div>
      <span class="grow"></span>
      ${exporting ? html`<button class="btn secondary" onClick=${cancelExport}>Cancelar exportación</button>`
        : html`<button class="btn primary" disabled=${!s.export.canExport} title=${s.export.canExport || !s.framing?.some(f => f.status === 'analyzing') ? '' : 'Espera a que termine el análisis del encuadre'}
          onClick=${startExport}>Exportar vídeo</button>`}
    </div>
    <div class="mt-notices">
      ${audioOnly.length ? html`<div class="small accent-text">Sin vídeo (solo audio, sin recuadro): ${audioOnly.join(', ')}.</div>` : null}
      ${previewErr ? html`<div class="small danger-text">${previewErr}</div>` : null}
      ${audioErr ? html`<div class="small danger-text">${audioErr}</div>` : null}
      ${actionError.value ? html`<div class="small danger-text">${actionError.value}
        <button class="mt-link" onClick=${() => { actionError.value = null; }}>Cerrar</button></div>` : null}
      <${ExportStatus} />
    </div>
    ${noVideo ? html`<section class="card mt-empty"><h2>Aún no hay tomas con vídeo</h2>
      <p class="muted">El montaje usa la mejor toma de cada parte. Graba alguna parte con la cámara y vuelve.</p>
      <div><button class="btn secondary" onClick=${() => go('record')}>Ir a Grabar</button></div></section>`
      : html`<div class="mt-scroll">
        <div class="mt-cols" ref=${row} style=${`min-height:${PREVIEW_MIN_HEIGHT}px` + (s.isPortrait ? `;max-height:${PORTRAIT_MAX_HEIGHT}px` : '')}>
          <${LayoutColumn} /><${PreviewColumn} /><${SettingsColumn} /></div>
        <${Timeline} /></div>`}
    ${sheetTake.value ? html`<${FramingSheet} />` : null}
  </div>`;
}

export function Montage() {
  const id = resolveTarget();
  useEffect(() => {
    if (!id) return undefined;
    openMontage(id);
    return () => { closeMontage(); };
  }, [id]);
  // Barra espaciadora = reproducir/pausar (como Backing), salvo escribiendo o con una hoja abierta.
  useEffect(() => {
    const onKey = e => {
      if (e.code !== 'Space' || e.repeat || e.ctrlKey || e.metaKey || e.altKey) return;
      const tag = e.target?.tagName;
      if ((tag === 'INPUT' && e.target.type !== 'range') || tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'BUTTON') return;
      if (status.value !== 'ready' || sheetTake.value || !previewReady.value) return;
      e.preventDefault();
      togglePlay();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
  // Gancho de QA (`?msheet=1`): abre la hoja de encuadre de la primera toma con vídeo, una vez por carga.
  useEffect(() => {
    if (status.value !== 'ready' || !new URLSearchParams(location.search).get('msheet') || Montage.sheetDone) return;
    Montage.sheetDone = true;
    const l = snap.value?.lanes.find(x => x.hasVideo);
    if (l) sheetTake.value = l.takeId;
  }, [status.value]);

  if (!id) return html`<${Chooser} />`;
  const st = status.value;
  if (st === 'error') {
    const e = openError.value;
    return html`<div class="screen montage"><div class="empty error"><b>No se pudo abrir el tema</b>
      <span class="muted">${e?.message} <code>(${e?.code})</code></span>
      <div><button class="btn secondary" onClick=${() => openMontage(id)}>Reintentar</button></div></div></div>`;
  }
  if (st !== 'ready' || !snap.value) return html`<div class="screen montage"><div class="backing-loading muted"><span class="spinner" aria-hidden="true"></span></div></div>`;
  return html`<${Body} />`;
}
