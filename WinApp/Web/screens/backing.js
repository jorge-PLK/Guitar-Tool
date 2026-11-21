import { computed } from '@preact/signals';
import { Fragment } from 'preact';
import { useEffect } from 'preact/hooks';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { entries, selectedEntry, go, loaded } from '../state.js';
import {
  target, status, openError, study, transport, audioError, chordsExpanded, openStudy, closeStudy, togglePlay,
  setLoop, setMix, seek, analyze,
} from '../backing/store.js';
import { SectionTools, SectionPanel, openSectionPanel } from '../backing/sections.js';
import { ChordStrip } from '../backing/strip.js';
import { ChordGrid } from '../backing/grid.js';
import { ChordEditToggle, chordEditMode } from '../backing/chord-editor.js';
import { Mixer } from '../backing/mixer.js';
import { ProgressBar, TransportBar, InfoRow, ChordCard } from '../backing/controls.js';
import { fmtClock } from '../backing/model.js';

const store = (() => { try { return window.localStorage; } catch { return null; } })();
let demoDone = false;
const expandedKey = id => `backing.chordsExpanded.${id}`;

const chordList = computed(() => study.value?.analysis?.chords ?? []);
const sectionList = computed(() => study.value?.sections ?? []);

/// Tema de Backing: el último abierto; si no hay, el seleccionado en la biblioteca si ya está separado.
function resolveTarget() {
  if (target.value) return target.value;
  const sel = selectedEntry.value;
  return sel && sel.separationState === 'done' ? sel.id : null;
}

/// Sin tema elegido: lista de los ya separados (BackingView.chooser).
function Chooser() {
  const ready = entries.value.filter(e => e.separationState === 'done');
  return html`<div class="screen backing"><div class="backing-chooser">
    <h1 class="page-title">Backing track</h1>
    ${!loaded.value ? null : ready.length === 0
      ? html`<p class="muted">Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.</p>`
      : html`<p class="muted">Elige un tema</p>
        <div class="chooser-list">${ready.map(e => html`<button class="chooser-item" key=${e.id} onClick=${() => { target.value = e.id; }}>
          <span>${e.title}</span><span class="muted">${e.artist ?? ''}</span></button>`)}</div>`}
  </div></div>`;
}

function Banner({ kind, children }) {
  return html`<div class=${'banner ' + (kind ?? '')} role=${kind === 'danger' ? 'alert' : 'status'}>${children}</div>`;
}

function Banners() {
  const s = study.value;
  if (!s) return null;
  const a = s.analysis ?? {};
  return html`<${Fragment}>
    ${s.loadError ? html`<${Banner} kind="danger"><span>${s.loadError}</span></${Banner}>` : null}
    ${audioError.value ? html`<${Banner} kind="danger"><span>${audioError.value}</span>
      <button class="btn secondary sm" onClick=${() => { audioError.value = null; }}>Cerrar</button></${Banner}>` : null}
    ${a.state === 'analyzing' ? html`<${Banner}><span class="spinner" aria-hidden="true"></span>
      <span>Analizando acordes y pulso… Puedes reproducir mientras tanto.</span></${Banner}>` : null}
    ${a.state === 'missing' ? html`<${Banner}><span>Sin análisis de acordes ni pulso todavía.</span>
      <button class="btn secondary sm banner-btn" onClick=${analyze}>Analizar</button></${Banner}>` : null}
    ${a.state === 'failed' ? html`<${Banner} kind="danger"><span>No se pudo analizar: ${a.error ?? 'error desconocido'}</span>
      <button class="btn secondary sm banner-btn" onClick=${analyze}>Reintentar</button></${Banner}>` : null}
  </${Fragment}>`;
}
function GuitarsToggle() {
  const guitars = (transport.value?.channels ?? []).filter(c => c.kind === 'guitar');
  if (!guitars.length) return null;
  const off = guitars.every(c => c.muted);
  return html`<button class=${'chip-btn' + (off ? ' on' : '')} aria-pressed=${off}
    onClick=${() => guitars.forEach(c => setMix(c.id, { muted: !off }))}>Sin guitarras</button>`;
}

