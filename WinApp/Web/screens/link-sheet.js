import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { icon } from '../icons.js';
import { call } from '../bridge.js';
import { Modal, AccentBar } from '../ui.js';
import { openProject, notify } from '../state.js';

// Hoja «Importar desde enlace» (LinkImportSheet del Mac) sobre link.resolve / link.import (contrato 8.3b).
// Estados: empty -> resolving -> candidates | repeated | error. Al importar, la hoja se cierra y el progreso
// (download / import) se ve en la fila de la biblioteca.

/// Texto de los enlaces admitidos (SourceMessages.supportedLinks del Mac).
export const SUPPORTED_LINKS = 'Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track). Listas, álbumes y episodios no.'; // listas y álbumes: ola 2; entonces vuelve el literal del Mac
/// Umbral de «cercano» del Mac (CandidateRanker.closeThreshold): ±3 s respecto a la duración de Spotify.
const CLOSE_THRESHOLD_S = 3;
/// Tras este tiempo de «Leyendo metadatos…» un enlace de Spotify pasa a «Buscando en YouTube…» (el núcleo no informa de etapas).
const SEARCH_STAGE_AFTER_MS = 1500;

/// «Importar» del popup (ImportQuery.classify del Mac, spec 7b punto 3): un enlace sigue el recorrido de siempre; lo demás
/// se busca en Spotify. Sin esquema se aceptan estos prefijos.
const SCHEMELESS_PREFIXES = ['www.', 'youtube.com', 'youtu.be', 'music.youtube.com', 'open.spotify.com'];
export function classify(text) {
  const s = (text ?? '').trim();
  if (!s) return { kind: 'empty' };
  const lower = s.toLowerCase();
  if (lower.startsWith('spotify:')) return { kind: 'link', value: s };
  if (!/\s/.test(s)) {
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      let host = '';
      try { host = new URL(s).hostname; } catch { /* sin host válido: búsqueda */ }
      return host ? { kind: 'link', value: s } : { kind: 'search', value: s };
    }
    if (SCHEMELESS_PREFIXES.some(p => lower.startsWith(p))) return { kind: 'link', value: 'https://' + s };
  }
  return { kind: 'search', value: s };
}

const isSpotify = u => /spotify/i.test(u);
const fmtDur = s => { const t = Math.round(s); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
const signed = s => `${s >= 0 ? '+' : '−'}${Math.abs(s).toFixed(1).replace('.', ',')} s`;

/// Los errores RPC traen `message` = "título\ndetalle".
export function splitMessage(message) {
  const i = (message ?? '').indexOf('\n');
  return i < 0 ? { title: message || 'No se pudo importar', detail: '' } : { title: message.slice(0, i), detail: message.slice(i + 1) };
}

function Cover({ url, size = 104 }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [url]);
  return html`<div class="cover" style=${`width:${size}px;height:${size}px;border-radius:10px`}>
    ${url && !bad ? html`<img src=${url} alt="" referrerpolicy="no-referrer" draggable="false" onError=${() => setBad(true)} />` : null}
    <span class="cover-ph">${icon('music', 28)}</span></div>`;
}

const Banner = ({ error, children }) => html`<div class=${'banner ' + (error ? 'error' : 'info')}>${children}</div>`;
const Field = ({ label, value, onInput, onEnter, placeholder, autofocus, action }) => html`<label class="field">${label ? html`<span>${label}</span>` : null}
  ${action ? html`<div class="field-row">${FieldInput({ value, onInput, onEnter, placeholder, autofocus })}${action}</div>`
    : FieldInput({ value, onInput, onEnter, placeholder, autofocus })}</label>`;
const FieldInput = ({ value, onInput, onEnter, placeholder, autofocus }) => html`<input value=${value} placeholder=${placeholder}
  data-autofocus=${autofocus ? '1' : undefined} onInput=${e => onInput(e.currentTarget.value)}
  onKeyDown=${e => { if (e.key === 'Enter') { e.preventDefault(); onEnter?.(); } }} />`;

