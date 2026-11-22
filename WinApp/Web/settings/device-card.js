import { useEffect, useState } from 'preact/hooks';
import { html } from '../html.js';
import { call, on, transportName } from '../bridge.js';

if (transportName() === 'mock') await import('../mock/audio.js');   // simulador de audio.* (solo con --mock)

const listeners = new Set();
/// Lo llama el bloque de Audio tras guardar el dispositivo de salida, para que la tarjeta de la barra lateral se relea.
export const refreshDeviceCard = () => listeners.forEach(f => f());

/// Indicador del dispositivo de salida de la barra lateral (AudioDeviceMonitor del Mac): «Salida del sistema · Por defecto»
/// sin dispositivo elegido; con uno, su nombre y «Conectado» / «Sin conectar» (punto verde solo si hay salida).
export function DeviceCard() {
  const [info, setInfo] = useState({ title: 'Salida del sistema', subtitle: 'Por defecto', ok: true });
  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const [s, d] = await Promise.all([call('audio.settings'), call('audio.devices')]);
        if (!alive) return;
        const uid = s.outputDeviceUID;
        if (!uid) { setInfo({ title: 'Salida del sistema', subtitle: 'Por defecto', ok: true }); return; }
        const dev = d.outputs.find(x => x.uid === uid);
        const connected = !!dev && dev.connected !== false;
        setInfo({ title: dev?.name ?? 'Dispositivo elegido', subtitle: connected ? 'Conectado' : 'Sin conectar', ok: connected });
      } catch { /* sin núcleo de audio: se queda el valor por defecto */ }
    };
    load();
    listeners.add(load);
    const off = on('audio.devicesChanged', load);
    return () => { alive = false; listeners.delete(load); off(); };
  }, []);
  return html`<div class="device-card"><div class="row"><span class=${'dot' + (info.ok ? ' ok' : '')} aria-hidden="true"></span><span>${info.title}</span></div>
    <div class="sub">${info.subtitle}</div></div>`;
}
