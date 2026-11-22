// Pantalla Grabar: App/Sources/RecordView.swift (RecordBody) y boceto docs/design/Record.dc.html; el Mac manda.
import { useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { entries, selectedEntry, go, loaded, screen } from '../state.js';
import { target } from '../backing/store.js';
import {
  status, openError, snap, openRecord, closeRecord, takesOf, viewRequest, prepareViewTake, markBest, deleteTake,
  study, locked,
} from '../record/store.js';
import { Preview } from '../record/preview.js';
import { RecordBar, Status } from '../record/bar.js';
import { PunchTimeline } from '../record/punch.js';
import { RecordMixer } from '../record/mixer.js';
import { PartsPanel, TakeMenu, DeleteTake, AddPart } from '../record/parts.js';
import { OffsetSheet } from '../record/offset-sheet.js';
import { TakeViewer } from '../record/viewer.js';

/// Tema de Grabar: el último abierto en Backing; si no hay, el seleccionado en la biblioteca si ya está separado.
function resolveTarget() {
  if (target.value) return target.value;
  const sel = selectedEntry.value;
  return sel && sel.separationState === 'done' ? sel.id : null;
}

/// Sin tema elegido: lista de los ya separados (RecordView.chooser).
function Chooser() {
  const ready = entries.value.filter(e => e.separationState === 'done');
  return html`<div class="screen record"><div class="backing-chooser">
    <h1 class="page-title rec-chooser-title">Grabar</h1>
    ${!loaded.value ? null : ready.length === 0
      ? html`<p class="muted">Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.</p>`
      : html`<p class="muted">Elige un tema</p>
        <div class="chooser-list">${ready.map(e => html`<button class="chooser-item" key=${e.id} onClick=${() => { target.value = e.id; }}>
          <span>${e.title}</span><span class="muted">${e.artist ?? ''}</span></button>`)}</div>`}
  </div></div>`;
}

function Header() {
  const s = snap.value;
  const entry = entries.value.find(e => e.id === s.projectId);
  const artist = entry?.artist ?? study.value?.artist;
  return html`<div class="rec-head">
    <div><div class="muted rec-song">${[artist, s.title, 'Multitoma'].filter(Boolean).join(' · ')}</div>
      <h1 class="page-title rec-title">Grabar</h1></div>
    <button class="rec-montage" disabled=${locked.value} title="Monta las mejores tomas en un vídeo" onClick=${() => go('montage')}>Ir al montaje</button></div>`;
}

function Body() {
  const s = snap.value;
  const [expanded, setExpanded] = useState(false);
  const [adding, setAdding] = useState(false);
  const [menu, setMenu] = useState(null);       // { take, number, best, x, y }
  const [deleting, setDeleting] = useState(null);
  const [viewing, setViewing] = useState(null); // { takeId, title }
  // «Eliminar toma» desde el visor: se borra cuando el visor ya se desmontó (su limpieza suelta el `<video>` de
  // `video.mov` y manda `takeview.close`), no antes: en NTFS no se borra un fichero abierto. El núcleo cierra además el
  // visor de esa toma antes de borrar (RecordController.deleteTake).
  const [deleteAfterView, setDeleteAfterView] = useState(null);
  useEffect(() => {
    if (!deleteAfterView || viewing) return;
    setDeleteAfterView(null);
    deleteTake(deleteAfterView);
  }, [deleteAfterView, viewing]);
  // «Ver toma» pedido desde la Biblioteca: se abre al estar lista la pantalla.
  useEffect(() => {
    const r = viewRequest.value;
    if (!r) return;
    viewRequest.value = null;
    const part = s.parts.find(p => p.takes.some(t => t.id === r.takeId));
    if (part) {
      const i = takesOf(part).findIndex(t => t.id === r.takeId);
      prepareViewTake().then(ok => { if (ok) setViewing({ takeId: r.takeId, title: `Toma ${i + 1} · ${part.name}` }); });
    }
  }, []);
  const view = async (take, number, part) => {
    if (await prepareViewTake()) setViewing({ takeId: take.id, title: `Toma ${number} · ${part.name}` });
  };
  const viewed = viewing && s.parts.flatMap(p => p.takes).find(t => t.id === viewing.takeId);
  const viewedPart = viewing && s.parts.find(p => p.takes.some(t => t.id === viewing.takeId));
  // Si la toma del visor desaparece (borrada), se cierra solo.
  useEffect(() => { if (viewing && !viewed) setViewing(null); }, [viewed]);
  return html`<div class="rec-body">
    <${Header} />
    <div class="rec-cols">
      <div class="rec-main">
        <${Preview} /><${RecordBar} /><${Status} />
        ${s.punch?.enabled ? html`<${PunchTimeline} />` : null}
        <${RecordMixer} expanded=${expanded} onToggle=${() => setExpanded(!expanded)} /></div>
      <${PartsPanel} onView=${view} onAdd=${() => setAdding(true)}
        onMenu=${(take, number, best, x, y) => setMenu({ take, number, best, x, y })} /></div>
    ${s.offset ? html`<${OffsetSheet} key=${s.offset.takeId} />` : null}
    ${adding ? html`<${AddPart} onClose=${() => setAdding(false)} />` : null}
    ${menu ? html`<${TakeMenu} menu=${menu} onClose=${() => setMenu(null)} onDelete=${id => setDeleting(id)} />` : null}
    ${deleting ? html`<${DeleteTake} takeId=${deleting} onClose=${() => setDeleting(null)} />` : null}
    ${viewing && viewed ? html`<${TakeViewer} key=${viewing.takeId} title=${viewing.title} take=${viewed}
      isBest=${viewedPart?.bestTakeId === viewing.takeId}
      onMarkBest=${() => markBest(viewing.takeId)}
      onDelete=${() => { setDeleteAfterView(viewing.takeId); setViewing(null); }}
      onClose=${() => setViewing(null)} />` : null}
  </div>`;
}

export function Record() {
  const id = resolveTarget();
  // study.open + record.open al entrar o cambiar de tema; record.close (y study.close, salvo rumbo a Montaje) al salir.
  useEffect(() => {
    if (!id) return undefined;
    openRecord(id);
    return () => { closeRecord({ keepStudy: screen.value === 'montage' }); };
  }, [id]);
  if (!id) return html`<${Chooser} />`;
  const s = status.value;
  if (s === 'error') {
    const e = openError.value;
    return html`<div class="screen record"><div class="empty error"><b>No se pudo abrir Grabar</b>
      <span class="muted">${e?.message} <code>(${e?.code})</code></span>
      <div><button class="btn secondary" onClick=${() => openRecord(id)}>Reintentar</button></div></div></div>`;
  }
  if (s !== 'ready' || !snap.value) return html`<div class="screen record"><div class="backing-loading muted"><span class="spinner" aria-hidden="true"></span>Abriendo el tema…</div></div>`;
  const unseparated = snap.value.mix.channels.length === 0 && (study.value?.emptyStems ?? []).length === 0;
  if (unseparated) {
    return html`<div class="screen record"><section class="card not-separated"><h2>Este tema aún no está separado</h2>
      <p class="muted">Grabar necesita los stems. Sepáralo desde la biblioteca y vuelve.</p>
      <div><button class="btn secondary" onClick=${() => go('library')}>Ir a la biblioteca</button></div></section></div>`;
  }
  return html`<div class="screen record"><${Body} /></div>`;
}