export function LinkSheet({ onClose, onPickFile }) {
  const [screen, setScreen] = useState('empty');
  const [text, setText] = useState('');
  const [resolved, setResolved] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [title, setTitle] = useState('');
  const [artist, setArtist] = useState('');
  const [error, setError] = useState(null);       // { code, title, detail }
  const [banner, setBanner] = useState(null);     // error inmediato de link.import (se queda en candidatos)
  const [stage, setStage] = useState('metadata');
  const [busy, setBusy] = useState(false);
  const [latest, setLatest] = useState(false);    // «yt-dlp ya es la última versión»
  const [search, setSearch] = useState({ kind: 'idle' });   // idle | searching | results {query, tracks} | failed {message}
  const [manual, setManual] = useState('');       // «¿Ninguno convence? Pega un enlace de YouTube»
  const [manualError, setManualError] = useState(null);
  const token = useRef(0);
  const manualLinks = useRef([]);              // enlaces manuales añadidos con éxito (manualLinks del Mac)
  const searchToken = useRef(0);
  const url = text.trim();
  const query = classify(text);
  const searching = search.kind === 'searching';
  const isBusy = searching || busy;

  /// «Importar» del popup: enlace -> resolver; texto -> buscar en Spotify (`link.search`).
  const importTapped = () => {
    if (isBusy) return;
    if (query.kind === 'link') { searchToken.current++; setSearch({ kind: 'idle' }); setText(query.value); resolve(query.value); }
    else if (query.kind === 'search') runSearch(query.value);
  };

  const runSearch = async q => {
    const mine = ++searchToken.current;
    setSearch({ kind: 'searching' });
    try {
      const r = await call('link.search', { query: q }, { timeout: 30000 });
      if (mine === searchToken.current) setSearch({ kind: 'results', query: r.query ?? q, tracks: r.tracks ?? [] });
    } catch (e) {
      if (mine === searchToken.current && e.code !== 'cancelled') setSearch({ kind: 'failed', message: splitMessage(e.message).title });
    }
  };

  /// «Elegir»: lanza el flujo de enlace con la pista.
  const choose = t => { if (isBusy) return; setText(t.trackURL); resolve(t.trackURL); };

  /// «Añadir»: el enlace de YouTube pegado a mano entra el primero de los candidatos (spec 7b; `addManual` del Mac).
  const addManual = async () => {
    const t = manual.trim();
    if (!t || isBusy) return;
    setManualError(null); setBusy(true);
    try {
      const r = await call('link.addManual', { url: t }, { timeout: 120000 });
      setResolved(r.resolution);
      setSelectedId(r.selectable ? r.added : null);
      manualLinks.current.push(t);
      setManual(''); setBanner(null);
    } catch (e) {
      const m = splitMessage(e.message);
      setManualError(m.detail || m.title);
    } finally { setBusy(false); }
  };

  /// Devuelve la resolución si sigue vigente (null si falla o se cancela). `retry`: «Actualizar y reintentar», conserva lo manual.
  const resolve = async (link, { retry = false } = {}) => {
    const mine = ++token.current;
    if (!retry) { manualLinks.current = []; setManual(''); }
    setManualError(null);
    setScreen('resolving'); setStage('metadata'); setError(null); setBanner(null); setLatest(false);
    const timer = isSpotify(link) ? setTimeout(() => { if (mine === token.current) setStage('searching'); }, SEARCH_STAGE_AFTER_MS) : null;
    try {
      const r = await call('link.resolve', { url: link }, { timeout: 120000 });
      if (mine !== token.current) return null;
      setResolved(r);
      setTitle(r.title ?? ''); setArtist(r.artist ?? '');
      const first = r.candidates.find(c => !c.inLibrary);
      setSelectedId(first?.id ?? null);
      setScreen(r.existing ? 'repeated' : 'candidates');
      return r;
    } catch (e) {
      if (mine !== token.current || e.code === 'cancelled') return null;
      setError({ code: e.code ?? 'internal', ...splitMessage(e.message) });
      setScreen('error');
      return null;
    } finally { clearTimeout(timer); }
  };

  const cancelResolve = () => { token.current++; call('link.cancel').catch(() => {}); setScreen('empty'); };

  const startImport = async () => {
    setBusy(true); setBanner(null);
    try {
      await call('link.import', { candidateId: selectedId, title: title.trim(), artist: artist.trim() || null });
      onClose();
    } catch (e) {
      setBanner(splitMessage(e.message).detail || splitMessage(e.message).title);
      setBusy(false);
    }
  };

  /// Como `updateAndRetry` del Mac: tras resolver de nuevo reañade los enlaces manuales (ignorando errores) y restaura
  /// título, artista y candidato elegido si sigue existiendo; si no, queda lo que eligió `resolve`.
  const updateAndRetry = async () => {
    setBusy(true);
    try {
      const r = await call('tools.updateYtDlp', {}, { timeout: 200000 });
      setBusy(false);
      if (r.alreadyLatest) { setLatest(true); return; }
    } catch (e) { setBusy(false); setError({ code: e.code ?? 'internal', ...splitMessage(e.message) }); return; }
    const saved = { title, artist, selectedId };
    const links = [...manualLinks.current];
    let res = await resolve(url, { retry: true });
    if (!res || res.existing) return;
    const mine = token.current;
    for (const l of links) {
      try {
        const m = await call('link.addManual', { url: l }, { timeout: 120000 });
        if (mine !== token.current) return;
        res = m.resolution;
      } catch { /* se ignora, como en el Mac */ }
    }
    if (mine !== token.current) return;
    setResolved(res);
    setTitle(saved.title); setArtist(saved.artist);
    const keep = res.candidates.find(c => c.id === saved.selectedId && !c.inLibrary);
    setSelectedId(keep ? keep.id : (res.candidates.find(c => !c.inLibrary)?.id ?? null));
  };

  const openExisting = id => { onClose(); openProject(id); };
  const canClose = screen !== 'resolving';
  const close = () => { if (screen === 'resolving') cancelResolve(); else onClose(); };

  let body;
  if (screen === 'empty') {
    body = html`<div class="field-spin"><${Field} label="" placeholder="Pega un enlace o busca en Spotify" value=${text} onInput=${setText} autofocus=${true}
        onEnter=${importTapped} />${searching ? html`<span class="spinner" aria-hidden="true"></span>` : null}</div>
      ${search.kind === 'results' ? (search.tracks.length === 0
        ? html`<p class="search-none">Spotify no ha encontrado nada para «${search.query}»</p>`
        : html`<div class="track-list">${search.tracks.map(t => TrackRow({ t, busy: isBusy, choose }))}</div>`)
        : html`${search.kind === 'failed' ? html`<${Banner} error=${true}>${search.message}</${Banner}>` : null}
          <p class="hint">${SUPPORTED_LINKS}</p>`}
      <div class="modal-actions">
        <button class="btn secondary" disabled=${isBusy} onClick=${() => { onClose(); onPickFile?.(); }}>Importar fichero…</button>
        <span class="grow"></span>
        <button class="btn secondary" onClick=${close}>Cancelar</button>
        <button class="btn primary" disabled=${isBusy || query.kind === 'empty'} onClick=${importTapped}>Importar</button></div>`;
  } else if (screen === 'resolving') {
    body = html`<div class="spin-line"><span class="spinner" aria-hidden="true"></span>
        <span>${stage === 'metadata' ? 'Leyendo metadatos…' : 'Buscando en YouTube…'}</span></div>
      ${stage === 'searching' ? html`<p class="hint">Suele tardar unos 9 s.</p>` : null}
      <div class="modal-actions"><button class="btn secondary" onClick=${cancelResolve}>Cancelar</button></div>`;
  } else if (screen === 'repeated') {
    const e = resolved.existing;
    body = html`<div class="ok-line">${icon('check', 18)}<span>Ya está en la biblioteca</span></div>
      <div class="existing"><div class="t">${e.title}</div>${e.artist ? html`<div class="a">${e.artist}</div>` : null}</div>
      <p class="hint">No se busca ni se descarga nada.</p>
      <div class="modal-actions"><button class="btn secondary" onClick=${onClose}>Cerrar</button>
        <button class="btn primary" onClick=${() => openExisting(e.id)}>Abrir</button></div>`;
  } else if (screen === 'candidates') {
    const r = resolved;
    const single = r.link === 'youtube' && r.candidates.length === 1;
    const p = r.possibleDuplicate;
    body = html`<div class="link-head"><${Cover} url=${r.thumbnail ?? r.candidates[0]?.thumbnail} />
        <div class="link-fields">
          <${Field} label="Título" value=${title} onInput=${setTitle} placeholder="Título" />
          <${Field} label="Artista" value=${artist} onInput=${setArtist} placeholder="Artista" /></div></div>
      ${p ? html`<div class="band">${icon('info', 16)}<span>Puede que ya lo tengas: ${[p.title, p.artist].filter(Boolean).join(' · ')}</span>
        <button class="btn secondary xs" onClick=${() => openExisting(p.id)}>Abrir</button></div>` : null}
      ${banner ? html`<${Banner} error=${true}>${banner}</${Banner}>` : null}
      ${single ? html`<div class="cand-block"><div class="eyebrow">VÍDEO A IMPORTAR</div>${CandidateBox({ c: r.candidates[0], single: true })}</div>`
        : html`<div class="cand-block"><div class="eyebrow-row"><span class="eyebrow">CANDIDATOS EN YOUTUBE</span>
            ${r.duration != null ? html`<span class="muted small">Spotify: ${fmtDur(r.duration)}</span>` : null}</div>
          ${r.noCloseCandidate ? html`<${Banner}>${r.candidates.length === 0
            ? 'La búsqueda no ha dado resultados. Pega a mano un enlace de YouTube.'
            : `Ningún candidato queda a ${CLOSE_THRESHOLD_S} s o menos de la duración de Spotify. Elige con cuidado o pega a mano un enlace de YouTube.`}</${Banner}>` : null}
          <div class="cand-list" role="radiogroup" aria-label="Candidatos">${r.candidates.map(c => CandidateBox({
            c, on: selectedId === c.id && !c.inLibrary, pick: () => !c.inLibrary && setSelectedId(c.id), open: openExisting }))}</div>
          <${Field} label="¿Ninguno convence? Pega un enlace de YouTube" value=${manual} onInput=${setManual} onEnter=${addManual}
            placeholder="https://www.youtube.com/watch?v=…" action=${html`<button class="btn secondary" disabled=${!manual.trim() || isBusy}
              onClick=${addManual}>Añadir</button>`} />
          ${manualError ? html`<div class="manual-error">${manualError}</div>` : null}</div>`}
      <div class="modal-actions"><button class="btn secondary" onClick=${onClose}>Cancelar</button>
        <button class="btn primary" disabled=${busy || !selectedId || !title.trim()} onClick=${startImport}>Importar</button></div>`;
  } else {
    const suggestsUpdate = error.code === 'extractor-broken';
    const again = error.code === 'unsupported-link' || error.code === 'spotify-unreadable';
    body = html`<div class="err-block"><span class="err-icon">${icon('warning', 20)}</span><div>
        <div class="err-title">${error.title}</div>${error.detail ? html`<div class="err-detail">${error.detail}</div>` : null}</div></div>
      ${latest ? html`<${Banner}>yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Mientras, importa el fichero a mano (Importar tema > Desde fichero…).</${Banner}>` : null}
      <div class="modal-actions"><button class="btn secondary" onClick=${onClose}>Cerrar</button>
        ${suggestsUpdate && !latest ? html`<button class="btn primary" disabled=${busy} onClick=${updateAndRetry}>Actualizar y reintentar</button>`
          : again ? html`<button class="btn primary" onClick=${() => { setText(''); setScreen('empty'); }}>${error.code === 'unsupported-link' ? 'Probar con otro enlace' : 'Pegar un enlace de YouTube'}</button>`
          : !latest ? html`<button class="btn primary" onClick=${() => resolve(url)}>Reintentar</button>` : null}</div>`;
  }

  const heading = screen === 'empty' ? 'Importar tema' : 'Importar desde enlace';
  return html`<${Modal} title=${heading} width=${screen === 'empty' ? 620 : 560} onClose=${canClose ? close : close} autofocus="[data-autofocus],.modal-actions .btn.primary,input">${body}</${Modal}>`;
}

