// («Ver toma» y hoja «Ajustar desfase»: CoreTakeSync, al final del fichero, con el audio en el núcleo (W2-V, W2-O).)
// Vídeo y audio de una toma en la página: el audio procesado (`processed.wav`, tiempo 0 = inicio de la toma) es el reloj;
// el `<video>` (sin sonido) lo sigue. Regla de TakePreview del Mac: «el fotograma con PTS `p` (tiempo del tema) se ve en
// `p − desfase`»; con el tiempo de toma `t`, el fotograma que toca es el de PTS `songStart + t + desfase`. En el tramo de un
// punch manda su vídeo con su propio desfase (el último manda).
//
// Origen del PTS: el `video.mov`/`.mp4` de una toma lleva PTS = tiempo del tema (VideoTakeWriter.swift:35-37; en Windows
// MediaFoundationWriter.swift:134-135 pone un tramo vacío delante con la lista de ediciones), así que el fotograma de PTS
// `p` está en `currentTime = p` y `VIDEO_PTS_ORIGIN_S = 0`. Pendiente de la VM: comprobar que WebView2 respeta ese tramo vacío
// (si normaliza el inicio a 0, poner aquí el PTS del primer fotograma).
import { mediaUrl } from '../state.js';

export const VIDEO_PTS_ORIGIN_S = 0;
/// Mensaje cuando el navegador no decodifica el vídeo (toma HEVC traída de un Mac).
export const HEVC_MESSAGE = 'Este equipo no puede reproducir el vídeo de esta toma (HEVC).';
export const VIDEO_ERROR_MESSAGE = 'No se pudo abrir el vídeo de la toma.';

/// MediaError -> texto: código 3 (decodificación) y 4 (formato no soportado) = códec que este equipo no decodifica.
export const videoErrorText = err => (err && (err.code === 3 || err.code === 4) ? HEVC_MESSAGE : VIDEO_ERROR_MESSAGE);

/// Fuente de imagen en el tiempo del tema `s`: el último punch con vídeo que lo contiene, o la base.
export function sourceAt(s, base, punches) {
  let src = base;
  for (const p of punches ?? []) if (p.videoPath && s >= p.start && s < p.end) src = { path: p.videoPath, offsetMs: p.videoOffsetMs ?? base?.offsetMs ?? 0 };
  return src;
}

/// Tamaño que ocupa una imagen `w`×`h` girada `deg` (múltiplos de 90, horario) dentro de una caja `bw`×`bh`, sin recortar.
export function fitRotated(bw, bh, w, h, deg) {
  const turned = ((deg % 180) + 180) % 180 === 90;
  const rw = turned ? h : w, rh = turned ? w : h;
  const k = Math.min(bw / rw, bh / rh);
  return { width: w * k, height: h * k };
}

// ---------------------------------------------------------------------------------------------------------------------
// W2-V «Ver toma» con el audio en el núcleo (contrato W2-V). Manda el núcleo: la toma y el backing suenan en
// `takeview.*` (StudyAudio) y el `<video>` sin sonido lo sigue. CoreClock y VideoFollower son puros (sin DOM): el test
// numérico de AppCore (TakeViewTests, JavaScriptCore) ejecuta este mismo fichero con un reloj de vídeo simulado.

/// Ventana del filtro de mínimos del retraso de entrega (s).
export const CLOCK = { SKEW_WINDOW_S: 5 };

/// Reloj del núcleo visto desde la página. Cada `takeview.position` trae `at` (reloj de host del núcleo, s); `now − at`
/// = desfase entre relojes + retraso de entrega (≥ 0). El mínimo en la ventana es el del mensaje que menos tardó: con él,
/// la posición en `now` es `seconds + rate · (now − skew − at)`.
export class CoreClock {
  constructor() { this.ev = null; this.samples = []; this.skew = 0; }
  push(ev, now) {
    this.samples.push([now, now - ev.at]);
    while (this.samples[0][0] < now - CLOCK.SKEW_WINDOW_S) this.samples.shift();
    let k = Infinity;
    for (const s of this.samples) k = Math.min(k, s[1]);
    this.skew = k;
    this.ev = ev;
  }
  get epoch() { return this.ev ? this.ev.epoch : -1; }
  /// Suena y el reloj avanza (antes de la primera muestra el núcleo manda `rate: 0`).
  get running() { return !!(this.ev && this.ev.playing && this.ev.rate > 0); }
  position(now) {
    const e = this.ev;
    if (!e) return 0;
    return e.seconds + (e.rate > 0 ? e.rate * Math.max(0, now - this.skew - e.at) : 0);
  }
}

