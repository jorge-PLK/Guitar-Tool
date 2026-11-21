import { signal, computed } from '@preact/signals';
import { call, on } from './bridge.js';
import { target as backingTarget } from './backing/store.js';

/// Pantallas de la barra lateral (orden y nombres de App/Sources/RootView.swift).
export const SCREENS = [
  { id: 'library', label: 'Biblioteca', icon: 'library' },
  { id: 'backing', label: 'Backing track', icon: 'backing' },
  { id: 'tab', label: 'Tablatura', icon: 'tab' },
  { id: 'record', label: 'Grabar', icon: 'record' },
  { id: 'montage', label: 'Montaje', icon: 'montage' },
];
export const SETTINGS = { id: 'settings', label: 'Ajustes', icon: 'settings' };
export const screenById = id => [...SCREENS, SETTINGS].find(s => s.id === id);

export const info = signal(null);          // resultado de app.info
export const bootError = signal(null);     // { code, message } si app.info falla
export const screen = signal('library');   // navegación por estado

// Biblioteca
export const entries = signal([]);         // [Summary] de library.list
export const skipped = signal([]);
export const listError = signal(null);     // { code, message }
export const loaded = signal(false);
export const selectedId = signal(null);    // tema seleccionado (tarjeta de la barra lateral)
export const detail = signal(null);        // { id, data?, error?, loading }

export const failures = signal({});     // motivo del último fallo de separación por id (tooltip del chip «Error»)
export const jobs = signal({});         // trabajos vivos por id (jobs.list / jobs.progress)
export const notices = signal([]);      // avisos suaves: { id, kind: 'info'|'error', text, action? }

let noticeSeq = 0;
export function notify(kind, text, action = null) {
  const id = ++noticeSeq;
  notices.value = [...notices.value, { id, kind, text, action }];
  if (kind !== 'error') setTimeout(() => dismissNotice(id), 9000);
  return id;
}
export const dismissNotice = id => { notices.value = notices.value.filter(n => n.id !== id); };

const FINAL = new Set(['done', 'failed', 'cancelled']);
export async function loadJobs() {
  try {
    const r = await call('jobs.list');
    jobs.value = Object.fromEntries((r.jobs ?? []).map(j => [j.id, j]));
  } catch { /* sin cola (host sin trabajos): la biblioteca sigue valiendo */ }
}
on('jobs.progress', j => {
  const next = { ...jobs.value };
  if (FINAL.has(j.state)) {
    delete next[j.id];
    if (j.state === 'failed') failures.value = { ...failures.value, [j.id]: j.error ?? 'Error desconocido' };
    if (j.state === 'failed' && j.stage !== 'import' && j.stage !== 'download' && !j.id.startsWith('link-')) notify('error', `${j.title}: ${j.error ?? 'error desconocido'}`);
  } else next[j.id] = j;
  jobs.value = next;
});

/// Fin de una importación por enlace: error (título + detalle), duplicado o avisos de la descarga.
on('link.finished', e => {
  if (e.error) {
    if (e.error.code === 'cancelled') return;
    const i = (e.error.message ?? '').indexOf('\n');
    const title = i < 0 ? e.error.message : e.error.message.slice(0, i);
    const detail = i < 0 ? '' : e.error.message.slice(i + 1);
    notify('error', detail ? `${title}\n${detail}` : title);
    return;
  }
  for (const n of e.notices ?? []) notify('info', n);
  if (e.duplicate && e.id) notify('info', 'Este tema ya está en la biblioteca.', { label: 'Abrir el existente', run: () => openProject(e.id) });
  else if (e.id) notify('info', 'Tema importado.', { label: 'Abrir', run: () => openProject(e.id) });
});

export const selectedEntry = computed(() => entries.value.find(e => e.id === selectedId.value) ?? null);

export function go(id) {
  screen.value = id;
  if (id === 'library') detail.value = null;
}

/// «Seleccionar» (AppModel.select del Mac): fija el tema de trabajo de Backing y Tablatura sin ir a su página.
export function selectEntry(id) {
  if (!entries.value.some(e => e.id === id)) return;
  backingTarget.value = id;
  selectedId.value = id;
}

/// Abre el tema en la pantalla Backing (la Biblioteca lo usa en «Abrir en Backing track»); la barra lateral recuerda el último.
export function openBacking(id) {
  backingTarget.value = id;
  selectedId.value = id;
  screen.value = 'backing';
}

/// Minúsculas y sin acentos, para buscar y comparar títulos (LibraryFilter.fold del Mac).
export const fold = s => (s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/// URL de un fichero del proyecto: `mediaBase` + ruta relativa con cada segmento codificado.
export function mediaUrl(path) {
  if (!path || !info.value) return null;
  const base = info.value.mediaBase.endsWith('/') ? info.value.mediaBase : info.value.mediaBase + '/';
  return base + path.split('/').map(encodeURIComponent).join('/');
}

export async function loadLibrary() {
  try {
    const r = await call('library.list');
    entries.value = r.projects ?? [];
    skipped.value = r.skipped ?? [];
    listError.value = null;
    if (selectedId.value && !entries.value.some(e => e.id === selectedId.value)) selectedId.value = null;
  } catch (e) {
    entries.value = [];
    skipped.value = [];
    listError.value = { code: e.code ?? 'internal', message: e.message };
  } finally {
    loaded.value = true;
  }
}

let detailToken = 0;
export async function openProject(id) {
  const token = ++detailToken;
  selectedId.value = id;
  backingTarget.value = id;     // abrir su página también fija el tema de trabajo (AppModel.open del Mac)
  screen.value = 'library';
  detail.value = { id, loading: true };
  try {
    const data = await call('library.project', { id });
    if (token === detailToken) detail.value = { id, data };
  } catch (e) {
    if (token === detailToken) detail.value = { id, error: { code: e.code ?? 'internal', message: e.message } };
  }
}

/// Repite `library.project` del tema abierto sin parpadeo (tras `library.changed`).
export async function refreshDetail() {
  const d = detail.value;
  if (!d?.data) return;
  try {
    const data = await call('library.project', { id: d.id });
    if (detail.value?.id === d.id) detail.value = { id: d.id, data };
  } catch (e) {
    if (detail.value?.id === d.id) detail.value = { id: d.id, error: { code: e.code ?? 'internal', message: e.message } };
  }
}

/// Un tema ha desaparecido (papelera o borrado): cierra su detalle y su selección.
export function forgetProject(id) {
  if (detail.value?.id === id) closeProject();
  if (selectedId.value === id) selectedId.value = null;
  if (id in failures.value) { const { [id]: _gone, ...rest } = failures.value; failures.value = rest; }
}

export function closeProject() {
  detailToken++;
  detail.value = null;
}

/// Arranque: app.info, carga de la biblioteca y `launch.screen` / `launch.project`.
export async function boot() {
  bootError.value = null;
  try {
    info.value = await call('app.info');
  } catch (e) {
    bootError.value = { code: e.code ?? 'internal', message: e.message };
    return;
  }
  const launch = info.value.launch ?? {};
  if (launch.screen && screenById(launch.screen)) screen.value = launch.screen;
  await Promise.all([loadLibrary(), loadJobs()]);
  if (launch.project) {
    const key = fold(launch.project);
    const hit = entries.value.find(e => e.id.toLowerCase() === launch.project.toLowerCase())
      ?? entries.value.find(e => fold(e.title) === key);
    if (hit) {
      if (launch.screen && launch.screen !== 'library') selectedId.value = hit.id;
      else await openProject(hit.id);
    }
  }
}
