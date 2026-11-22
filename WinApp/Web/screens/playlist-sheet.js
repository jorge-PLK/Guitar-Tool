import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { call, on } from '../bridge.js';
import { AccentBar, PopupMenu } from '../ui.js';
import { openProject, notify } from '../state.js';
import { applySnapshot, clearPlaylist } from '../playlist/store.js';

// Pasos de la importación de listas y álbumes (PlaylistImportView del Mac) sobre `playlist.*` y `playlist.changed`
// (contrato W2-J). Se pinta con la instantánea del núcleo: temas -> (búsqueda -> revisión) -> cola -> resumen.
// La hoja la monta `LinkSheet` (screens/link-sheet.js), que ensancha la hoja a 880 pt como `LinkImportSheet.playlistSize` del Mac.

const fmtDur = s => { const t = Math.round(s); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
const percent = f => `${Math.round(f * 100)} %`;
const signed = s => `${s >= 0 ? '+' : '−'}${Math.abs(s).toFixed(1).replace('.', ',')} s`;
const duration = s => (s == null ? '—' : fmtDur(s));

const Chip = ({ text, kind, title }) => html`<span class=${'chip ' + kind} title=${title}>${text}</span>`;
const Banner = ({ error, children }) => html`<div class=${'banner ' + (error ? 'error' : 'info')}>${children}</div>`;
const Actions = ({ children }) => html`<div class="pl-actions">${children}</div>`;
const Spacer = () => html`<div class="pl-spacer"></div>`;

function ListHeader({ name, subtitle }) {
  return html`<div class="pl-head"><div class="pl-name">${name || 'Lista'}</div><div class="pl-sub">${subtitle}</div></div>`;
}

function TitleBlock({ item, dim }) {
  return html`<div class="pl-title" style=${dim ? 'opacity:.55' : undefined}>
    <div class="t" title=${item.title}>${item.title}</div><div class="a" title=${item.artist}>${item.artist}</div></div>`;
}

const Table = ({ children }) => html`<div class="pl-table">${children}</div>`;
const Row = ({ children, cls = '' }) => html`<div class=${'pl-row ' + cls}>${children}</div>`;

const CheckBox = ({ on }) => html`<span class=${'pl-check' + (on ? ' on' : '')} aria-hidden="true">${on
  ? html`<svg width="18" height="18" viewBox="0 0 18 18"><rect width="18" height="18" rx="4" fill="currentColor"/><path d="M4.5 9.3l3 3 6-6.6" fill="none" stroke="var(--accent-ink)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`
  : html`<svg width="18" height="18" viewBox="0 0 18 18"><rect x="1" y="1" width="16" height="16" rx="4" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>`}</span>`;

const Chevrons = () => html`<svg class="pl-chev" width="10" height="12" viewBox="0 0 10 12" aria-hidden="true"><path d="M2 4.5L5 1.5l3 3M2 7.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

/// Candidato en el menú (menuLabel del Mac): título · canal · duración · diferencia · cercano · directo.
function menuLabel(c) {
  const parts = [c.title];
  if (c.artist) parts.push(c.artist);
  if (c.duration != null) parts.push(fmtDur(c.duration));
  if (c.difference != null) parts.push(signed(c.difference));
  if (c.isClose) parts.push('cercano');
  if (c.isLive) parts.push('directo');
  return parts.join(' · ');
}

function placeholder(item) {
  switch (item.status) {
    case 'skipped': return 'Omitido';
    case 'failed': return 'Falló la búsqueda: ' + (item.error?.title ?? '');
    case 'pending': return 'Sin buscar';
    default: return item.candidates.length === 0 ? 'Sin resultados: omitir' : 'Elige un candidato…';
  }
}

/// `playlist.close {}`: la lista con trabajo vivo sigue en segundo plano; si no, se descarta (y la cápsula desaparece).
export async function closePlaylist() {
  try {
    const r = await call('playlist.close', {});
    if (r.closed) clearPlaylist();
  } catch { /* se cierra igual */ }
}

