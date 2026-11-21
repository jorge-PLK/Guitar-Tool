import { signal, computed } from '@preact/signals';
import { useState, useEffect, useRef } from 'preact/hooks';
import { html } from '../html.js';
import { call } from '../bridge.js';
import { icon } from '../icons.js';
import {
  entries, skipped, listError, loaded, selectedId, detail, fold, mediaUrl, jobs, failures, notify,
  loadLibrary, openProject, closeProject, selectEntry, openBacking,
} from '../state.js';
import { PopupMenu, AccentBar } from '../ui.js';
import { RenameSheet, TrashDialog, FirstRunSheet, DuplicateDialog, CleanupDialog, DeleteTakeDialog, SongInfoFields, saveSongInfo } from './library-dialogs.js';
import { LinkSheet } from './link-sheet.js';
import { pickAndImport } from './import-files.js';

// Vista recordada entre arranques (Mac: @AppStorage "libraryGrouping"). El buscador y el artista abierto, no.
const store = (() => { try { return window.localStorage; } catch { return null; } })();
const grouping = signal(store?.getItem('libraryGrouping') === 'artists' ? 'artists' : 'songs');
const query = signal('');
const dialog = signal(null);       // { kind: 'rename'|'trash'|'link', ... }
const menu = signal(null);         // { x, y, items, align }
const openArtist = signal(null);   // clave plegada del artista abierto ('' = sin artista)

function setGrouping(g) {
  grouping.value = g;
  openArtist.value = null;
  try { store?.setItem('libraryGrouping', g); } catch { /* sin almacenamiento */ }
}

