// Simulador de audio.* para `?mock=1` (sin núcleo). Forma de Temp/win/step8-contract.md, «W2-C audio.*».
// Variantes con `?audio=`: mismatch (dispositivo a otra frecuencia) | disconnected (salida elegida ausente) | noguitar (sin guitarra: calibrar bloqueado) | onerate (una sola frecuencia).
// Resultado de la calibración con `?cal=`: success (por defecto) | noSignal | saturated | unstable | error.
import { setMockHandler, mockEmit } from '../bridge.js';

const q = new URLSearchParams(location.search);
const variant = q.get('audio'), calVariant = q.get('cal') ?? 'success';
const wait = ms => new Promise(r => setTimeout(r, ms));
const clone = o => JSON.parse(JSON.stringify(o));
const dev = (uid, name, channels) => ({ uid, name, channels, label: `${name} · ${channels} can.`, connected: true, rate: 48000 });
const IN = [dev('sim-in', 'Entrada simulada', 2), dev('usb-in', 'Interfaz USB (HeadRush)', 4)];
const OUT = [dev('sim-out', 'Salida simulada', 2), dev('usb-out', 'Interfaz USB (HeadRush)', 4)];

const prof = { outputDeviceUID: variant === 'disconnected' ? 'gone-out' : 'sim-out', inputDeviceUID: 'sim-in',
  backingOut: { left: 1, right: 2 }, guitarIn: variant === 'noguitar' ? null : [1, 2], workingSampleRate: 48000 };
const rates = variant === 'onerate' ? [{ rate: 48000, label: '48 kHz' }] : [{ rate: 44100, label: '44,1 kHz' }, { rate: 48000, label: '48 kHz' }];
let calibration = { calibrated: false, label: 'Sin calibrar' };

const devices = () => ({ inputs: clone(IN), outputs: variant === 'disconnected' ? clone(OUT).slice(0, 0) : clone(OUT), systemDefault: clone(OUT[0]) });
const chan = uid => ([...IN, ...OUT].find(d => d.uid === uid)?.channels ?? 2);
const block = () => variant === 'noguitar' || prof.guitarIn == null ? 'Asigna una entrada de guitarra para calibrar.'
  : variant === 'mismatch' ? 'Calibrar queda bloqueado: el dispositivo no está a la frecuencia de trabajo.' : null;

function settings() {
  const outCh = chan(prof.outputDeviceUID), inCh = chan(prof.inputDeviceUID);
  const backingChoices = [];
  for (let l = 1; l < Math.max(outCh, 2); l += 2) backingChoices.push({ label: `Salidas ${l} y ${l + 1} · estéreo`, left: l, right: l + 1 });
  const guitarChoices = [{ label: 'Sin asignar', channels: null }];
  for (let c = 1; c <= inCh; c++) guitarChoices.push({ label: `Entrada ${c}`, channels: [c] });
  for (let c = 1; c < inCh; c += 2) guitarChoices.push({ label: `Entradas ${c} y ${c + 1}`, channels: [c, c + 1] });
  return { ...clone(prof), allowedSampleRates: rates, backingChoices, guitarChoices,
    rateMismatch: variant === 'mismatch' ? { deviceRate: 44100, workingRate: 48000, canUseDeviceRate: true, useLabel: 'Usar 44,1 kHz como frecuencia de trabajo',
      message: 'El dispositivo está a 44,1 kHz y la frecuencia de trabajo es 48 kHz', hint: 'Grabar y calibrar quedan bloqueados; el backing suena igual.' } : null,
    calibration: clone(calibration), calibrateBlock: block(),
    calibrateInstructions: ['Conecta con un cable una salida del dispositivo a su entrada de guitarra.',
      'Con una pedalera, carga un rig vacío y baja el volumen de salida: el bucle realimenta (entrada, rig, salida, cable, entrada).',
      'La prueba son 10 pitidos agudos en unos 5 segundos. Mide el retardo de ida y vuelta, que es el desfase que tendrá una toma respecto al backing que se oye.'] };
}

