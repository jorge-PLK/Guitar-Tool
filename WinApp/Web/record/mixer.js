// Mezclador de Grabar (RecordMixer del Mac): compacto por defecto (Master, nivel de la guitarra y M/S por canal) y expandido
// (faders y medidores). Canales «Tú · parte» para la mejor toma de cada otra parte. Faders y vúmetros del mezclador de Backing.
import { useRef, useEffect, useLayoutEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { Fader, Toggle, paintMeter } from '../backing/mixer.js';
import { FADER_MIN_DB, FADER_MAX_DB, FADER_SNAP_DB } from '../backing/store.js';
import { fmtDb } from '../backing/model.js';
import { snap, levels, onLevels, setMix, setMaster } from './store.js';

const dim = (c, anySolo) => c.muted || (anySolo && !c.solo);

function InputBar({ cls }) {
  const el = useRef(null);
  useEffect(() => {
    const paint = () => { if (el.current) el.current.style.clipPath = `inset(${(1 - Math.min(Math.max(levels.input, 0), 1)) * 100}% 0 0 0)`; };
    paint();
    return onLevels(paint);
  }, []);
  return html`<div class=${'rec-in ' + cls} aria-hidden="true"><div class="rec-in-fill" ref=${el}></div></div>`;
}

function Channel({ c, anySolo, meters }) {
  const bar = useRef(null), dbText = useRef(null);
  const d = dim(c, anySolo);
  useEffect(() => { meters.set(c.id, bar.current); return () => meters.delete(c.id); }, [c.id]);
  useEffect(() => { paintMeter(bar.current, d ? null : levels.channels[c.id]); }, [d, c.id]);
  const forced = !!c.forcedMuted;
  return html`<div class=${'chan' + (d ? ' dim' : '')}>
    <div class="chan-title" title=${c.name}>${c.name}</div>
    <div class="chan-body">
      <${Fader} db=${c.gainDB} label=${c.name} dbRef=${dbText}
        onChange=${v => setMix(c.id, { gainDB: v }, { optimistic: false })} onCommit=${v => setMix(c.id, { gainDB: v })} />
      <div class="meter" aria-hidden="true"><div class="meter-fill" ref=${bar}></div></div></div>
    <div class="chan-db" ref=${dbText}>${c.muted ? 'Silenciado' : fmtDb(c.gainDB)}</div>
    <div class="chan-btns">
      <${Toggle} text="M" on=${c.muted} label=${(c.muted ? 'Activar ' : 'Silenciar ') + c.name} onClick=${() => { if (!forced) setMix(c.id, { muted: !c.muted }); }} />
      <${Toggle} text="S" on=${c.solo} label=${'Solo ' + c.name} onClick=${() => { if (!forced) setMix(c.id, { solo: !c.solo }); }} />
    </div></div>`;
}

function Expanded({ chs, anySolo, master }) {
  const meters = useRef(new Map()).current;
  const dbText = useRef(null);
  useEffect(() => onLevels(l => {
    for (const [id, el] of meters) {
      const c = chs.find(x => x.id === id);
      paintMeter(el, c && dim(c, anySolo) ? null : l.channels[id]);
    }
  }), [chs, anySolo]);
  return html`<div class="mixer-body">
    <div class="chan master"><div class="chan-title">Master</div>
      <div class="chan-body"><${Fader} db=${master} label="Master" dbRef=${dbText} onChange=${v => setMaster(v)} onCommit=${v => setMaster(v)} /></div>
      <div class="chan-db" ref=${dbText}>${fmtDb(master)}</div><div class="chan-btns-spacer"></div></div>
    <div class="chan input"><div class="chan-title">Tu guitarra</div>
      <div class="chan-body"><${InputBar} cls="big" /></div>
      <div class="chan-db">Entrada</div><div class="chan-btns-spacer"></div></div>
    <div class="mix-sep tall"></div>
    <div class="mix-chans">${chs.map(c => html`<${Channel} key=${c.id} c=${c} anySolo=${anySolo} meters=${meters} />`)}</div></div>`;
}

/// Canal compacto: nombre y M/S. La guitarra de la parte que se graba se ve silenciada y no se reactiva.
function Compact({ chs, anySolo, master }) {
  const wrap = useRef(null), head = useRef(null), list = useRef(null);
  const [one, setOne] = useState(true);
  // Una sola línea si Master, la entrada y los canales caben; si no, los canales pasan a una segunda línea (ViewThatFits del Mac).
  useLayoutEffect(() => {
    const measure = () => {
      if (!wrap.current) return;
      const need = head.current.offsetWidth + list.current.scrollWidth + 2 * 10 + 1;
      setOne(need <= wrap.current.clientWidth);
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(wrap.current);
    return () => ro.disconnect();
  }, [chs.length, chs.map(c => c.name).join('|')]);
  const pct = ((master - FADER_MIN_DB) / (FADER_MAX_DB - FADER_MIN_DB)) * 100;
  return html`<div class=${'rec-compact' + (one ? ' one' : '')} ref=${wrap}>
    <div class="rec-chead" ref=${head}>
      <span class="rec-master"><b>Master</b>
        <input type="range" class="rec-range" min=${FADER_MIN_DB} max=${FADER_MAX_DB} step="0.5" value=${master} aria-label="Volumen Master"
          style=${`--p:${pct}%`}
          onInput=${e => { const v = +e.currentTarget.value; setMaster(Math.abs(v) < FADER_SNAP_DB ? 0 : v); }} />
        <span class="rec-master-db">${fmtDb(master)}</span></span>
      <span class="rec-vsep"></span>
      <span class="rec-guitar"><b>Tu guitarra</b><${InputBar} cls="small" /></span></div>
    ${one ? html`<span class="rec-vsep"></span>` : null}
    <div class="rec-clist" ref=${list}>${chs.map(c => {
      const d = dim(c, anySolo), forced = !!c.forcedMuted;
      return html`<div class=${'rec-cchan' + (d ? ' dim' : '')} key=${c.id} title=${c.name}><div class="rec-cname">${c.name}</div>
        <div class="chan-btns"><${Toggle} text="M" on=${c.muted} label=${(c.muted ? 'Activar ' : 'Silenciar ') + c.name} onClick=${() => { if (!forced) setMix(c.id, { muted: !c.muted }); }} />
          <${Toggle} text="S" on=${c.solo} label=${'Solo ' + c.name} onClick=${() => { if (!forced) setMix(c.id, { solo: !c.solo }); }} /></div></div>`;
    })}</div></div>`;
}

export function RecordMixer({ expanded, onToggle }) {
  const s = snap.value;
  const chs = [...s.mix.channels, ...s.mix.takeChannels];
  const anySolo = !!s.mix.anySolo;
  return html`<section class=${'card mixer rec-mixer' + (expanded ? '' : ' compact')} aria-label="Mezclador">
    <div class="mixer-head"><h2>Mezclador</h2><span class="grow"></span>
      <span class="muted small">Salida: ${s.mix.outputName ? s.mix.outputName : '—'}</span>
      <button class="rec-expand" aria-label=${expanded ? 'Plegar el mezclador' : 'Expandir el mezclador'} aria-expanded=${expanded}
        onClick=${onToggle}>${expanded ? 'Plegar' : 'Expandir'}</button></div>
    ${expanded ? html`<${Expanded} chs=${chs} anySolo=${anySolo} master=${s.mix.masterGainDB} />`
      : html`<${Compact} chs=${chs} anySolo=${anySolo} master=${s.mix.masterGainDB} />`}</section>`;
}