// Formatos (Fmt de Theme.swift; bytes como ByteCountFormatter .file: decimal, coma).
const fmtDuration = s => { const t = Math.round(s); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
const fmtRate = hz => hz === 44100 ? '44,1 kHz' : hz === 48000 ? '48 kHz' : `${Math.round(hz)} Hz`;
// ByteCountFormatter(.file) comprobado en el Mac: bytes enteros («1 byte»), KB sin decimales, MB con 1, GB con 2 hasta 10 y 1 después.
const fmtBytes = n => {
  if (n === 1) return '1 byte';
  if (n < 1000) return `${n} bytes`;
  const units = [['KB', 0], ['MB', 1], ['GB', 2], ['TB', 2]];
  let v = n / 1000, i = 0;
  const digits = k => (k === 2 && v >= 10 ? 1 : units[k][1]);
  while (i < units.length - 1 && Number(v.toFixed(digits(i))) >= 1000) { v /= 1000; i++; }
  return `${v.toLocaleString('es-ES', { maximumFractionDigits: digits(i) })} ${units[i][0]}`;
};
// Mac: `formatted(date: .abbreviated, time: .shortened)`.
const fmtDate = iso => new Date(iso).toLocaleString('es-ES', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' });

/// Etiquetas del Mac para `separationState` (contrato, library.list).
const STATES = {
  none: ['Importado', 'neutral'], queued: ['En cola', 'neutral'], running: ['Separando', 'working'],
  done: ['Separado', 'ok'], failed: ['Error', 'error'],
};
const Chip = ({ state }) => { const [t, k] = STATES[state] ?? STATES.none; return html`<span class=${'chip ' + k}>${t}</span>`; };

function Cover({ path, size, className = '' }) {
  const url = mediaUrl(path);
  const style = size ? `width:${size}px;height:${size}px` : undefined;
  return html`<div class=${'cover ' + className} style=${style}>
    ${url ? html`<img src=${url} alt="" loading="lazy" draggable="false" onError=${e => e.currentTarget.remove()} />` : null}
    <span class="cover-ph">${icon('music', size && size < 60 ? 18 : 32)}</span></div>`;
}

// LibraryFilter.swift del Mac: cada palabra de la consulta debe estar en el título o en el artista.
const collate = (a, b, sensitivity) => a.localeCompare(b, 'es', { sensitivity });
const matches = (e, q) => {
  const words = fold(q).split(/\s+/).filter(Boolean);
  if (!words.length) return true;
  const hay = fold(e.title) + '\u0001' + fold(e.artist);
  return words.every(w => hay.includes(w));
};
const byTitle = list => [...list].sort((a, b) => collate(a.title, b.title, 'accent'));
const filtered = computed(() => byTitle(entries.value.filter(e => matches(e, query.value))));

// LibraryGrouping.byArtist: orden alfabético local, «Sin artista» (clave vacía) al final, temas por título dentro del grupo.
const artistGroups = computed(() => {
  const map = new Map();
  for (const e of entries.value) {
    if (!matches(e, query.value)) continue;
    const raw = (e.artist ?? '').trim();
    const key = fold(raw);
    if (!map.has(key)) map.set(key, { id: key, name: raw, items: [] });
    map.get(key).items.push(e);
  }
  const groups = [...map.values()];
  return [...groups.filter(g => g.id).sort((a, b) => collate(a.name, b.name, 'base')), ...groups.filter(g => !g.id)]
    // Dentro del grupo el Mac ordena los títulos sin distinguir acentos (collator de LibraryGrouping), no como la lista plana.
    .map(g => ({ ...g, items: [...g.items].sort((a, b) => collate(a.title, b.title, 'base')) }));
});

function SearchField() {
  return html`<label class="search">${icon('search', 16)}
    <input type="search" placeholder="Buscar tema o artista" value=${query.value} aria-label="Buscar tema o artista"
      onInput=${e => { query.value = e.currentTarget.value; }} />
    ${query.value ? html`<button class="clear" aria-label="Borrar búsqueda" onClick=${() => { query.value = ''; }}>${icon('close', 14)}</button>` : null}
  </label>`;
}

function Segmented() {
  const opt = (v, label) => html`<button role="radio" aria-checked=${grouping.value === v}
    class=${grouping.value === v ? 'on' : ''} onClick=${() => setGrouping(v)}>${label}</button>`;
  return html`<div class="segmented" role="radiogroup" aria-label="Vista">${opt('songs', 'Temas')}${opt('artists', 'Artistas')}</div>`;
}

function Header() {
  return html`<div class="lib-header">
    <div><h1 class="page-title">Biblioteca</h1><p class="page-sub">Tus temas.</p></div>
    <div class="lib-tools">
      <${SearchField} /><${Segmented} />
      <button class="btn primary" onClick=${() => { dialog.value = { kind: 'link' }; }}>Importar tema</button>
    </div>
  </div>`;
}

function EmptyLibrary() {
  return html`<div class="empty"><b>Todavía no hay temas</b>
    <span class="muted">Importa un wav, flac o mp3, arrástralo a esta ventana o pega un enlace de YouTube o Spotify.</span></div>`;
}

function NoMatch() {
  return html`<div class="empty"><span class="muted">Ningún tema coincide con «${query.value.trim()}»</span></div>`;
}

const separating = e => e.separationState === 'queued' || e.separationState === 'running';

function reveal(id) { call('library.reveal', { id }).catch(err => notify('error', `No se pudo abrir la carpeta: ${err.message}`)); }

const isIntake = j => j.stage === 'import' || j.stage === 'download';
const isLive = j => j && !isIntake(j);
const cancellable = (e, j) => isLive(j) && j.stage === 'separation' && (e.separationState === 'queued' || e.separationState === 'running');

async function cancelJob(id) {
  try {
    const r = await call('jobs.cancel', { id });
    if (!r.cancelled) notify('info', 'Este trabajo ya no se puede cancelar (está en análisis).');
  } catch (e) { notify('error', `No se pudo cancelar: ${e.message}`); }
}

async function separateAgain(id) {
  try { await call('library.separate', { id }); } catch (e) { notify('error', `No se pudo separar: ${e.message}`); }
}

const importFromFile = pickAndImport;   // selección múltiple y aviso de repetido en import-files.js (L-F5)

const askRename = e => { dialog.value = { kind: 'rename', id: e.id, title: e.title, artist: e.artist ?? '' }; };
// AppModel.requestCleanup: primero se calcula lo que se libera y luego sale el diálogo.
async function askCleanup(e) {
  try {
    const { bytes } = await call('library.cleanupInfo', { id: e.id });
    dialog.value = { kind: 'cleanup', id: e.id, title: `Limpiar «${e.title}»`, bytes: fmtBytes(bytes) };
  } catch (err) { notify('error', `No se pudo limpiar: ${err.message}`); }
}
const askTrash = e => { dialog.value = { kind: 'trash', entry: e }; };

function rowMenu(ev, e) {
  ev.preventDefault();
  const j = jobs.value[e.id];
  menu.value = { x: ev.clientX, y: ev.clientY, items: [
    { label: 'Separar de nuevo', onSelect: () => separateAgain(e.id), disabled: separating(e) || isLive(j) },
    ...(cancellable(e, j) ? [{ label: 'Cancelar separación', onSelect: () => cancelJob(e.id) }] : []),
    { label: 'Limpiar…', onSelect: () => askCleanup(e), disabled: separating(e) },
    { label: 'Mostrar carpeta', onSelect: () => reveal(e.id) },
    { label: 'Corregir título y artista…', onSelect: () => askRename(e) },
    'sep',
    { label: 'Eliminar…', danger: true, onSelect: () => askTrash(e) },
  ] };
}

function StateCell({ e }) {
  const j = jobs.value[e.id];
  if (!isLive(j)) {
    const tip = e.separationState === 'failed' ? (failures.value[e.id] ?? e.separationError ?? 'Error desconocido') : undefined;
    return html`<span title=${tip}><${Chip} state=${e.separationState} /></span>`;
  }
  const kind = j.state === 'queued' ? 'neutral' : 'working';
  return html`<span class=${'chip ' + kind}>${j.text || (j.state === 'queued' ? 'En cola' : 'Trabajando…')}</span>`;
}

function ImportRows() {
  const list = Object.values(jobs.value).filter(isIntake);
  return list.map(j => html`<tr class="row import-row" key=${j.id}><td colSpan="5"><div class="import-line">
    <span class="t">${j.title}</span><span class="grow"></span>
    ${j.state === 'queued' ? null : html`<div class="import-bar"><${AccentBar} fraction=${j.fraction} /></div>`}
    <span class=${'chip ' + (j.state === 'queued' ? 'neutral' : 'working')}>${j.text || 'Importando…'}</span>
    ${j.id.startsWith('link-') && j.stage === 'download' ? html`<button class="btn secondary sm icon" aria-label="Cancelar descarga" title="Cancelar descarga"
      onClick=${() => call('link.cancel', { jobId: j.id }).catch(err => notify('error', `No se pudo cancelar: ${err.message}`))}>${icon('close', 15)}</button>` : null}
    </div></td></tr>`);
}

function Row({ e }) {
  const sel = selectedId.value === e.id;
  // Como el Mac: un clic selecciona (fija el tema de trabajo); sin doble clic ni «Abrir». La página del tema, desde la barra lateral.
  return html`<tr class=${'row' + (sel ? ' selected' : '')} tabindex="0" aria-selected=${sel}
    onClick=${() => selectEntry(e.id)} onContextMenu=${ev => rowMenu(ev, e)}
    onKeyDown=${ev => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); selectEntry(e.id); } }}>
    <td class="c-title"><div class="title-cell"><${Cover} path=${e.cover} size=${44} />
      <div class="tt"><div class="t">${e.title}</div>${e.artist && grouping.value === 'songs' ? html`<div class="a">${e.artist}</div>` : null}</div></div></td>
    <td class="c-num">${e.takeCount ? e.takeCount : '—'}</td>
    <td class="c-state"><${StateCell} e=${e} /></td>
    <td class="c-actions"><div class="actions">
      <button class="btn secondary sm icon" onClick=${ev => { ev.stopPropagation(); reveal(e.id); }} aria-label="Mostrar carpeta" title="Mostrar carpeta">${icon('folder', 15)}</button>
      <button class="btn secondary sm icon" onClick=${ev => { ev.stopPropagation(); askRename(e); }} aria-label="Editar título y artista" title="Editar título y artista">${icon('pencil', 15)}</button>
      <button class="btn secondary sm icon hover-danger" onClick=${ev => { ev.stopPropagation(); askTrash(e); }} aria-label="Eliminar" title="Eliminar…">${icon('trash', 15)}</button>
    </div></td>
  </tr>`;
}

function Table({ list }) {
  return html`<div class="card table-card"><table class="lib-table">
    <thead><tr><th>Tema / Artista</th><th class="c-num">Tomas</th><th>Estado</th>
      <th class="c-actions"><span class="sr-only">Acciones</span></th></tr></thead>
    <tbody><${ImportRows} />${list.map(e => html`<${Row} key=${e.id} e=${e} />`)}</tbody></table>
    ${entries.value.length === 0 && !Object.values(jobs.value).some(isIntake) ? html`<${EmptyLibrary} />` : list.length === 0 ? html`<${NoMatch} />` : null}
  </div>`;
}

/// Iniciales (hasta dos palabras) y color estable por FNV-1a del nombre plegado, como `ArtistTile` del Mac (HSB 0,45/0,5 -> HSL).
const initials = name => name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => [...w][0]).join('').toUpperCase() || '?';
function artistColor(name) {
  let h = 0xcbf29ce484222325n;
  for (const b of new TextEncoder().encode(fold(name))) h = ((h ^ BigInt(b)) * 0x100000001b3n) & 0xffffffffffffffffn;
  return `hsl(${Number(h % 360n)} 29% 38.75%)`;
}

function ArtistGrid() {
  const groups = artistGroups.value;
  if (!groups.length) return html`${entries.value.length ? html`<${NoMatch} />` : html`<div class="card"><${EmptyLibrary} /></div>`}`;
  return html`<div class="tiles">${groups.map(g => html`<button key=${g.id} class="tile" onClick=${() => { openArtist.value = g.id; }}
      aria-label=${`${g.name || 'Sin artista'}, ${g.items.length} temas`}>
      <div class="tile-cover" style=${g.name ? `background:${artistColor(g.name)}` : undefined}>
        ${g.name ? html`<span class="tile-initials">${initials(g.name)}</span>` : html`<span class="tile-person">${icon('person', 40)}</span>`}</div>
      <div class="tile-name">${g.name || 'Sin artista'}</div>
      <div class="tile-count muted">${g.items.length === 1 ? '1 tema' : `${g.items.length} temas`}</div></button>`)}</div>`;
}

function ArtistBar({ name }) {
  return html`<div class="artist-bar"><button class="link-back" onClick=${() => { openArtist.value = null; }}>
    ${icon('chevronLeft', 16)}<span>Artistas</span></button><h2>${name || 'Sin artista'}</h2></div>`;
}

function ListError() {
  const err = listError.value;
  if (err.code === 'no-projects-folder') {
    return html`<div class="card"><div class="empty"><b>Falta la carpeta de proyectos</b>
      <span class="muted">Elige dónde se guardan los temas (cada uno vive en su propia carpeta, con sus stems, tomas y vídeo).
      Se podrá hacer desde Ajustes o con <code>--projects-folder</code>.</span>
      <div><button class="btn secondary" style="margin-top:12px" onClick=${loadLibrary}>Reintentar</button></div></div></div>`;
  }
  return html`<div class="card"><div class="empty error"><b>No se pudo leer la biblioteca</b>
    <span class="muted">${err.message} <code>(${err.code})</code></span>
    <div><button class="btn secondary" style="margin-top:12px" onClick=${loadLibrary}>Reintentar</button></div></div></div>`;
}

function Skipped() {
  const n = skipped.value.length;
  if (!n) return null;
  const detailText = skipped.value.map(s => `${s.folderName}: ${s.reason}`).join('\n');
  return html`<p class="skipped muted" title=${detailText}>${n === 1 ? '1 carpeta omitida' : `${n} carpetas omitidas`} (no son proyectos válidos).</p>`;
}

function ListView() {
  let body;
  if (listError.value) body = html`<${ListError} />`;
  else if (!loaded.value) body = null;
  else if (grouping.value === 'artists' && openArtist.value == null) body = html`<${ArtistGrid} />`;
  else {
    const open = grouping.value === 'artists' ? artistGroups.value.find(g => g.id === openArtist.value) : null;
    const list = grouping.value === 'artists' ? (open?.items ?? []) : filtered.value;
    const name = open?.name ?? entries.value.find(e => fold(e.artist) === openArtist.value)?.artist?.trim();
    body = html`${grouping.value === 'artists' ? html`<${ArtistBar} name=${name} />` : null}<${Table} list=${list} />`;
  }
  return html`<div class="screen"><${Header} /><div class="scroll">${body}<${Skipped} /></div></div>`;
}

// Detalle (library.project)

const infoRow = (k, v) => html`<div class="info-row"><span class="muted">${k}</span><span class="v">${v}</span></div>`;

// ProjectRecordingsView del Mac: m:ss truncado (Fmt.clock) y «–» si no se lee el audio.
const fmtTakeClock = d => d == null ? '–' : `${Math.floor(Math.max(d, 0) / 60)}:${String(Math.floor(Math.max(d, 0)) % 60).padStart(2, '0')}`;

function Takes({ data }) {
  const parts = (data.parts ?? []).filter(p => p.takes?.length);
  const ask = (part, t) => { dialog.value = { kind: 'deleteTake', id: data.id, takeId: t.id, label: `Toma ${t.number} · ${part.name}` }; };
  if (!parts.length) return html`<p class="muted small-text">Este tema aún no tiene tomas grabadas.</p>`;
  return html`${parts.map(p => html`<div class="part" key=${p.id}>
    <div class="part-name">${p.name}</div>
    ${p.takes.map((t, i) => html`<div class="take" key=${t.id}>
      <span class=${'take-n' + (t.isBest ? ' best' : '')}>Toma ${t.number}</span>
      ${t.isBest ? html`<span class="best" aria-label="Mejor toma">★</span>` : null}
      <span class="muted small-text">${fmtDate(t.createdAt)}</span>
      <span class="muted small-text take-dur">${fmtTakeClock(t.duration)}</span>
      <span class="muted small-text">${t.hasVideo ? 'Con vídeo' : 'Sin vídeo'}</span>
      ${t.punchCount > 0 ? html`<span class="muted small-text">${t.punchCount === 1 ? '1 punch' : `${t.punchCount} punches`}</span>` : null}
      <span class="grow"></span>
      <button class="btn secondary sm" onClick=${() => ask(p, t)}>Eliminar</button></div>`)}</div>`)}`;
}

/// Título y artista de la página del tema; el lápiz los edita en el sitio (Guardar / Cancelar, Esc cancela), como el Mac.
function TitleBlock({ data }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState('');
  const [artist, setArtist] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const box = useRef(null);
  useEffect(() => { if (editing) box.current?.querySelector('input')?.focus(); }, [editing]);
  const start = () => { setTitle(data.title); setArtist(data.artist ?? ''); setError(null); setEditing(true); };
  const canSave = title.trim() !== '' && !busy;
  const save = async () => {
    if (!canSave) return;
    setBusy(true);
    const err = await saveSongInfo(data.id, title, artist);
    setBusy(false);
    if (err) setError(err); else setEditing(false);
  };
  if (!editing) {
    return html`<div><h1 class="page-title title-edit">${data.title}<button class="pencil" aria-label="Editar título y artista" title="Editar título y artista"
      onClick=${start}>${icon('pencil', 18)}</button></h1>${data.artist ? html`<p class="page-sub" style="margin-top:6px">${data.artist}</p>` : null}</div>`;
  }
  return html`<div class="title-form" ref=${box} onKeyDown=${e => { if (e.key === 'Escape') { e.stopPropagation(); setEditing(false); } }}>
    <${SongInfoFields} title=${title} artist=${artist} setTitle=${setTitle} setArtist=${setArtist} onSubmit=${save} />
    ${error ? html`<div class="modal-error" role="alert">${error}</div>` : null}
    <div class="title-form-actions"><button class="btn primary" onClick=${save} disabled=${!canSave}>Guardar</button>
      <button class="btn secondary sm" onClick=${() => setEditing(false)}>Cancelar</button></div></div>`;
}

function Detail() {
  const d = detail.value;
  const data = d.data;
  const back = html`<button class="link-back" onClick=${closeProject}>${icon('chevronLeft', 16)}<span>Biblioteca</span></button>`;
  if (d.loading) return html`<div class="screen screen-scroll">${back}<p class="muted">Cargando…</p></div>`;
  if (d.error) {
    return html`<div class="screen screen-scroll">${back}<div class="card"><div class="empty error">
      <b>${d.error.code === 'not-found' ? 'El tema ya no está en la biblioteca' : 'No se pudo abrir el tema'}</b>
      <span class="muted">${d.error.message} <code>(${d.error.code})</code></span></div></div></div>`;
  }
  const state = data.separationState === 'failed'
    ? `Error: ${data.separationError ?? 'desconocido'}` : (STATES[data.separationState] ?? STATES.none)[0];
  return html`<div class="screen screen-scroll">${back}
    <div class="detail-head"><${Cover} path=${data.cover} size=${96} className="detail-cover" />
      <${TitleBlock} key=${data.id} data=${data} /></div>
    <div class="card info-card">${infoRow('Frecuencia', fmtRate(data.sampleRate))}${infoRow('Duración', fmtDuration(data.duration))}${infoRow('Estado', state)}</div>
    <div class="card block"><h3 class="block-title">Stems</h3>
      ${data.stems.length === 0 ? html`<p class="muted">Sin stems todavía.</p>` : null}
      ${data.stems.map(s => html`<div class="stem" key=${s.kind}><span>${s.kind}</span>
        <span class="muted">${s.isEmpty ? 'vacío' : fmtBytes(s.bytes)}</span></div>`)}</div>
    <div class="card block"><h3 class="block-title">Grabaciones</h3><${Takes} data=${data} /></div>
    <div class="detail-actions">
      ${data.separationState === 'done' ? html`<button class="btn primary" onClick=${() => openBacking(data.id)}>Abrir en Backing track</button>` : null}
      <button class="btn secondary" onClick=${() => reveal(data.id)}>Mostrar carpeta</button>
      <span class="grow"></span>
      <button class="link-muted" onClick=${() => askTrash(data)}>Eliminar…</button></div>
  </div>`;
}

function Dialogs() {
  const d = dialog.value;
  const close = () => { dialog.value = null; };
  const firstRun = listError.value?.code === 'no-projects-folder';
  if (d?.kind === 'rename') return html`<${RenameSheet} id=${d.id} title=${d.title} artist=${d.artist} onClose=${close} />`;
  if (d?.kind === 'duplicate') return html`<${DuplicateDialog} id=${d.id} onOpen=${openProject} onClose=${close} />`;
  if (d?.kind === 'cleanup') return html`<${CleanupDialog} id=${d.id} title=${d.title} bytes=${d.bytes} onClose=${close} />`;
  if (d?.kind === 'deleteTake') return html`<${DeleteTakeDialog} id=${d.id} takeId=${d.takeId} label=${d.label} onClose=${close} />`;
  if (d?.kind === 'trash') return html`<${TrashDialog} entry=${d.entry} onClose=${close} />`;
  if (d?.kind === 'link') return html`<${LinkSheet} onClose=${close} onPickFile=${importFromFile} />`;
  return firstRun ? html`<${FirstRunSheet} />` : null;
}

export function Library() {
  const m = menu.value;
  return html`${detail.value ? html`<${Detail} />` : html`<${ListView} />`}<${Dialogs} />
    ${m ? html`<${PopupMenu} x=${m.x} y=${m.y} items=${m.items} align=${m.align} onClose=${() => { menu.value = null; }} />` : null}`;
}