const state = () => ({ sessionOpen: true, sessionError: null, interruptionNote: null, hostError: null, hosting: false, metersVisible: meters != null,
  recording: false, calibrationRunning: false, calibrationValid: calibration.calibrated, calibrateBlock: block(), recordingNotices: [],
  mismatchedRate: variant === 'mismatch' ? 44100 : null, workingSampleRate: prof.workingSampleRate });

let meters = null, t0 = 0;
function setMeters(visible) {
  clearInterval(meters); meters = null;
  if (!visible) { mockEmit('audio.levels', { levels: [], rmsDB: [], peakDB: [] }); return; }
  t0 = performance.now();
  const n = () => (prof.guitarIn ?? (prof.inputDeviceUID ? [1, 2] : [])).length || (prof.inputDeviceUID ? 2 : 0);
  meters = setInterval(() => {
    const t = (performance.now() - t0) / 1000, k = n();
    const levels = Array.from({ length: k }, (_, i) => Math.max(0, Math.min(1, 0.45 + 0.35 * Math.sin(t * 3 + i * 1.7) + 0.1 * Math.sin(t * 11))));
    mockEmit('audio.levels', { levels, rmsDB: levels.map(l => 20 * Math.log10(l || 1e-4)), peakDB: levels.map(l => 20 * Math.log10(l || 1e-4)) });
  }, 33);
}

const f2 = (v, d) => v.toLocaleString('es-ES', { minimumFractionDigits: d, maximumFractionDigits: d });
const OUTCOMES = {
  success: () => ({ phase: 'finished', outcome: 'success', success: { latencyMS: 2.05, latencySamples: 98.4, spreadMS: 0.021, spreadSamples: 1, rigDelayMS: null, correctedTakes: 0,
    rows: [{ label: 'Latencia', value: `${f2(2.05, 2)} ms · ${f2(98.4, 1)} muestras` }, { label: 'Dispersión', value: `${f2(0.021, 3)} ms · ${f2(1, 1)} muestras` },
      { label: 'Retardo del rig', value: 'sin canal de referencia: la latencia calibrada vale tal cual' }] } }),
  noSignal: () => ({ phase: 'finished', outcome: 'failure', failure: { reason: 'noSignal', spreadMS: 0, title: 'No llegó la señal de prueba',
    hint: 'Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite.' } }),
  saturated: () => ({ phase: 'finished', outcome: 'failure', failure: { reason: 'saturated', spreadMS: 0, title: 'La señal llegó saturada',
    hint: 'Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite.' } }),
  unstable: () => ({ phase: 'finished', outcome: 'failure', failure: { reason: 'unstable', spreadMS: 1.37, title: 'Las medidas no coinciden entre sí (dispersión de 1,37 ms)',
    hint: 'Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite.' } }),
  error: () => ({ phase: 'finished', outcome: 'error', error: 'La entrada y la salida elegidas no son del mismo dispositivo.' }),
};

setMockHandler((method, p) => {
  switch (method) {
    case 'audio.devices': return devices();
    case 'audio.settings': return settings();
    case 'audio.setSettings': {
      if ('outputDeviceUID' in p) { prof.outputDeviceUID = p.outputDeviceUID; prof.backingOut = { left: 1, right: 2 }; }
      if ('inputDeviceUID' in p) { prof.inputDeviceUID = p.inputDeviceUID; prof.guitarIn = null; }
      if (p.backingOut) prof.backingOut = p.backingOut;
      if ('guitarIn' in p) prof.guitarIn = p.guitarIn;
      if (p.workingSampleRate) { prof.workingSampleRate = p.workingSampleRate; if (variant === 'mismatch') calibration = { calibrated: false, label: 'Sin calibrar' }; }
      return settings();
    }
    case 'audio.state': return state();
    case 'audio.setMeters': setMeters(p.visible); return state();
    case 'audio.calibrate': return (async () => {
      for (let f = 0; f < 1; f += 0.1) { mockEmit('audio.calibration', { phase: 'running', progress: f }); await wait(500); }
      const r = OUTCOMES[calVariant]();
      if (r.outcome === 'success') calibration = { calibrated: true, label: 'Calibrada · 2,05 ms · 21 nov 2026' };
      mockEmit('audio.calibration', r);
      return r;
    })();
    case 'audio.cancelCalibration': case 'audio.dismissCalibration': return { phase: 'idle' };
  }
  return undefined;
});