/// Pasos de la lista. `initial`: instantánea ya conocida (la de `link.resolve`) o null (se pide con `playlist.state`).
/// `onClose`: cierra la hoja; `onDiscard`: vuelve al campo vacío; `onGone`: el núcleo ya no tiene la lista.
export function PlaylistView({ initial, onClose, onDiscard, onGone }) {
  const [snap, setSnap] = useState(initial ?? null);
  const [menu, setMenu] = useState(null);
  const alive = useRef(true);
  const put = s => { if (alive.current) { setSnap(s); applySnapshot(s); } };

  useEffect(() => {
    alive.current = true;
    const off = on('playlist.changed', s => { if (alive.current) setSnap(s); });
    if (!initial) call('playlist.state').then(put).catch(() => onGone?.());
    return () => { alive.current = false; off(); };
  }, []);

  /// Acción del núcleo: la respuesta es la instantánea nueva.
  const act = async (method, params = {}) => {
    try { put(await call(method, params, { timeout: 30000 })); }
    catch (e) {
      if (e.code === 'no-playlist') { clearPlaylist(); onGone?.(); return; }
      notify('error', (e.message ?? '').split('\n')[0] || 'No se pudo completar la acción');
    }
  };

  /// «Cerrar»: la lista con trabajo en marcha se conserva en segundo plano (la cápsula de la Biblioteca la reabre).
  const close = async () => { await closePlaylist(); onClose(); };
  const discard = async () => {
    try { await call('playlist.close', { force: true }); } catch { /* sin lista */ }
    clearPlaylist();
    onDiscard();
  };
  const openInLibrary = async id => { await close(); openProject(id); };

  if (!snap) return html`<div class="pl-root"></div>`;
  const t = snap.totals ?? {};
  const isYouTube = snap.source === 'youtube';
  const items = snap.items ?? [];

  // --- Cargando
  const loading = () => html`<div class="spin-line"><span class="spinner" aria-hidden="true"></span><span>Leyendo la lista…</span></div>
    <${Spacer} /><${Actions}><button class="btn secondary" onClick=${() => { call('link.cancel').catch(() => {}); discard(); }}>Cancelar</button></${Actions}>`;

  // --- Paso 1: temas
  const tracks = () => html`<div class="pl-head-row">
      <${ListHeader} name=${snap.name} subtitle=${`${t.total} temas · ${t.selected} marcados` + (t.inLibrary > 0 ? ` · ${t.inLibrary} ya en la biblioteca` : '')} />
      <button class="btn secondary pl-small" onClick=${() => act('playlist.selectAll')}>Marcar todos</button>
      <button class="btn secondary pl-small" onClick=${() => act('playlist.selectNone')}>Ninguno</button></div>
    ${snap.mayBeTruncated ? html`<${Banner}>Spotify devuelve como máximo 100 temas por lista: puede haber cortado esta. Si faltan temas, impórtalos desde su enlace.</${Banner}>` : null}
    <${Table}>${items.map(i => TrackRow(i))}</${Table}>
    <${Actions}><button class="btn secondary" onClick=${close}>Cerrar</button>
      <button class="btn primary" disabled=${t.selected === 0} onClick=${() => act('playlist.continue')}>${isYouTube
        ? `Descargar y procesar (${t.selected})` : `Buscar en YouTube (${t.selected})`}</button></${Actions}>`;

  const TrackRow = i => {
    const inLib = i.status === 'inLibrary';
    const toggle = () => { if (!inLib) act('playlist.select', { id: i.id, selected: !i.selected }); };
    return html`<${Row} key=${i.id}><div class=${'pl-line' + (inLib ? '' : ' tap')} onClick=${toggle}>
      ${inLib ? html`<span class="pl-check-ph"></span>`
        : html`<button type="button" class=${'pl-check-btn' + (i.selected ? ' on' : '')} role="checkbox" aria-checked=${!!i.selected}
            aria-label=${`Marcar ${i.title}`} onClick=${e => { e.stopPropagation(); toggle(); }}><${CheckBox} on=${i.selected} /></button>`}
      <${TitleBlock} item=${i} dim=${inLib} />
      <span class="grow"></span>
      ${inLib ? html`<${Chip} text="En la biblioteca" kind="neutral" />` : null}
      ${i.possible ? html`<${Chip} text="Puede que ya lo tengas" kind="working" title=${`Parecido a: ${i.possible.title}`} />` : null}
      <span class="pl-dur">${duration(i.duration)}</span></div></${Row}>`;
  };

  // --- Paso 2: búsqueda
  const searching = () => {
    const done = snap.searchDone ?? 0, total = snap.searchTotal ?? 0;
    const frac = total === 0 ? 0 : done / total;
    const current = items.find(i => i.status === 'searching');
    return html`<${ListHeader} name=${snap.name} subtitle="Buscando cada tema en YouTube" />
      <div class="pl-line-between"><span>Buscando ${Math.min(done + 1, Math.max(total, 1))} de ${total}</span><span class="muted">${percent(frac)}</span></div>
      <${AccentBar} fraction=${frac} />
      ${current ? html`<${TitleBlock} item=${current} />` : null}
      <p class="pl-note">Nada se descarga todavía: después podrás revisar los candidatos.</p>
      <${Spacer} /><${Actions}><button class="btn secondary" onClick=${() => act('playlist.cancel')}>Cancelar</button></${Actions}>`;
  };

  // --- Paso 2: revisión
  const review = () => {
    const rows = items.filter(i => i.selected && i.status !== 'imported' && i.status !== 'inLibrary');
    const n = s => rows.filter(i => i.status === s).length;
    const unsearched = rows.some(i => i.status === 'pending' && !i.chosen && i.kind === 'spotify');
    return html`<${ListHeader} name=${snap.name} subtitle=${`${n('proposed')} con candidato · ${n('doubtful')} dudosos · ${n('skipped')} omitidos`} />
      <${Banner}>Revisa lo propuesto: nada se descarga hasta que pulses «Descargar y procesar». Los «dudosos» no tienen propuesta: elige uno o se omiten.</${Banner}>
      <${Table}>${rows.map(i => ReviewRow(i))}</${Table}>
      <${Actions}><button class="btn secondary" onClick=${close}>Cerrar</button>
        ${unsearched ? html`<button class="btn secondary" onClick=${() => act('playlist.search')}>Seguir buscando</button>` : null}
        <button class="btn primary" disabled=${t.queued === 0} onClick=${() => act('playlist.start')}>Descargar y procesar (${t.queued})</button></${Actions}>`;
  };

  const openMenu = (ev, i) => {
    const r = ev.currentTarget.getBoundingClientRect();
    const entries = [];
    for (const c of i.candidates) {
      if (c.inLibrary) {
        entries.push({ label: `${menuLabel(c)} · En la biblioteca`, disabled: true });
        entries.push({ label: `Abrir «${c.inLibrary.title}» en la biblioteca`, onSelect: () => openInLibrary(c.inLibrary.id) });
      } else entries.push({ label: menuLabel(c), onSelect: () => act('playlist.choose', { id: i.id, candidateId: c.id }) });
    }
    if (i.candidates.length) entries.push('sep');
    entries.push({ label: 'Omitir este tema', onSelect: () => act('playlist.skip', { id: i.id }) });
    setMenu({ x: r.left, y: r.bottom + 4, items: entries });
  };

  const ReviewRow = i => {
    const doubtful = i.status === 'doubtful';
    const c = i.chosen ? (i.candidates.find(x => x.id === i.chosen.id) ?? i.chosen) : null;
    return html`<${Row} key=${i.id} cls=${doubtful ? 'doubtful' : ''}><div class="pl-line review">
      <div class="pl-rtitle"><${TitleBlock} item=${i} /></div>
      <span class="pl-rdur">${duration(i.duration)}</span>
      <button type="button" class="pl-cand" aria-haspopup="menu" onClick=${ev => openMenu(ev, i)}>
        ${c ? html`<div class="pl-cand-text"><div class="n" title=${c.title}>${c.title}</div>
            <div class="m">${[c.artist, c.duration != null ? fmtDur(c.duration) : null].filter(Boolean).join(' · ')}</div></div>
          <span class="grow"></span>
          ${c.difference != null ? html`<span class="pl-diff">${signed(c.difference)}</span>` : null}
          ${c.isClose ? html`<${Chip} text="cercano" kind="ok" />` : null}
          ${c.isLive ? html`<${Chip} text="directo" kind="neutral" />` : null}
          ${c.inLibrary ? html`<${Chip} text="En la biblioteca" kind="neutral" />` : null}`
        : html`<span class=${'pl-ph' + (i.status === 'skipped' ? ' muted' : '')}>${placeholder(i)}</span><span class="grow"></span>`}
        <${Chevrons} /></button>
      ${doubtful ? html`<${Chip} text="dudoso" kind="error" />` : null}</div></${Row}>`;
  };

  // --- Paso 3: cola
  const queue = stopped => {
    const done = t.selected - t.remaining;
    const rows = items.filter(i => i.selected);
    const u = snap.update ?? {};
    const e = stopped ? snap.error : null;
    return html`<${ListHeader} name=${snap.name} subtitle=${e ? 'Cola detenida' : 'Descargando, importando y separando'} />
      <div class="pl-line-between"><span>${done} de ${t.selected} temas</span><span class="muted">${percent(snap.progress ?? 0)}</span></div>
      <${AccentBar} fraction=${snap.progress ?? 0} />
      ${e ? html`<${Banner} error=${true}>${e.title}. ${e.code === 'rate-limited' ? 'No se reintenta sola: reanuda cuando quieras.' : e.detail}</${Banner}>
        ${u.alreadyLatest ? html`<${Banner}>yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Lo ya importado se conserva.</${Banner}>` : null}
        ${u.error ? html`<${Banner} error=${true}>${u.error}</${Banner}>` : null}` : null}
      <${Table}>${rows.map(i => QueueRow(i))}</${Table}>
      <${Actions}><button class="btn secondary" title="La cola sigue en segundo plano" onClick=${close}>Cerrar</button>
        ${e ? (e.suggestsUpdate ? (u.alreadyLatest ? null
              : html`<button class="btn primary" disabled=${u.updating} onClick=${() => act('playlist.updateAndRetry')}>${u.updating ? 'Actualizando…' : 'Actualizar y reintentar'}</button>`)
            : html`<button class="btn primary" onClick=${() => act('playlist.resume')}>Reanudar</button>`)
          : html`<button class="btn secondary" onClick=${() => act('playlist.cancel')}>Cancelar</button>`}</${Actions}>`;
  };

  const QueueRow = i => html`<${Row} key=${i.id}><div class="pl-line"><${TitleBlock} item=${i} /><span class="grow"></span>${(() => {
    switch (i.status) {
      case 'downloading': return html`<span class="pl-stage">${i.stage === 'download'
          ? 'Descargando' + (i.progress != null ? ' ' + percent(i.progress) : '…') : 'Convirtiendo…'}</span>
        <div class="pl-mini"><${AccentBar} fraction=${i.stage === 'download' ? i.progress ?? null : null} /></div>`;
      case 'imported': return html`<${Chip} text="Importado" kind="ok" />`;
      case 'skipped': return html`<${Chip} text="Omitido" kind="neutral" />`;
      case 'inLibrary': return html`<${Chip} text="En la biblioteca" kind="neutral" />`;
      case 'failed': return html`<${Chip} text=${i.error?.title ?? 'Falló'} kind="error" />`;
      default: return html`<span class="pl-queued">En cola</span>`;
    }
  })()}</div></${Row}>`;

  // --- Paso 4: resumen
  const summary = () => {
    const s = snap.summary ?? {};
    const failed = items.filter(i => i.status === 'failed');
    const Stat = (label, value, color) => html`<div class="pl-stat"><div class="l">${label.toUpperCase()}</div><div class="v" style=${`color:${color}`}>${value}</div></div>`;
    return html`<${ListHeader} name=${snap.name} subtitle=${s.cancelled ? 'Cola cancelada: lo ya importado se conserva' : 'Importación terminada'} />
      <div class="pl-stats">${Stat('Importados', s.imported, 'var(--ok)')}${Stat('Omitidos', s.skipped, 'var(--text-2)')}
        ${Stat('Ya en la biblioteca', s.inLibrary, 'var(--text-2)')}${Stat('Fallidos', s.failed, s.failed > 0 ? 'var(--danger)' : 'var(--text-2)')}</div>
      ${s.imported > 0 ? html`<p class="pl-note">Los temas importados se están separando en stems; verás el avance en la Biblioteca.</p>` : null}
      ${failed.length === 0 ? html`<${Spacer} />` : html`<div class="pl-eyebrow">FALLIDOS</div>
        <${Table}>${failed.map(i => html`<${Row} key=${i.id}><div class="pl-line top"><div class="pl-ftitle"><${TitleBlock} item=${i} /></div>
          <div class="pl-ferr"><div class="e">${i.error?.title}</div>${i.error?.detail ? html`<div class="d">${i.error.detail}</div>` : null}</div></div></${Row}>`)}</${Table}>`}
      <${Actions}><button class="btn primary" onClick=${close}>Cerrar</button>
        ${s.cancelled && s.remaining > 0 ? html`<button class="btn secondary" onClick=${() => act('playlist.resume')}>Reanudar (${s.remaining})</button>` : null}
        ${failed.length ? html`<button class="btn secondary" onClick=${() => act('playlist.retryFailed')}>Reintentar fallidos (${failed.length})</button>` : null}</${Actions}>`;
  };

  let body;
  switch (snap.step) {
    case 'loading': body = loading(); break;
    case 'tracks': body = tracks(); break;
    case 'searching': body = searching(); break;
    case 'review': body = review(); break;
    case 'running': body = queue(false); break;
    case 'stopped': body = queue(true); break;
    case 'summary': body = summary(); break;
    default: body = html`<${PlaylistError} error=${snap.error ?? { title: 'No se pudo leer la lista', detail: '' }} onClose=${close} onAgain=${discard} />`;
  }
  return html`<div class="pl-root">${body}${menu ? html`<${PopupMenu} x=${menu.x} y=${menu.y} items=${menu.items} onClose=${() => setMenu(null)} />` : null}</div>`;
}

/// Estado «Leyendo la lista…» mientras `link.resolve` espera (en el Mac lo pinta `PlaylistImportView.loadingView`).
export function PlaylistLoading({ onCancel }) {
  return html`<div class="pl-root"><div class="spin-line"><span class="spinner" aria-hidden="true"></span><span>Leyendo la lista…</span></div>
    <${Spacer} /><${Actions}><button class="btn secondary" onClick=${onCancel}>Cancelar</button></${Actions}></div>`;
}

/// Paso de error (`errorView` del Mac): título, detalle, «Cerrar» y «Probar con otro enlace».
export function PlaylistError({ error, onClose, onAgain }) {
  return html`<div class="pl-root pl-error"><div class="err-block"><span class="err-icon">${icon('warning', 20)}</span><div>
      <div class="err-title">${error.title}</div>${error.detail ? html`<div class="err-detail">${error.detail}</div>` : null}</div></div>
    <${Spacer} /><${Actions}><button class="btn secondary" onClick=${onClose}>Cerrar</button>
      <button class="btn primary" onClick=${onAgain}>Probar con otro enlace</button></${Actions}></div>`;
}