/// Seguimiento del vídeo. Zona muerta: no se toca; deriva moderada: `playbackRate` proporcional (sin saltos de imagen);
/// deriva grande o búsqueda: salto con el adelanto que tardan los saltos (aprendido). Números en TakeViewTests.
export const FOLLOW = {
  DEADBAND_S: 0.003,     // deriva sin corregir
  HARD_S: 0.25,          // por encima, salto
  JUMP_SEEK_S: 0.05,     // tras una discontinuidad del núcleo (búsqueda), salto si la deriva pasa de esto
  GAIN_PER_S: 3,         // corrección de velocidad por segundo de deriva (constante de tiempo 0,33 s)
  MAX_RATE_DEV: 0.25,    // velocidad entre 0,75 y 1,25 (vídeo sin sonido: no se nota)
  RATE_STEP: 0.005,      // cambios de velocidad menores no se aplican
  LEAD_MAX_S: 0.3,       // adelanto máximo de un salto en marcha
  LEAD_EMA: 0.5,         // peso de la última medida del adelanto
};

export class VideoFollower {
  constructor() { this.lead = 0; this.leadKnown = false; this.recheck = false; this.seekAt = null; this.epoch = null; this.rate = 1; }
  /// `v`: {time, paused, seeking}; `target`: tiempo de vídeo que toca ahora; `running`: el núcleo suena y avanza.
  /// Devuelve las acciones a aplicar al `<video>`: {seek?, rate?, play?, pause?}.
  update(now, v, target, running, epoch) {
    const a = {};
    const jumped = epoch !== this.epoch || this.recheck;
    this.epoch = epoch;
    if (v.seeking) return a;
    this.recheck = false;
    const setRate = r => { if (r !== this.rate && (Math.abs(r - this.rate) >= FOLLOW.RATE_STEP || r === 1)) { a.rate = r; this.rate = r; } };
    const drift = v.time - target;
    if (!running) {
      if (!v.paused) a.pause = true;
      setRate(1);
      if (Math.abs(drift) > 0.001) { a.seek = target; this.seekAt = null; }
      return a;
    }
    if (v.paused) a.play = true;
    if (Math.abs(drift) > FOLLOW.HARD_S || (jumped && Math.abs(drift) > FOLLOW.JUMP_SEEK_S)) {
      a.seek = target + this.lead;
      this.seekAt = now;
      setRate(1);
      return a;
    }
    setRate(Math.abs(drift) <= FOLLOW.DEADBAND_S ? 1
      : Math.min(1 + FOLLOW.MAX_RATE_DEV, Math.max(1 - FOLLOW.MAX_RATE_DEV, 1 - drift * FOLLOW.GAIN_PER_S)));
    return a;
  }
  /// Fin de un salto pedido en marcha: lo que tardó es el adelanto del siguiente (la primera medida, entera). El fotograma
  /// siguiente mira dónde cayó: si falló por más de `JUMP_SEEK_S` (p. ej. el primer salto, sin adelanto aún), salta otra
  /// vez ya con el adelanto medido en vez de corregir por velocidad (W2-O: un cambio de desfase se ve en ≈0,3 s, no en 0,9).
  seeked(now) {
    if (this.seekAt == null) return;
    const d = now - this.seekAt;
    const lead = this.leadKnown ? this.lead * (1 - FOLLOW.LEAD_EMA) + d * FOLLOW.LEAD_EMA : d;
    this.lead = Math.min(FOLLOW.LEAD_MAX_S, Math.max(0, lead));
    this.leadKnown = true;
    this.seekAt = null;
    this.recheck = true;
  }
}

