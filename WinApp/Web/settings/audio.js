import { useEffect, useRef, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { Group, InfoRow, Select, fail } from './common.js';
import { CalibrationSheet } from './calibration-sheet.js';
import { refreshDeviceCard } from './device-card.js';

/// Medidas de InputMeters del Mac: barras de 8 x 28, 4 de separación, radio 2.
const METER_W = 8, METER_H = 28, METER_GAP = 4, METER_RADIUS = 2;

const sameChannels = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

/// Pestaña «Audio» del Mac (AudioSettingsView): Dispositivo, Canales y Calibración. Los vúmetros y la sesión sin guitarra
/// asignada solo corren con el bloque a la vista (`audio.setMeters`).
export function AudioSettings() {
  const [devices, setDevices] = useState(null);
  const [s, setS] = useState(null);
  const [levels, setLevels] = useState(null);
  const [sheet, setSheet] = useState(false);
  const metersRef = useRef(null);

  useEffect(() => {
    let alive = true;
    const reload = () => call('audio.settings').then(x => alive && setS(x)).catch(e => fail('No se pudieron leer los ajustes de audio', e));
    call('audio.setMeters', { visible: true }).catch(() => {}).then(() => {
      call('audio.devices').then(d => alive && setDevices(d)).catch(e => fail('No se pudieron leer los dispositivos', e));
      reload();
    });
    const offL = on('audio.levels', p => { const l = p?.levels ?? []; metersRef.current?.(l); setLevels(prev => (prev?.length === l.length ? prev : (l.length ? Array(l.length).fill(0) : null))); });
    const offD = on('audio.devicesChanged', d => { setDevices(d); reload(); });
    const offS = on('audio.state', () => reload());
    return () => { alive = false; offL(); offD(); offS(); call('audio.setMeters', { visible: false }).catch(() => {}); };
  }, []);

  if (!devices || !s) return null;
  const update = async change => {
    try { setS(await call('audio.setSettings', change)); refreshDeviceCard(); } catch (e) { fail('No se pudo guardar', e); }
  };
  return html`<div class="sstack">
    <${DeviceGroup} devices=${devices} s=${s} update=${update} />
    <${ChannelsGroup} s=${s} update=${update} levels=${levels} metersRef=${metersRef} />
    <${CalibrationGroup} s=${s} onCalibrate=${() => setSheet(true)} />
    ${sheet ? html`<${CalibrationSheet} instructions=${s.calibrateInstructions} block=${s.calibrateBlock}
      onClose=${() => { setSheet(false); call('audio.settings').then(setS).catch(() => {}); }} />` : null}
  </div>`;
}

/// Dispositivos conectados; el elegido que ya no está se mantiene como «desconectado».
function deviceOptions(list, chosen, none) {
  const opts = [{ value: '', label: none }, ...list.map(d => ({ value: d.uid, label: d.label }))];
  if (chosen && !list.some(d => d.uid === chosen)) opts.push({ value: chosen, label: 'Dispositivo elegido · desconectado' });
  return opts;
}

function DeviceGroup({ devices, s, update }) {
  const m = s.rateMismatch;
  return html`<${Group} title="Dispositivo" note="Por dónde suena el backing y por dónde entra tu guitarra.">
    <${InfoRow} label="Dispositivo de salida"><${Select} label="Dispositivo de salida" value=${s.outputDeviceUID ?? ''}
      options=${deviceOptions(devices.outputs, s.outputDeviceUID, 'Salida del sistema')}
      onChange=${v => update({ outputDeviceUID: v === '' ? null : v })} /><//>
    <${InfoRow} label="Dispositivo de entrada"><${Select} label="Dispositivo de entrada" value=${s.inputDeviceUID ?? ''}
      options=${deviceOptions(devices.inputs, s.inputDeviceUID, 'Ninguna')}
      onChange=${v => update({ inputDeviceUID: v === '' ? null : v })} /><//>
    <${InfoRow} label="Frecuencia de trabajo"><div class="rate-seg" role="radiogroup" aria-label="Frecuencia de trabajo">
      ${s.allowedSampleRates.map(r => html`<button key=${r.rate} role="radio" aria-checked=${r.rate === s.workingSampleRate ? 'true' : 'false'}
        class=${r.rate === s.workingSampleRate ? 'on' : ''} onClick=${() => r.rate !== s.workingSampleRate && update({ workingSampleRate: r.rate })}>${r.label}</button>`)}</div><//>
    ${m ? html`<div class="rate-warn"><p class="rate-warn-main">${m.message}</p><p class="rate-warn-hint">${m.hint}</p>
      ${m.canUseDeviceRate ? html`<button class="btn secondary" onClick=${() => update({ workingSampleRate: m.deviceRate })}>${m.useLabel}</button>` : null}</div>` : null}
  <//>`;
}

function ChannelsGroup({ s, update, levels, metersRef }) {
  const backing = s.backingChoices.map(c => ({ value: `${c.left}-${c.right}`, label: c.label }));
  const guitar = s.guitarChoices.map(c => ({ value: JSON.stringify(c.channels), label: c.label }));
  return html`<${Group} title="Canales" note="Qué entra y qué sale por cada canal del dispositivo.">
    <${InfoRow} label="Salida del backing"><${Select} label="Salida del backing" value=${`${s.backingOut.left}-${s.backingOut.right}`} options=${backing}
      onChange=${v => { const [left, right] = v.split('-').map(Number); update({ backingOut: { left, right } }); }} /><//>
    <${InfoRow} label="Entrada de guitarra">
      ${levels ? html`<${InputMeters} count=${levels.length} metersRef=${metersRef} />` : null}
      <${Select} label="Entrada de guitarra" value=${JSON.stringify(s.guitarIn ?? null)} options=${guitar} disabled=${s.inputDeviceUID == null}
        onChange=${v => { const g = JSON.parse(v); if (!sameChannels(g, s.guitarIn)) update({ guitarIn: g }); }} /><//>
  <//>`;
}

/// InputMeters del Mac en canvas: nivel 0...1 por canal sobre el fondo de campo, relleno en verde.
function InputMeters({ count, metersRef }) {
  const canvas = useRef(null);
  const width = count * METER_W + (count - 1) * METER_GAP;
  useEffect(() => {
    const el = canvas.current, ratio = window.devicePixelRatio || 1;
    el.width = Math.round(width * ratio); el.height = Math.round(METER_H * ratio);
    const ctx = el.getContext('2d');
    const css = getComputedStyle(document.documentElement);
    const field = css.getPropertyValue('--field').trim(), ok = css.getPropertyValue('--ok').trim();
    const rect = (x, y, w, h, c) => { ctx.fillStyle = c; ctx.beginPath(); ctx.roundRect(x * ratio, y * ratio, w * ratio, h * ratio, METER_RADIUS * ratio); ctx.fill(); };
    const draw = levels => {
      ctx.clearRect(0, 0, el.width, el.height);
      levels.slice(0, count).forEach((l, i) => {
        const x = i * (METER_W + METER_GAP), h = METER_H * Math.min(Math.max(l, 0), 1);
        rect(x, 0, METER_W, METER_H, field);
        if (h > 0) rect(x, METER_H - h, METER_W, h, ok);
      });
    };
    draw(Array(count).fill(0));
    metersRef.current = draw;
    return () => { metersRef.current = null; };
  }, [count]);
  return html`<canvas ref=${canvas} class="meters" aria-label="Nivel de entrada" style=${`width:${width}px;height:${METER_H}px`}></canvas>`;
}

function CalibrationGroup({ s, onCalibrate }) {
  const c = s.calibration, block = s.calibrateBlock;
  return html`<${Group} title="Calibración" note="Un pulso de prueba mide el retardo de ida y vuelta del dispositivo.">
    <${InfoRow} label="Latencia"><b class=${'val ' + (c.calibrated ? 'ok' : 'accent')}>${c.label}</b><//>
    <div class="srow-btns"><button class="btn secondary" disabled=${!!block} onClick=${onCalibrate}>Calibrar latencia</button></div>
    ${block ? html`<p class="snote">${block}</p>` : null}
  <//>`;
}
