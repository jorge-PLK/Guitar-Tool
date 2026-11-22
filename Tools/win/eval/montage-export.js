// Exportacion de un Montaje de extremo a extremo (app de Windows, WebView2). Cuerpo de funcion async con (bridge, log).
// Modo: `globalThis.MONTAGE_MODE = 'full' | 'cancel'` lo antepone el lanzador; sin eso, 'full'.
//   full:   abrir Montaje por la interfaz -> esperar al analisis de encuadre -> «Exportar vídeo» -> esperar -> medir el fichero
//           (contenedor, codecs, resolucion, fps, duraciones, fotogramas, RMS del audio), tiempos, restos y vista previa viva.
//   cancel: exportar y pulsar «Cancelar exportación» (A: mezclando, con «WAV de cada pista»; B: codificando, a mitad) -> sin fichero
//           final ni parciales y app viva -> C: exportar de nuevo hasta el final (un fichero abierto en NTFS no se borra ni se renombra).
// `globalThis.MONTAGE_NOFETCH = true`: solo la prueba en seco del Mac (tf-webdev no deja leer media por fetch): el fichero no se mide.
// `globalThis.MONTAGE_TITLE = 'texto'`: fuerza el tema (si no, el de plan mas cercano a PLAN_TARGET_S entre los que tienen video).
// Linea: `OK|FAIL|SKIP|INFO <nombre> <dato>` (el anfitrion antepone `eval| `); ultima: `DONE montage <ok>/<total> (skip <n>)`.
// Solo toca la COPIA de proyectos que trae el lanzador (--projects-folder). La copia se tira.
const MODE = globalThis.MONTAGE_MODE ?? 'full';
const NOFETCH = !!globalThis.MONTAGE_NOFETCH;
const PLAN_TARGET_S = 12;                 // plan deseado 10-15 s; Montaje NO tiene control de rango: el plan sale de las tomas
const PLAN_MAX_PROBE = 8;                 // temas con video que se abren (montage.open) para conocer su plan
const PLAN_LONG_S = 90;                   // un plan mas largo se exporta igual (no hay forma de recortarlo) pero con tope mayor y aviso
const PLAN_SHORT_S = 5;                   // plan mas corto: la velocidad (s/s) y la cancelacion a mitad no son fiables
const MIX_SHARE = 0.15;                   // MontageController.mixProgressShare: el progreso 0-0,15 es la mezcla, el resto la codificacion
const ENC_CANCEL_FRACTION = 0.5;          // B: se cancela cuando la codificacion va por la mitad
const STAGE_ENCODE = /Codificando/;
const PREP_MAX_MS = 6 * 60000;            // vista previa + analisis de encuadre (pose en CPU) antes de poder exportar
const EXPORT_MAX_MS = { base: 15 * 60000, perPlanS: 60000 };   // tope = base + 60 s por segundo de plan
const POLL_MS = 500, HEARTBEAT_MS = 30000, UI_SAMPLE_MS = 1000;
const START_QUEUE_MAX_MS = 25 * 60000;
const DUR_TOL_FRAMES = 1;                 // duracion de video y audio = plan, con 1 fotograma de tolerancia
const FRAME_COUNT_TOL = 1;                // fotogramas = round(duracion x fps) +- 1
const AAC_PRIMING_S = 2112 / 48000;       // el codificador AAC de MF antepone 2112 muestras (step7-2-state.md): el audio DECODIFICADO puede durar eso de mas
const AUDIO_RMS_MIN_DB = -55;             // la mezcla normalizada a -14 LUFS no es silencio
const AUDIO_BLOCK_S = 0.1, AUDIO_BLOCK_SILENCE_DB = -70;
const MAX_FULL_FETCH = 200 * 1024 * 1024; // fetch entero del mp4 (para leer cajas y decodificar el audio)
const AFTER_FRAME_MS = 10000;             // espera de un fotograma de la vista previa tras exportar

const sleep = ms => new Promise(r => setTimeout(r, ms));
const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
const txt = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
const T0 = Date.now();
let ok = 0, bad = 0, skip = 0;
const OK = (n, d = '') => { ok++; log(`OK ${n} ${d}`.trimEnd()); return true; };
const FAIL = (n, d = '') => { bad++; log(`FAIL ${n} ${d}`.trimEnd()); return false; };
const SKIP = (n, d = '') => { skip++; log(`SKIP ${n} ${d}`.trimEnd()); return false; };
const INFO = (n, d = '') => log(`INFO ${n} ${d}`.trimEnd());
const check = (n, cond, d = '') => (cond ? OK(n, d) : FAIL(n, d));
const err = e => `${e?.code ? e.code + ': ' : ''}${e?.message ?? e}`;
const f1 = x => (Number.isFinite(x) ? x.toFixed(1) : String(x));
const f3 = x => (Number.isFinite(x) ? x.toFixed(3) : String(x));
const db = x => (x > 0 ? 20 * Math.log10(x) : -Infinity);
const fdb = x => (Number.isFinite(x) ? x.toFixed(1) : '-inf');
const call = (m, p, t = 60000) => bridge.call(m, p ?? {}, { timeout: t });
const btn = re => $$('button').find(b => re.test(txt(b)));
async function until(fn, ms = 5000, step = 100) {
  const t = Date.now();
  for (;;) {
    let v = null; try { v = await fn(); } catch { v = null; }
    if (v) return v;
    if (Date.now() - t > ms) return null;
    await sleep(step);
  }
}
const offs = [];
function collect(ev, fn) { const arr = []; const off = bridge.on(ev, p => { const e = { t: performance.now(), p }; arr.push(e); fn?.(e); }); offs.push(off); return { arr, stop: () => { try { off(); } catch { /* ya */ } } }; }

