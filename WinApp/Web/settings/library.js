import { useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { Modal, AccentBar } from '../ui.js';
import { notify } from '../state.js';
import { CleanupDialog } from '../screens/library-dialogs.js';
import { Group, InfoRow, fmtBytes, fmtPercent, errText, fail } from './common.js';

/// Pestaña «Biblioteca» del Mac (LibrarySettings): Biblioteca, Modelos y Fuentes externas.
export function LibrarySettings() {
  return html`<div class="sstack"><${LibraryGroup} /><${ModelsGroup} /><${SourcesGroup} /></div>`;
}

// --- Biblioteca (settings.get, library.usage, host.pickProjectsFolder, library.cleanup) ---

function LibraryGroup() {
  const [folder, setFolder] = useState(undefined);   // undefined = cargando
  const [usage, setUsage] = useState(null);
  const [restart, setRestart] = useState(false);
  const [cleanup, setCleanup] = useState(null);      // { bytes } | null
  const load = () => {
    call('settings.get').then(r => { setFolder(r.projectsFolder ?? null); setRestart(r.projectsFolder != null && r.projectsFolder !== r.activeProjectsFolder); }).catch(() => setFolder(null));
    call('library.usage').then(setUsage).catch(() => setUsage(null));
  };
  useEffect(() => { load(); return on('library.changed', load); }, []);
  const pick = async () => {
    try {
      const r = await call('host.pickProjectsFolder');
      if (r.path) { setFolder(r.path); setRestart(r.restartRequired !== false); }
    } catch (e) { fail('No se pudo cambiar la carpeta', e); }
  };
  const askCleanup = async () => {
    try { const { bytes } = await call('library.cleanupInfo', {}); setCleanup({ bytes: fmtBytes(bytes) }); }
    catch (e) { fail('No se pudo calcular la limpieza', e); }
  };
  return html`<${Group} title="Biblioteca" note="Una carpeta por tema, con sus stems, tomas y vídeo.">
    <div class="sfield"><span class="sfield-label">Carpeta de proyectos</span><div class="pathbox" title=${folder ?? ''}>${folder ?? '—'}</div></div>
    <${InfoRow} label="Espacio usado"><b class="val">${usage ? fmtBytes(usage.totalBytes) : '—'}</b><//>
    ${restart ? html`<p class="snote" role="status">La carpeta nueva se usará al reiniciar ToneForge.</p>` : null}
    <div class="srow-btns">
      <button class="btn secondary" onClick=${pick}>Cambiar carpeta</button>
      <button class="btn secondary" onClick=${askCleanup}>Limpiar tomas descartadas y stems</button></div>
    ${cleanup ? html`<${CleanupDialog} id=${undefined} title="Limpiar toda la biblioteca" bytes=${cleanup.bytes} onClose=${() => { setCleanup(null); load(); }} />` : null}
  <//>`;
}

// --- Modelos (models.*) ---

function ModelsGroup() {
  const [models, setModels] = useState(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  useEffect(() => {
    call('models.list').then(r => setModels(r.models)).catch(() => setModels([]));
    const offProgress = on('models.progress', p => setModels(ms => ms?.map(m => m.id === p.id ? { ...m, state: 'downloading', fraction: p.fraction } : m)));
    const offChanged = on('models.changed', p => {
      setModels(p.models);
      if (p.error) notify('error', `No se pudo descargar el modelo: ${p.error.message}`);
    });
    return () => { offProgress(); offChanged(); };
  }, []);
  const m = models?.[0];
  const download = () => call('models.download', { id: m.id })
    .then(() => setModels(ms => ms.map(x => x.id === m.id ? { ...x, state: 'downloading', fraction: x.fraction ?? 0 } : x)))
    .catch(e => fail('No se pudo descargar el modelo', e));
  const del = async () => {
    setConfirmDelete(false);
    try { setModels((await call('models.delete', { id: m.id })).models); } catch (e) { fail('No se pudo borrar el modelo', e); }
  };
  return html`<${Group} title="Modelos" note="Se descargan la primera vez que se usan.">
    ${m ? html`<${InfoRow} label=${m.name}><${ModelStatus} m=${m} /><//>
      ${m.state === 'downloading' ? html`<${AccentBar} fraction=${m.fraction ?? 0} />` : null}
      <div class="srow-btns">
        ${m.state === 'installed' && m.source === 'store' ? html`<button class="btn secondary" onClick=${() => setConfirmDelete(true)}>Borrar</button>` : null}
        ${m.state === 'notInstalled' || m.state === 'failed' ? html`<button class="btn primary" onClick=${download}>Descargar</button>` : null}</div>` : null}
    ${confirmDelete ? html`<${Modal} title="Borrar el modelo" width=${460} onClose=${() => setConfirmDelete(false)} autofocus=".secondary">
      <p>Se volverá a descargar la próxima vez que separes un tema.</p>
      <div class="modal-actions"><button class="btn secondary sm" onClick=${() => setConfirmDelete(false)}>Cancelar</button>
        <button class="btn danger sm" onClick=${del}>Borrar</button></div><//>` : null}
  <//>`;
}

function ModelStatus({ m }) {
  switch (m.state) {
    case 'notInstalled': return html`<b class="val accent">Pendiente · ${fmtBytes(m.archiveBytes)}</b>`;
    case 'downloading': return html`<b class="val accent">Descargando ${fmtPercent(m.fraction ?? 0)}</b>`;
    case 'verifying': return html`<b class="val accent">Verificando…</b>`;
    case 'installing': return html`<b class="val accent">Instalando…</b>`;
    case 'installed': return html`<b class="val ok">${m.bytes != null ? `Descargado · ${fmtBytes(m.bytes)}` : 'Descargado'}</b>`;
    default: return html`<b class="val danger" title=${m.message ?? ''}>Error</b>`;
  }
}

// --- Fuentes externas (tools.*) ---

function SourcesGroup() {
  const [info, setInfo] = useState(null);
  const [status, setStatus] = useState({ kind: 'idle' });   // idle | updating | done | failed
  const load = () => call('tools.info').then(setInfo).catch(() => setInfo({}));
  useEffect(() => { load(); }, []);
  const updated = info?.ytDlpOrigin === 'updated';
  const updating = status.kind === 'updating';
  const update = async () => {
    if (updating) return;
    setStatus({ kind: 'updating' });
    try {
      const r = await call('tools.updateYtDlp', {}, { timeout: 200000 });
      const i = await call('tools.info'); setInfo(i);
      setStatus({ kind: 'done', text: i.ytDlpOrigin === 'updated' ? `yt-dlp actualizado a ${r.version}.` : `Ya tienes la última versión (${r.version}).` });
    } catch (e) { setStatus({ kind: 'failed', text: errText(e) }); }
  };
  const revert = async () => {
    try { await call('tools.revertYtDlp'); setStatus({ kind: 'idle' }); } catch (e) { fail('No se pudo volver a la embebida', e); }
    load();
  };
  const ver = v => info == null ? 'comprobando…' : (v ?? 'no disponible');
  return html`<${Group} title="Fuentes externas"
      note="Importar desde enlace usa yt-dlp, Deno y ffmpeg, que van dentro de la app. Si YouTube cambia y las descargas fallan, actualiza yt-dlp.">
    <${InfoRow} label="yt-dlp"><b class="val">${ver(info?.ytDlpVersion)}</b>
      ${info?.ytDlpOrigin ? html`<span class=${'chip ' + (updated ? 'ok' : 'neutral')}>${updated ? 'actualizada' : 'embebida'}</span>` : null}<//>
    <${InfoRow} label="Deno"><b class="val">${ver(info?.denoVersion)}</b><//>
    <${InfoRow} label="ffmpeg"><b class="val">${ver(info?.ffmpegVersion)}</b><//>
    ${updating ? html`<${AccentBar} fraction=${null} />` : null}
    ${status.kind === 'done' ? html`<p class="snote ok">${status.text}</p>` : null}
    ${status.kind === 'failed' ? html`<p class="snote danger">${status.text}</p>` : null}
    <div class="srow-btns">
      <button class="btn primary" onClick=${update} disabled=${updating}>Actualizar yt-dlp</button>
      <button class="btn secondary" onClick=${revert} disabled=${!updated || updating}>Volver a la embebida</button></div>
  <//>`;
}