/// Fila de candidato (YouTube único o lista de Spotify). `on`: elegido; `open`: abrir el tema que ya está en la biblioteca.
function CandidateBox({ c, on, pick, open, single }) {
  const inLib = c.inLibrary;
  return html`<div class=${'cand' + (on ? ' on' : '') + (inLib ? ' dim' : '') + (single ? ' single' : '')} key=${c.id} role=${single ? undefined : 'radio'}
      aria-checked=${single ? undefined : !!on} tabindex=${single || inLib ? undefined : 0}
      onClick=${pick} onKeyDown=${e => { if ((e.key === ' ' || e.key === 'Enter') && pick) { e.preventDefault(); pick(); } }}>
    ${single ? null : html`<span class=${'radio' + (on ? ' on' : '')} aria-hidden="true"></span>`}
    <${Thumb} url=${c.thumbnail} />
    <div class="cand-text"><div class="t" title=${c.title}>${c.title}</div>
      <div class="a" title=${[c.artist, c.duration != null ? fmtDur(c.duration) : null].filter(Boolean).join(' · ')}>${[c.artist, c.duration != null ? fmtDur(c.duration) : null].filter(Boolean).join(' · ')}</div></div>
    <span class="grow"></span>
    ${c.difference != null ? html`<span class="diff">${signed(c.difference)}</span>` : null}
    ${c.isClose ? html`<span class="chip ok">cercano</span>` : null}
    ${c.isLive ? html`<span class="chip neutral">directo</span>` : null}
    ${inLib ? html`<span class="chip neutral">En la biblioteca</span>
      <button class="btn secondary xs" onClick=${e => { e.stopPropagation(); open(inLib.id); }}>Abrir</button>`
      : html`<a class="ext" href=${c.url} target="_blank" rel="noopener noreferrer" title="Abrir en el navegador" aria-label="Abrir en el navegador"
          onClick=${e => e.stopPropagation()}>${icon('external', 16)}</a>`}</div>`;
}