// ---------------- MP4/MOV: cajas (equivalente a ffprobe; sin dependencias) ----------------
//<<MP4
function parseMp4(buf) {
  const dv = new DataView(buf), u8 = new Uint8Array(buf);
  const t4 = o => String.fromCharCode(u8[o], u8[o + 1], u8[o + 2], u8[o + 3]);
  const u64 = o => dv.getUint32(o) * 4294967296 + dv.getUint32(o + 4);
  const boxes = (a, b) => {
    const out = []; let p = a;
    while (p + 8 <= b) {
      let size = dv.getUint32(p); const type = t4(p + 4); let hdr = 8;
      if (size === 1) { size = u64(p + 8); hdr = 16; } else if (size === 0) size = b - p;
      if (size < hdr || p + size > b) { out.push({ type, bad: true, start: p, end: Math.min(b, p + Math.max(size, hdr)), body: p + hdr }); break; }
      out.push({ type, start: p, end: p + size, body: p + hdr }); p += size;
    }
    return out;
  };
  const find = (list, t) => list.find(x => x.type === t);
  const kids = x => boxes(x.body, x.end);
  const res = { size: buf.byteLength, brand: null, tracks: [], movie: null, topLevel: [] };
  const top = boxes(0, buf.byteLength);
  res.topLevel = top.map(x => `${x.type}${x.bad ? '(truncada)' : ''}`);
  const ftyp = find(top, 'ftyp'); if (ftyp) res.brand = t4(ftyp.body);
  const moov = find(top, 'moov'); if (!moov) { res.error = 'sin caja moov'; return res; }
  const mk = kids(moov);
  const mvhd = find(mk, 'mvhd');
  if (mvhd) { const v = u8[mvhd.body]; const o = mvhd.body + 4 + (v === 1 ? 16 : 8); res.movie = { timescale: dv.getUint32(o), duration: v === 1 ? u64(o + 4) : dv.getUint32(o + 4) }; }
  for (const trak of mk.filter(x => x.type === 'trak')) {
    const tk = kids(trak), tr = { };
    const tkhd = find(tk, 'tkhd');
    if (tkhd) {
      const v = u8[tkhd.body], o = tkhd.body + 4 + (v === 1 ? 16 : 8);
      tr.id = dv.getUint32(o); tr.tkhdDuration = v === 1 ? u64(o + 8) : dv.getUint32(o + 8);
      const w = tkhd.body + (v === 1 ? 88 : 76); tr.tkhdW = dv.getUint32(w) / 65536; tr.tkhdH = dv.getUint32(w + 4) / 65536;
    }
    const edts = find(tk, 'edts');
    if (edts) {
      const elst = find(kids(edts), 'elst');
      if (elst) {
        const v = u8[elst.body], n = dv.getUint32(elst.body + 4); let o = elst.body + 8; tr.edits = [];
        for (let i = 0; i < n; i++) {
          if (v === 1) { tr.edits.push({ dur: u64(o), start: Number(dv.getBigInt64(o + 8)) }); o += 20; }
          else { tr.edits.push({ dur: dv.getUint32(o), start: dv.getInt32(o + 4) }); o += 12; }
        }
      }
    }
    const mdia = find(tk, 'mdia'); if (!mdia) { res.tracks.push(tr); continue; }
    const mk2 = kids(mdia);
    const mdhd = find(mk2, 'mdhd');
    if (mdhd) { const v = u8[mdhd.body], o = mdhd.body + 4 + (v === 1 ? 16 : 8); tr.timescale = dv.getUint32(o); tr.mdhdDuration = v === 1 ? u64(o + 4) : dv.getUint32(o + 4); }
    const hdlr = find(mk2, 'hdlr'); if (hdlr) tr.handler = t4(hdlr.body + 8);
    const minf = find(mk2, 'minf'), stbl = minf && find(kids(minf), 'stbl'); if (!stbl) { res.tracks.push(tr); continue; }
    const sk = kids(stbl);
    const stsd = find(sk, 'stsd');
    if (stsd) {
      const e = boxes(stsd.body + 8, stsd.end)[0];
      if (e) {
        tr.codec = e.type;
        if (tr.handler === 'vide') {
          tr.width = dv.getUint16(e.body + 24); tr.height = dv.getUint16(e.body + 26);
          const cfg = boxes(e.body + 78, e.end).find(x => x.type === 'avcC' || x.type === 'hvcC');
          if (cfg) { tr.config = cfg.type; if (cfg.type === 'avcC') tr.profile = u8[cfg.body + 1]; tr.level = u8[cfg.body + 3]; }
        } else if (tr.handler === 'soun') {
          tr.channels = dv.getUint16(e.body + 16); tr.sampleRate = dv.getUint32(e.body + 24) / 65536;
        }
      }
    }
    const stts = find(sk, 'stts');
    if (stts) {
      const n = dv.getUint32(stts.body + 4); let o = stts.body + 8, count = 0, ticks = 0; const hist = new Map();
      for (let i = 0; i < n; i++) { const c = dv.getUint32(o), d = dv.getUint32(o + 4); count += c; ticks += c * d; hist.set(d, (hist.get(d) ?? 0) + c); o += 8; }
      tr.sttsCount = count; tr.sttsTicks = ticks;
      tr.deltaMode = [...hist.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
    }
    const stsz = find(sk, 'stsz'); if (stsz) tr.stszCount = dv.getUint32(stsz.body + 8);
    res.tracks.push(tr);
  }
  const msec = res.movie?.timescale || 1;
  for (const tr of res.tracks) {
    tr.mediaSeconds = tr.timescale ? tr.mdhdDuration / tr.timescale : NaN;
    tr.sampleSeconds = tr.timescale ? (tr.sttsTicks ?? NaN) / tr.timescale : NaN;
    tr.presentedSeconds = tr.edits?.length ? tr.edits.reduce((s, e) => s + e.dur, 0) / msec : (tr.tkhdDuration ?? NaN) / msec;
    tr.fps = tr.handler === 'vide' && tr.deltaMode ? tr.timescale / tr.deltaMode : NaN;
  }
  res.video = res.tracks.find(t => t.handler === 'vide'); res.audio = res.tracks.find(t => t.handler === 'soun');
  return res;
}
//>>MP4

// ---------------- Fichero por mediaBase ----------------
let mediaBase = '';
const mediaUrl = rel => (mediaBase.endsWith('/') ? mediaBase : mediaBase + '/') + rel.split('/').map(encodeURIComponent).join('/');
// {exists, bytes, buf?} ; «no existe» solo con 404 (un fallo de fetch no prueba nada: why).
async function getFile(rel, keep = false) {
  let r;
  try { r = await fetch(mediaUrl(rel), { cache: 'no-store' }); } catch (e) { return { exists: false, unknown: true, why: String(e) }; }
  if (r.status === 404) return { exists: false, unknown: false, why: 'HTTP 404' };
  if (!r.ok) return { exists: false, unknown: true, why: `HTTP ${r.status}` };
  const len = +(r.headers.get('Content-Length') ?? 0);
  if (!keep || (len && len > MAX_FULL_FETCH)) { const out = { exists: true, bytes: len || NaN, big: len > MAX_FULL_FETCH }; if (!keep) { try { r.body?.cancel(); } catch { /* ya */ } } return out; }
  const buf = await r.arrayBuffer();
  return { exists: true, bytes: buf.byteLength, buf };
}
// Ausente = 404; si no se pudo comprobar, SKIP.
async function absentFile(name, rel, what) {
  if (NOFETCH) return SKIP(name, `${what}: fetch de media desactivado (prueba en seco)`);
  const f = await getFile(rel);
  if (f.unknown) return SKIP(name, `${what}: no se pudo comprobar (${f.why})`);
  return check(name, !f.exists, `${what}: ${f.exists ? `EXISTE (${f.bytes} B): ${rel}` : 'no existe (404)'}`);
}

// ---------------- Estado ----------------
const ctx = { proj: null, folder: null, id: null, plan: null, platform: '?' };
const snap = () => call('montage.snapshot', {}, 60000);
const exportBtn = () => btn(/^Exportar vídeo$/);
const cancelBtn = () => btn(/^Cancelar exportación$/);
const domExport = () => txt($('.mt-export'));
const finalName = (s, container) => `${ctx.folder}-${s.layout}.${container}`;   // Files.montageVideoURL (sin caracteres a sanear en estos temas)
const videoRel = n => `${ctx.folder}/video/${n}`;

// Sale a la biblioteca si hace falta, abre Montaje con el boton de la barra lateral y el tema en el selector.
async function openMontageUI(proj) {
  if (!$('.screen.montage .mt-head')) {
    const nav = $$('.nav-item, nav button, button').find(b => txt(b) === 'Montaje');
    if (nav) nav.click(); else INFO('ui.nav', 'sin boton «Montaje» en la barra lateral');
  }
  const chooser = await until(() => $('.mt-chooser') ?? $('.screen.montage .mt-head'), 15000, 100);
  if ($('.mt-chooser')) {
    const item = $$('.chooser-item').find(b => txt(b).includes(proj.title));
    if (item) item.click(); else INFO('ui.selector', `tema «${proj.title}» no esta en el selector: ${$$('.chooser-item').map(txt).join(' | ')}`);
  }
  let ready = await until(() => $('.screen.montage .mt-head'), 30000, 200);
  let s = ready ? await until(async () => { const x = await snap(); return x.projectId === proj.id ? x : null; }, 15000, 300) : null;
  if (!s) {   // alternativa: el mismo modulo de estado que usa la pagina
    try {
      const m = await import(new URL('montage/store.js', document.baseURI).href);
      m.target.value = proj.id; INFO('ui.alternativa', 'target de montage/store.js fijado a mano');
      ready = await until(() => $('.screen.montage .mt-head'), 30000, 200);
      s = ready ? await until(async () => { const x = await snap(); return x.projectId === proj.id ? x : null; }, 15000, 300) : null;
    } catch (e) { INFO('ui.alternativa', `fallo: ${err(e)}`); }
  }
  return { viaUI: !!chooser, snapshot: s };
}

// Espera a vista previa lista + sin analisis de encuadre en curso + «Exportar vídeo» habilitado.
async function waitReady() {
  const t = Date.now(); let beat = t, last = null;
  for (;;) {
    last = await snap();
    const b = exportBtn();
    if (last.preview.phase === 'ready' && last.preview.audio.phase !== 'preparing' && last.export.canExport && b && !b.disabled) return { ok: true, s: last, ms: Date.now() - t };
    if (last.preview.phase === 'error') return { ok: false, s: last, ms: Date.now() - t, why: `vista previa en error: ${last.preview.error}` };
    if (Date.now() - beat >= HEARTBEAT_MS) { beat = Date.now(); INFO('preparar.latido', `${Math.round((Date.now() - t) / 1000)} s preview=${last.preview.phase}/${last.preview.audio.phase} analizando=${last.isAnalyzing} canExport=${last.export.canExport}`); }
    if (Date.now() - t > PREP_MAX_MS) return { ok: false, s: last, ms: Date.now() - t, why: `tope de ${PREP_MAX_MS / 1000} s: preview=${last.preview.phase}/${last.preview.audio.phase} analizando=${last.isAnalyzing} canExport=${last.export.canExport}; encuadre ${last.framing.map(f => `${f.status} ${(f.progress * 100).toFixed(0)}%`).join(',')}` };
    await sleep(POLL_MS);
  }
}

// Lanza una exportacion por la interfaz y la sigue. opts.cancelWhen(ev) -> true pide cancelar (se pulsa el boton en el propio evento).
// Devuelve {end:'done'|'failed'|'cancelled'|'timeout', ms, events, ui, result, message, cancelClick, cancelAt}.
async function runExport(label, planS, { cancelWhen = null } = {}) {
  const evs = [];
  const out = { end: null, ms: 0, events: evs, ui: [], result: null, message: null, cancelClick: null, cancelAt: null };
  let cancelled = false, tStart = 0;
  const sub = collect('montage.export', e => {
    const p = e.p; evs.push({ ms: Math.round(e.t - tStart), phase: p.phase, stage: p.stage, progress: p.progress });
    if (cancelWhen && !cancelled && p.phase === 'running' && cancelWhen(p)) {
      cancelled = true; out.cancelAt = { ms: Math.round(e.t - tStart), stage: p.stage, progress: p.progress };
      const b = cancelBtn();   // cancelWhen ya exige que el boton exista; el puente es solo una red de seguridad
      if (b) { b.click(); out.cancelClick = 'interfaz'; }
      else { out.cancelClick = 'puente (no habia boton «Cancelar exportación»)'; call('montage.cancelExport').catch(() => {}); }
    }
  });
  const b = exportBtn();
  if (!b || b.disabled) { sub.stop(); out.end = 'no-boton'; return out; }
  tStart = performance.now();
  b.click();
  const tCap = EXPORT_MAX_MS.base + EXPORT_MAX_MS.perPlanS * Math.max(planS, 1);
  let beat = Date.now(), uiAt = 0, lastUi = '', doneEv = null;
  const t = Date.now();
  for (;;) {
    doneEv = evs.find(e => e.phase !== 'running' && e.phase !== 'idle');
    if (doneEv) { out.ms = Math.round(sub.arr.find(x => x.p.phase !== 'running' && x.p.phase !== 'idle').t - tStart); break; }
    if (Date.now() - uiAt >= UI_SAMPLE_MS) { uiAt = Date.now(); const u = domExport(); if (u && u !== lastUi) { lastUi = u; out.ui.push(`${Math.round((Date.now() - t) / 1000)} s: ${u}`); } }
    if (Date.now() - beat >= HEARTBEAT_MS) { beat = Date.now(); const l = evs[evs.length - 1]; INFO(`${label}.latido`, `${Math.round((Date.now() - t) / 1000)} s ultimo evento ${l ? `${l.phase} «${l.stage ?? ''}» ${(l.progress * 100).toFixed(0)}%` : '(ninguno)'}; interfaz: «${domExport()}»`); }
    if (Date.now() - t > tCap) { out.end = 'timeout'; out.ms = Date.now() - t; break; }
    await sleep(100);
  }
  sub.stop();
  if (out.end !== 'timeout') {
    const s = sub.arr.find(x => x.p.phase !== 'running' && x.p.phase !== 'idle').p;
    out.end = s.phase; out.result = s.result ?? null; out.message = s.message ?? null;
    await sleep(500);
    const u = domExport(); if (u && u !== lastUi) out.ui.push(`final: ${u}`);
  }
  return out;
}
const summarizeEvents = o => {
  const stages = []; for (const e of o.events) { const k = e.stage ?? e.phase; if (!stages.length || stages[stages.length - 1].k !== k) stages.push({ k, from: e.ms, p0: e.progress, p1: e.progress, to: e.ms }); else { const s = stages[stages.length - 1]; s.p1 = e.progress; s.to = e.ms; } }
  return `${o.events.length} eventos; ` + stages.map(s => `«${s.k}» ${s.from}-${s.to} ms ${(s.p0 * 100).toFixed(0)}->${(s.p1 * 100).toFixed(0)}%`).join(' | ');
};

// Mide el fichero exportado. exp = lo que se pidio.
async function verifyOutput(tag, o, s0, planS, exp) {
  const r = o.result;
  const base = (r?.path ?? '').split(/[\\/]/).pop();
  const rel = videoRel(base || finalName(s0, exp.container));
  check(`${tag}.ruta`, !!r?.path && base === finalName(s0, exp.container) && /[\\/]video[\\/]/.test(r.path), `result.path=${r?.path}; esperado video/${finalName(s0, exp.container)}`);
  INFO(`${tag}.resultado`, `codec=${r?.codec} LUFS=${r?.finalLUFS == null ? '-' : f1(r.finalLUFS)} pico=${r ? f1(r.finalTruePeakDB) : '-'} dBTP normalizado=${r?.normalized} limitador aplicado=${r?.limiterApplied} recortados=[${r?.clippedFiles ?? []}] pistas=${r?.tracksDirectory ?? '-'}`);
  if (NOFETCH) { SKIP(`${tag}.fichero`, 'fetch de media desactivado (prueba en seco): sin medir contenedor, codecs, duraciones ni RMS'); return null; }
  const f = await getFile(rel, true);
  if (f.unknown) { SKIP(`${tag}.fichero`, `no se pudo leer ${rel}: ${f.why}`); return null; }
  if (!check(`${tag}.fichero`, f.exists && f.bytes > 0, f.exists ? `${rel}: ${f.bytes} B` : `no existe (${f.why}): ${rel}`)) return null;
  if (!f.buf) { SKIP(`${tag}.medir`, `fichero de ${f.bytes} B > ${MAX_FULL_FETCH}: no se carga entero`); return null; }
  let m; try { m = parseMp4(f.buf); } catch (e) { FAIL(`${tag}.cajas`, `parseMp4: ${err(e)}`); return null; }
  INFO(`${tag}.cajas`, `marca ${m.brand}; nivel superior [${m.topLevel}]; movie timescale ${m.movie?.timescale} duracion ${f3((m.movie?.duration ?? NaN) / (m.movie?.timescale || 1))} s; pistas ${m.tracks.map(t => `${t.handler}/${t.codec}`).join(', ')}${m.error ? '; ERROR ' + m.error : ''}`);
  if (!check(`${tag}.pistas`, !!m.video && !!m.audio && !m.error, `video ${m.video ? 'si' : 'NO'}, audio ${m.audio ? 'si' : 'NO'}`)) return m;
  const mp4Brands = ['isom', 'iso2', 'mp41', 'mp42', 'avc1', 'M4V '], isMov = m.brand === 'qt  ';
  check(`${tag}.contenedor`, exp.container === 'mp4' ? mp4Brands.includes(m.brand) : isMov, `pedido ${exp.container}; marca ftyp «${m.brand}»; pedido por UI: ${exp.container}`);
  const wantV = exp.effectiveCodec === 'hevc' ? ['hvc1', 'hev1'] : ['avc1', 'avc3'];
  check(`${tag}.codec-video`, wantV.includes(m.video.codec), `pedido ${exp.codec} (efectivo ${exp.effectiveCodec}); entrada ${m.video.codec} ${m.video.config ?? ''} perfil ${m.video.profile ?? '-'} nivel ${m.video.level ?? '-'}; result.codec=${r?.codec}`);
  check(`${tag}.codec-audio`, m.audio.codec === 'mp4a', `entrada ${m.audio.codec}, ${m.audio.channels} can., ${m.audio.sampleRate} Hz`);
  check(`${tag}.resolucion`, m.video.width === exp.width && m.video.height === exp.height, `pedido ${exp.width}x${exp.height} (export.size; resolution=${exp.resolution}); entrada ${m.video.width}x${m.video.height}; tkhd ${m.video.tkhdW}x${m.video.tkhdH}`);
  check(`${tag}.fps`, Math.abs(m.video.fps - exp.fps) < 0.01, `pedido ${exp.fps}; stts ${f3(m.video.fps)} (delta ${m.video.deltaMode}/${m.video.timescale})`);
  const frame = 1 / exp.fps, tol = DUR_TOL_FRAMES * frame;
  check(`${tag}.duracion-plan`, planS > 0, `plan ${f3(planS)} s (span ${f3(s0.span.start)}-${f3(s0.span.end)}); preview.duration ${s0.preview.duration == null ? '-' : f3(s0.preview.duration)}`);
  check(`${tag}.duracion-video`, Math.abs(m.video.presentedSeconds - planS) <= tol, `presentada ${f3(m.video.presentedSeconds)} s, de muestras ${f3(m.video.sampleSeconds)} s (mdhd ${f3(m.video.mediaSeconds)}); plan ${f3(planS)} s; dif ${f3(m.video.presentedSeconds - planS)} s (tolerancia ${f3(tol)}); ediciones ${JSON.stringify(m.video.edits ?? [])}`);
  check(`${tag}.duracion-audio`, Math.abs(m.audio.presentedSeconds - planS) <= tol, `presentada ${f3(m.audio.presentedSeconds)} s, de muestras ${f3(m.audio.sampleSeconds)} s (mdhd ${f3(m.audio.mediaSeconds)}); plan ${f3(planS)} s; dif ${f3(m.audio.presentedSeconds - planS)} s (tolerancia ${f3(tol)}); ediciones ${JSON.stringify(m.audio.edits ?? [])}`);
  const want = Math.round(planS * exp.fps);
  check(`${tag}.fotogramas`, m.video.stszCount === m.video.sttsCount && Math.abs(m.video.stszCount - want) <= FRAME_COUNT_TOL, `stsz ${m.video.stszCount}, stts ${m.video.sttsCount}; esperado round(${f3(planS)} x ${exp.fps}) = ${want} +-${FRAME_COUNT_TOL}`);
  // Audio decodificado: duracion y RMS (WebAudio del WebView2).
  if (f.bytes > 150 * 1024 * 1024) SKIP(`${tag}.audio-rms`, 'fichero demasiado grande para decodificar en la pagina');
  else {
    try {
      const rate = m.audio.sampleRate || 48000;
      const ab = await new OfflineAudioContext(2, 1, rate).decodeAudioData(f.buf.slice(0));
      const ch = [...Array(ab.numberOfChannels).keys()].map(i => ab.getChannelData(i));
      let s2 = 0, pk = 0; const n = ab.length, bl = Math.max(1, Math.round(AUDIO_BLOCK_S * ab.sampleRate)); let blocks = 0, live = 0;
      for (let a = 0; a < n; a += bl) {
        let bs = 0, c = 0; const e = Math.min(n, a + bl);
        for (const x of ch) for (let i = a; i < e; i++) { const v = x[i]; bs += v * v; c++; const m2 = v < 0 ? -v : v; if (m2 > pk) pk = m2; }
        s2 += bs; blocks++; if (db(Math.sqrt(bs / Math.max(1, c))) > AUDIO_BLOCK_SILENCE_DB) live++;
      }
      const rms = Math.sqrt(s2 / Math.max(1, n * ch.length));
      check(`${tag}.audio-rms`, db(rms) > AUDIO_RMS_MIN_DB, `RMS ${fdb(db(rms))} dBFS (minimo ${AUDIO_RMS_MIN_DB}), pico ${fdb(db(pk))} dBFS; ${live}/${blocks} bloques de ${AUDIO_BLOCK_S} s con senal (> ${AUDIO_BLOCK_SILENCE_DB} dB); ${ab.numberOfChannels} can., ${ab.sampleRate} Hz`);
      check(`${tag}.audio-decodificado`, Math.abs(ab.duration - planS) <= tol + AAC_PRIMING_S, `decodificado ${f3(ab.duration)} s; plan ${f3(planS)} s; dif ${f3(ab.duration - planS)} s (tolerancia ${f3(tol)} + priming AAC ${f3(AAC_PRIMING_S)})`);
    } catch (e) { SKIP(`${tag}.audio-rms`, `decodeAudioData no pudo con el fichero: ${err(e)}`); }
  }
  return m;
}

// Restos: nada de parciales ni WAV de pistas sueltos (el lanzador lista ademas el disco entero: lineas disk|).
async function noLeftovers(tag, s0, container, { tracks = false, finalToo = false } = {}) {
  const fn = finalName(s0, container), stem = fn.slice(0, fn.lastIndexOf('.'));
  await absentFile(`${tag}.sin-parcial`, videoRel(`${stem}.partial.${container}`), `video/${stem}.partial.${container}`);
  await absentFile(`${tag}.sin-mezcla-pistas`, videoRel(`${stem}-pistas/mezcla.wav`), `video/${stem}-pistas/mezcla.wav`);
  if (finalToo) await absentFile(`${tag}.sin-final`, videoRel(fn), `video/${fn}`);
}
// La vista previa sigue viva: un seek en pausa entrega un fotograma de montage y el snapshot responde.
async function previewAlive(tag) {
  const fr = collect('frames.montage');
  try {
    const s = await snap();
    const t = Math.min(s.span.end - 0.2, s.span.start + Math.max(0.3, (s.span.end - s.span.start) * 0.5));
    await call('montage.seek', { seconds: t }, 30000);
    const f = await until(() => fr.arr[0], AFTER_FRAME_MS, 50);
    const s2 = await snap();
    check(`${tag}.preview-viva`, !!f && s2.preview.phase === 'ready', `fotograma tras seek ${t.toFixed(2)} s: ${f ? `${f.p.width}x${f.p.height} seq ${f.p.seq}` : 'NINGUNO en ' + AFTER_FRAME_MS / 1000 + ' s'}; preview ${s2.preview.phase}; entregados ${s2.preview.delivered} saltados ${s2.preview.skipped}; transporte ${JSON.stringify(s2.transport)}`);
  } catch (e) { FAIL(`${tag}.preview-viva`, err(e)); } finally { fr.stop(); }
}
async function appAlive(tag) {
  try { const i = await call('app.info', {}, 15000); const s = await snap(); OK(`${tag}.app-viva`, `app.info ${i.platform}; montage.snapshot ${s.projectId === ctx.id ? 'del mismo tema' : 'OTRO tema'}; exportStatus ${s.exportStatus?.phase}`); }
  catch (e) { FAIL(`${tag}.app-viva`, err(e)); }
}
const expectedOf = s => ({ container: s.export.container, codec: s.export.codec, effectiveCodec: s.export.effectiveCodec, width: s.export.size.width, height: s.export.size.height,
  resolution: `${s.export.resolution.width}x${s.export.resolution.height}`, fps: s.export.fps });

async function dismissUI(tag) {
  const b = btn(/^Cerrar$/);
  if (b) b.click(); else await call('montage.dismissExport');
  const gone = await until(() => !$('.mt-export'), 5000, 100);
  const s = await snap();
  check(`${tag}.cerrar`, !!gone && s.exportStatus.phase === 'idle', `boton ${b ? 'Cerrar de la interfaz' : 'ausente (puente)'}; .mt-export ${$('.mt-export') ? 'sigue' : 'oculto'}; exportStatus ${s.exportStatus.phase}`);
}

// ---------------- Preparacion: cola de arranque, temas, plan ----------------
async function setup() {
  const info = await call('app.info');
  mediaBase = info.mediaBase ?? ''; ctx.platform = info.platform;
  INFO('app', `platform=${info.platform} version=${info.version} carpeta=${info.projectsFolder} modo=${MODE}${NOFETCH ? ' (sin fetch)' : ''}`);
  const busy = (list, jobs) => list.some(p => ['queued', 'running'].includes(p.separationState)) || jobs.some(x => ['queued', 'running'].includes(x.state));
  let list = (await call('library.list', {}, 60000)).projects ?? [], jobs = (await call('jobs.list', {}, 30000).catch(() => ({ jobs: [] }))).jobs ?? [];
  if (busy(list, jobs)) {   // la huella de guitar.wav lleva la fecha: tras copiar a la VM la app rehace guitarras al abrir el tema
    INFO('setup.espera-cola', `la app tiene trabajos al arrancar (${jobs.map(x => `${x.stage}/${x.state} ${x.title}`).join(' | ')}); se espera hasta ${START_QUEUE_MAX_MS / 60000} min`);
    const tq = Date.now(); let beat = tq;
    await until(async () => {
      list = (await call('library.list', {}, 60000)).projects ?? []; jobs = (await call('jobs.list', {}, 30000)).jobs ?? [];
      if (Date.now() - beat >= HEARTBEAT_MS) { beat = Date.now(); INFO('setup.espera-cola.latido', `${Math.round((Date.now() - tq) / 1000)} s: ${jobs.map(x => `${x.stage}/${x.state} ${x.text}`).join(' | ')}`); }
      return !busy(list, jobs);
    }, START_QUEUE_MAX_MS, 3000);
    INFO('setup.espera-cola.fin', `${Math.round((Date.now() - tq) / 1000)} s`);
  } else INFO('setup.cola', 'vacia');
  // Lista de temas: tomas y video (siempre se vuelca).
  const rows = [];
  for (const p of list) {
    let d = null, takes = [];
    try { d = await call('library.project', { id: p.id }, 60000); takes = (d.parts ?? []).flatMap(x => x.takes ?? []).filter(t => !t.discarded); } catch (e) { INFO('setup.tema', `«${p.title}» library.project fallo: ${err(e)}`); }
    rows.push({ p, takes: takes.length, video: takes.filter(t => t.hasVideo).length, takeCountList: p.takeCount });
  }
  INFO('setup.temas', rows.map(r => `«${r.p.title}» tomas=${r.takes} (ficha ${r.takeCountList}) con video=${r.video}`).join(' | ') || '(ninguno)');
  const cand = rows.filter(r => r.video > 0);
  if (!cand.length) {
    check('setup.tema-con-video', false, `ningun tema de la copia tiene tomas con video (${rows.length} temas). Hay que copiar a la VM un tema con takes/<id>/video.mov y su project.json (p. ej. «Megadeth - Tornado Of Souls» de Temp/qa-7c/evalB/projects: 3 tomas, 1 con video, plan de ~2 s) a C:\\tf-qa\\projects, o el de «El roce de tu cuerpo» sin su carpeta video/`);
    return false;
  }
  // Plan de cada candidato (montage.open): no hay control de rango en la pantalla, el plan es el tramo de las tomas.
  const forced = globalThis.MONTAGE_TITLE;
  const probes = [];
  for (const r of cand.slice(0, PLAN_MAX_PROBE)) {
    try {
      const s = await call('montage.open', { projectId: r.p.id }, 120000);
      const len = s.span.end - s.span.start;
      probes.push({ r, len, hasPlan: s.hasPlan, hasVideo: s.hasVideo, lanes: s.lanes.length, layout: s.layout, cuts: s.cuts.length });
    } catch (e) { INFO('setup.plan', `«${r.p.title}» montage.open fallo: ${err(e)}`); }
    finally { try { await call('montage.close', {}, 60000); } catch { /* ya */ } }
  }
  INFO('setup.planes', probes.map(x => `«${x.r.p.title}» plan ${f1(x.len)} s, ${x.lanes} partes, ${x.cuts} cortes, layout ${x.layout}, hasVideo=${x.hasVideo}`).join(' | '));
  const usable = probes.filter(x => x.hasPlan && x.hasVideo && x.len > 0);
  const pick = (forced && usable.find(x => x.r.p.title.includes(forced))) ?? usable.sort((a, b) => Math.abs(a.len - PLAN_TARGET_S) - Math.abs(b.len - PLAN_TARGET_S))[0];
  if (!check('setup.tema-con-video', !!pick, pick ? `«${pick.r.p.title}» plan ${f1(pick.len)} s, ${pick.lanes} partes con ${pick.r.video} toma(s) con video, ${list.length} temas en la copia` : `ningun tema con plan y video utilizable entre ${probes.length} probados (ver setup.planes)`)) return false;
  ctx.proj = pick.r.p; ctx.id = pick.r.p.id; ctx.folder = pick.r.p.folderName; ctx.plan = pick.len;
  if (pick.len > PLAN_LONG_S) INFO('setup.plan-largo', `el plan dura ${f1(pick.len)} s (> ${PLAN_LONG_S}): Montaje no tiene control de rango; se exporta entero con tope ${Math.round((EXPORT_MAX_MS.base + EXPORT_MAX_MS.perPlanS * pick.len) / 60000)} min`);
  else if (pick.len < PLAN_SHORT_S) INFO('setup.plan-corto', `el plan dura solo ${f1(pick.len)} s (< ${PLAN_SHORT_S}): los s/s salen ruidosos y la cancelacion a mitad puede llegar tarde`);
  return true;
}

// ---------------- Modos ----------------
async function fullMode() {
  const o = await openMontageUI(ctx.proj);
  if (!check('ui.montaje', !!o.snapshot, `pantalla Montaje abierta ${o.viaUI ? 'por la barra lateral y el selector' : 'directamente'}; tema ${o.snapshot?.title}`)) return;
  const ready = await waitReady();
  if (!check('ui.preparado', ready.ok, ready.ok ? `${Math.round(ready.ms / 1000)} s hasta vista previa lista y «Exportar vídeo» habilitado; ${ready.s.lanes.length} partes, layout ${ready.s.layout}, lienzo ${ready.s.canvasLabel}` : ready.why)) return;
  // Ajustes: el codec y contenedor que ofrece la plataforma (por el puente: es lo que dispara el Popup de la interfaz); resto por defecto.
  const o0 = ready.s.export.options;
  const set = { container: o0.containers.includes('mp4') ? 'mp4' : o0.containers[0], codec: o0.codecs.includes('h264') ? 'h264' : o0.codecs[0], trackWAVs: false };
  INFO('ajustes', `opciones: codecs [${o0.codecs}] contenedores [${o0.containers}] resoluciones [${o0.resolutions.map(r => `${r.width}x${r.height}`)}] fps [${o0.fps}]; se pide ${JSON.stringify(set)}; por defecto resolution=${ready.s.export.resolution.width}x${ready.s.export.resolution.height} fps=${ready.s.export.fps} normalizar=${ready.s.export.normalize} limitador=${ready.s.export.limiter}`);
  await call('montage.setExport', set);
  const s0 = await until(async () => { const x = await snap(); return x.export.canExport && exportBtn() && !exportBtn().disabled ? x : null; }, 30000, 300);
  if (!check('ajustes.aplicados', !!s0 && s0.export.container === set.container && s0.export.codec === set.codec, s0 ? `container=${s0.export.container} codec=${s0.export.codec} efectivo=${s0.export.effectiveCodec} tamano ${s0.export.size.width}x${s0.export.size.height} fps ${s0.export.fps}` : 'sin snapshot listo tras setExport')) return;
  const planS = s0.span.end - s0.span.start, exp = expectedOf(s0);
  INFO('plan', `${f3(planS)} s (span ${f3(s0.span.start)}-${f3(s0.span.end)}), ${s0.segments.length} tramos, ${s0.cuts.length} cortes, cutGaps=${s0.cutGaps}, layout ${s0.layout}, partes con video ${s0.lanes.filter(l => l.hasVideo).length}/${s0.lanes.length}`);
  check('plan.exportable', planS > 0 && s0.export.canExport, `canExport=${s0.export.canExport}`);

  const x = await runExport('exportar', planS);
  INFO('exportar.progreso', summarizeEvents(x));
  INFO('exportar.interfaz', x.ui.join(' || ') || '(la interfaz no mostro .mt-export)');
  check('exportar.fin', x.end === 'done', `${x.end} en ${(x.ms / 1000).toFixed(2)} s${x.message ? ': ' + x.message : ''}`);
  const sawRun = x.events.some(e => e.phase === 'running'), mono = x.events.every((e, i, a) => i === 0 || e.progress + 1e-9 >= a[i - 1].progress);
  check('exportar.progreso-visto', sawRun && mono && x.ui.some(u => /Exportando|Mezclando|Codificando|%/.test(u)), `eventos running ${x.events.filter(e => e.phase === 'running').length}, progreso monotono=${mono}, la interfaz mostro: ${x.ui.length ? x.ui[0].slice(0, 120) : 'nada'}`);
  if (x.end === 'done') {
    const secs = x.ms / 1000;
    INFO('exportar.tiempo', `${secs.toFixed(2)} s totales desde el clic hasta «done»; ${f3(secs / planS)} s de exportacion por segundo de video (plan ${f3(planS)} s)`);
    await verifyOutput('salida', x, s0, planS, exp);
    await dismissUI('salida');
  } else { INFO('exportar.interfaz-final', domExport()); }
  await noLeftovers('salida', s0, exp.container, { tracks: false });
  await previewAlive('salida');
  await appAlive('salida');
}

async function cancelMode() {
  const o = await openMontageUI(ctx.proj);
  if (!check('ui.montaje', !!o.snapshot, `pantalla Montaje abierta; tema ${o.snapshot?.title}`)) return;
  const ready = await waitReady();
  if (!check('ui.preparado', ready.ok, ready.ok ? `${Math.round(ready.ms / 1000)} s; ${ready.s.lanes.length} partes` : ready.why)) return;
  const o0 = ready.s.export.options;
  const set = { container: o0.containers.includes('mp4') ? 'mp4' : o0.containers[0], codec: o0.codecs.includes('h264') ? 'h264' : o0.codecs[0] };
  const planS = ready.s.span.end - ready.s.span.start;

  // A: cancelar mezclando (con WAV por pista: si el audio se interrumpe, los WAV deben desaparecer)
  // B: cancelar codificando a mitad
  // C: exportar de nuevo hasta el final (un parcial que quedara abierto lo estropearia)
  const cases = [
    { tag: 'A', desc: 'mezclando, con «WAV de cada pista»', trackWAVs: true, when: p => !!cancelBtn() && ((p.stage ?? '').includes('Mezclando') || p.progress > 0) },
    { tag: 'B', desc: 'codificando, a mitad', trackWAVs: false, when: p => !!cancelBtn() && STAGE_ENCODE.test(p.stage ?? '') && (p.progress - MIX_SHARE) / (1 - MIX_SHARE) >= ENC_CANCEL_FRACTION },
  ];
  for (const c of cases) {
    INFO(`${c.tag}.inicio`, `cancelar ${c.desc}`);
    await call('montage.setExport', { ...set, trackWAVs: c.trackWAVs });
    const s0 = await until(async () => { const x = await snap(); return x.export.canExport && exportBtn() && !exportBtn().disabled ? x : null; }, 30000, 300);
    if (!check(`${c.tag}.listo`, !!s0, 'Exportar habilitado')) return;
    const x = await runExport(`cancel-${c.tag}`, planS, { cancelWhen: c.when });
    INFO(`${c.tag}.progreso`, summarizeEvents(x));
    if (!x.cancelAt) { SKIP(`${c.tag}.cancelar`, `la exportacion acabo (${x.end}, ${(x.ms / 1000).toFixed(2)} s) antes de que llegara el momento de cancelar: plan de ${f3(planS)} s demasiado corto o evento no emitido`); await dismissUI(`${c.tag}`); continue; }
    INFO(`${c.tag}.cancelado-en`, `${x.cancelAt.ms} ms, etapa «${x.cancelAt.stage}», progreso ${(x.cancelAt.progress * 100).toFixed(0)}%, via ${x.cancelClick}`);
    check(`${c.tag}.fin`, x.end === 'cancelled', `fase final ${x.end} tras ${(x.ms / 1000).toFixed(2)} s${x.message ? ': ' + x.message : ''}; interfaz: «${x.ui[x.ui.length - 1] ?? ''}»`);
    check(`${c.tag}.interfaz`, x.ui.some(u => /cancelada/i.test(u)), `texto «Exportación cancelada.» visto: ${x.ui.filter(u => /cancelada/i.test(u))[0] ?? 'no'}`);
    await sleep(1500);   // margen para que acaben las limpiezas del exportador y el controlador
    await noLeftovers(c.tag, s0, s0.export.container, { finalToo: true });
    await absentFile(`${c.tag}.sin-pistas`, videoRel(`${finalName(s0, s0.export.container).replace(/\.[^.]+$/, '')}-pistas/mezcla.wav`), 'WAV mezcla de pistas');
    await dismissUI(c.tag);
    await appAlive(c.tag);
    await previewAlive(c.tag);
  }
  // C
  await call('montage.setExport', { ...set, trackWAVs: false });
  const sC = await until(async () => { const x = await snap(); return x.export.canExport && exportBtn() && !exportBtn().disabled ? x : null; }, 30000, 300);
  if (!check('C.listo', !!sC, 'Exportar habilitado tras cancelar')) return;
  const exp = expectedOf(sC);
  const x = await runExport('reexportar', planS);
  INFO('C.progreso', summarizeEvents(x));
  check('C.fin', x.end === 'done', `${x.end} en ${(x.ms / 1000).toFixed(2)} s${x.message ? ': ' + x.message : ''}`);
  if (x.end === 'done') { await verifyOutput('C', x, sC, sC.span.end - sC.span.start, exp); await dismissUI('C'); }
  await noLeftovers('C', sC, exp.container);
  await appAlive('C');
}

async function main() {
  if (!(await setup())) return;
  if (MODE === 'cancel') await cancelMode(); else await fullMode();
}
try { await main(); } catch (e) { FAIL('excepcion', `${err(e)} ${String(e?.stack ?? '').split('\n').slice(1, 3).join(' | ')}`); }
finally { for (const o of offs) { try { o(); } catch { /* ya */ } } try { await call('montage.close', {}, 30000); } catch { /* ya */ } }
INFO('total', `${Math.round((Date.now() - T0) / 1000)} s`);
log(`DONE montage ${ok}/${ok + bad} (skip ${skip})`);
return 'ok';