/// Tiempo de `<video>` que toca: PTS `songStart + t + desfase` (desfase en ms; en la hoja «Ajustar desfase», el de ese momento).
export const videoTarget = (songStart, t, offsetMs) => Math.max(0, songStart + t + (offsetMs ?? 0) / 1000 - VIDEO_PTS_ORIGIN_S);

/// Clave de discontinuidad del seguidor: la época del núcleo y, en la hoja de desfase, cuántas veces cambió el desfase.
/// Un cambio de desfase es un salto de la imagen, no del audio: el seguidor lo trata como una búsqueda (salto si pasa de
/// `FOLLOW.JUMP_SEEK_S`, si no, velocidad), y el núcleo ni se entera.
export const followEpoch = (coreEpoch, offsetEpoch) => `${coreEpoch}:${offsetEpoch}`;

/// Pegamento con el DOM: un fotograma por `requestAnimationFrame` mientras está montado.
export class CoreTakeSync {
  constructor(video, { songStart = 0, offsetMs = 0, basePath = null, punches = [], duration = 0, onVideoError = () => {}, onTick = () => {} }) {
    Object.assign(this, { video, songStart, offsetMs, basePath, punches, duration, onVideoError, onTick });
    this.offsetEpoch = 0;
    this.clock = new CoreClock();
    this.follower = new VideoFollower();
    this.current = null;
    this.loading = false;
    this.raf = 0;
    if (video) {
      video.muted = true;
      video.playsInline = true;
      video.addEventListener('error', () => this.onVideoError(videoErrorText(video.error)));
      video.addEventListener('loadedmetadata', () => { this.loading = false; });
      video.addEventListener('seeked', () => this.follower.seeked(performance.now() / 1000));
    }
    const step = () => { this.step(); this.raf = requestAnimationFrame(step); };
    this.raf = requestAnimationFrame(step);
  }
  get hasVideo() { return !!(this.basePath || this.punches.some(p => p.videoPath)); }
  /// `now`: hora de página (s) a la que llegó el evento.
  push(ev, now = performance.now() / 1000) { this.clock.push(ev, now); }
  /// Hoja «Ajustar desfase» (W2-O): desfase en vivo (ms). Solo mueve el objetivo del `<video>`; el audio del núcleo sigue.
  setOffset(ms) {
    if (ms === this.offsetMs) return;
    this.offsetMs = ms;
    this.offsetEpoch += 1;
  }
  time(now) { return Math.min(Math.max(this.clock.position(now), 0), this.duration || Infinity); }
  step() {
    const now = performance.now() / 1000;
    const t = this.time(now);
    this.onTick(t);
    if (!this.video || !this.hasVideo) return;
    const src = sourceAt(this.songStart + t, this.basePath ? { path: this.basePath, offsetMs: this.offsetMs } : null,
      this.punches.map(p => ({ ...p, videoOffsetMs: p.videoOffsetMs ?? this.offsetMs })));
    if (!src) { if (this.current) { this.video.removeAttribute('src'); this.current = null; } return; }
    if (this.current !== src.path) {
      this.current = src.path;
      this.loading = true;
      this.video.src = mediaUrl(src.path);
      this.video.load();
      return;
    }
    const target = videoTarget(this.songStart, t, src.offsetMs);
    const v = { time: this.video.currentTime, paused: this.video.paused, seeking: this.loading || this.video.seeking || this.video.readyState < 1 };
    const a = this.follower.update(now, v, target, this.clock.running, followEpoch(this.clock.epoch, this.offsetEpoch));
    if (a.rate != null) this.video.playbackRate = a.rate;
    if (a.seek != null) this.video.currentTime = a.seek;
    if (a.play) this.video.play().catch(() => {});
    if (a.pause) this.video.pause();
  }
  destroy() {
    cancelAnimationFrame(this.raf);
    if (!this.video) return;
    this.video.pause();
    this.video.removeAttribute('src');
    this.video.load();
  }
}