function Thumb({ url }) {
  const [bad, setBad] = useState(false);
  return html`<div class="thumb">${url && !bad ? html`<img src=${url} alt="" referrerpolicy="no-referrer" draggable="false" onError=${() => setBad(true)} />` : icon('music', 16)}</div>`;
}

/// Fila de resultado de la búsqueda de Spotify (trackRow del Mac): carátula 36 px, nombre, artistas, álbum · año, duración,
/// ▶ «Oír en Spotify» y «Elegir».
function TrackRow({ t, busy, choose }) {
  return html`<div class="track" key=${t.id}><${TrackArt} url=${t.imageURL} />
    <div class="track-text"><div class="n" title=${t.name}>${t.name}</div>
      <div class="ar" title=${(t.artists ?? []).join(', ')}>${(t.artists ?? []).join(', ')}</div>
      <div class="al" title=${t.year != null ? `${t.album} · ${t.year}` : t.album}>${t.year != null ? `${t.album} · ${t.year}` : t.album}</div></div>
    <span class="dur">${t.durationText}</span>
    <button type="button" class="listen" title="Oír en Spotify" aria-label="Oír en Spotify"
      onClick=${() => call('host.openURL', { urls: [t.appURL ?? (t.id ? `spotify:track:${t.id}` : ''), t.trackURL].filter(Boolean) }).catch(() => {})}>${icon('play', 14)}</button>
    <button class="btn secondary sm" disabled=${busy} onClick=${() => choose(t)}>Elegir</button></div>`;
}

function TrackArt({ url }) {
  const [bad, setBad] = useState(false);
  return html`<div class="track-art">${url && !bad ? html`<img src=${url} alt="" referrerpolicy="no-referrer" draggable="false" onError=${() => setBad(true)} />` : icon('music', 16)}</div>`;
}