function TimelineCard() {
  const chords = chordList.value, sections = sectionList.value;
  const a = study.value.analysis ?? {};
  const t = transport.value;
  const expanded = chordsExpanded.value;
  const tr = t?.transpose ?? 0;
  const loop = t?.loop ?? null;
  const common = { chords, sections, analysis: a, transpose: tr, loop, edit: chordEditMode.value, overrides: study.value?.chordOverrides, onSeek: s => seek(s), onSection: (id, x, y) => openSectionPanel(id, x, y), onLoop: (s, e, name) => (s == null ? setLoop(null) : setLoop(s, e, name)) };
  const toggle = () => {
    chordsExpanded.value = !expanded;
    try { store?.setItem(expandedKey(study.value.projectId), chordsExpanded.value ? '1' : '0'); } catch { /* sin almacenamiento */ }
  };
  const empty = chords.length === 0;
  return html`<section class="card timeline" aria-label="Línea de tiempo">
    <div class="tl-head">
      <h2>Acordes</h2>
      <${ChordEditToggle} />
      <span class=${'small hint ' + (chordEditMode.value ? 'accent-text' : 'muted')}>${chordEditMode.value
        ? 'Modo edición: clic en un acorde para cambiarlo o partirlo. No se marcan bucles.' : 'Clic: saltar · arrastrar: bucle (Alt = compases)'}</span>
      <span class="grow"></span>
      <${SectionTools} editMode=${chordEditMode.value} hasChords=${!empty} />
      <button class="btn secondary xs" aria-label=${expanded ? 'Plegar acordes' : 'Expandir acordes'} aria-expanded=${expanded} onClick=${toggle}>
        ${expanded ? 'Plegar' : 'Expandir'}<span class=${'chev' + (expanded ? ' up' : '')}>${icon('chevronLeft', 14)}</span></button>
    </div>
    <div class=${'chords-area' + (chordEditMode.value ? ' editing' : '')}>
      ${empty && !expanded
        ? html`<div class="chords-empty muted">${a.state === 'ready' ? 'Sin acordes detectados.' : 'Los acordes aparecerán al terminar el análisis.'}</div>`
        : expanded ? html`<${ChordGrid} ...${common} />` : html`<${ChordStrip} ...${common} />`}
      <${ChordCard} chords=${chords} />
    </div>
    <${InfoRow} />
    <${ProgressBar} />
    <${TransportBar} />
  </section>`;
}

function Content() {
  const s = study.value;
  const unseparated = (transport.value?.channels ?? []).length === 0 && (s.emptyStems ?? []).length === 0;
  return html`<div class="backing-body">
    <div class="backing-head">
      <div><div class="muted song">${[s.artist, s.title].filter(Boolean).join(' · ')}</div>
        <h1 class="page-title backing-title">Backing track</h1></div>
      <div class="bk-head-actions">
        <${GuitarsToggle} />
        <button class="chip-btn" onClick=${() => go('tab')}>${icon('tab', 14)}Tablatura</button>
      </div>
    </div>
    ${unseparated ? html`<section class="card not-separated"><h2>Este tema aún no está separado</h2>
      <p class="muted">Backing track necesita los stems. Sepáralo desde la biblioteca y vuelve.</p>
      <div><button class="btn secondary" onClick=${() => go('library')}>Ir a la biblioteca</button></div></section>`
      : html`<${Banners} /><${TimelineCard} /><${Mixer} /><${SectionPanel} />`}
  </div>`;
}

export function Backing() {
  const id = resolveTarget();
  // study.open al entrar o cambiar de tema; study.close al salir de la pantalla o cambiar de tema.
  useEffect(() => {
    if (!id) return undefined;
    try { chordsExpanded.value = store?.getItem(expandedKey(id)) === '1'; } catch { chordsExpanded.value = false; }
    openStudy(id);
    return () => { closeStudy(); };
  }, [id]);
  // Gancho de QA (`?demo=`): ver backing/demo.js. Una sola vez por carga de página.
  useEffect(() => {
    const demo = new URLSearchParams(location.search).get('demo');
    if (demo && status.value === 'ready' && !demoDone) { demoDone = true; import('../backing/demo.js').then(m => m.runDemo(demo)); }
  }, [status.value]);
  // Barra espaciadora = reproducir/pausar (como el Mac), salvo escribiendo en un campo.
  useEffect(() => {
    const onKey = e => {
      if (e.code !== 'Space' || e.repeat || e.ctrlKey || e.metaKey || e.altKey) return;
      const tag = e.target?.tagName;
      if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
      if (status.value !== 'ready') return;
      e.preventDefault();
      togglePlay();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  if (!id) return html`<${Chooser} />`;
  const s = status.value;
  let body;
  if (s === 'error') {
    const e = openError.value;
    body = html`<div class="empty error"><b>No se pudo abrir el tema</b>
      <span class="muted">${e?.message} <code>(${e?.code})</code></span>
      <div><button class="btn secondary" onClick=${() => openStudy(id)}>Reintentar</button></div></div>`;
  } else if (s !== 'ready' || !study.value) {
    body = html`<div class="backing-loading muted"><span class="spinner" aria-hidden="true"></span>Abriendo el tema…</div>`;
  } else body = html`<${Content} />`;
  return html`<div class="screen backing">${body}</div>`;
}
