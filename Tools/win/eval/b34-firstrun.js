// B3 (primer arranque) y B4 (fotos de artista) en la app de Windows. Cuerpo de funcion async con (bridge, log).
// El lanzador antepone variables globales (b34-launch.ps1 / b34-dry.sh):
//   B34_MODE   'firstrun' | 'photos'
//   B34_LAUNCH firstrun: 1 (support y carpeta vacios; hay que elegir carpeta) | 2 (el perfil ya la tiene)
//              photos:   'cold' (cache vacia, entorno normal) | 'warm' (cache sembrada, SIN red ni credenciales) | 'offline' (cache vacia, sin red)
//   B34_DIALOG 'ui' (el lanzador maneja el selector nativo con UI Automation) | 'none' (tf-webdev: no se pulsa el boton)
//   B34_PICK   'hook' (la app lleva TF_TEST_PICK_FOLDER: host.pickProjectsFolder devuelve B34_CHOSEN sin dialogo) | 'uia' (el lanzador rellena el selector nativo; plan B)
//   B34_CHOSEN carpeta que debe quedar elegida (firstrun); B34_PROBE_TEXT contenido de <carpeta>\b34-probe.txt
//   B34_EXPECT {photo:[stem,...]} artistas que DEBEN mostrar foto (warm) o [] (offline)
// Linea: `OK|FAIL|SKIP|INFO <nombre> <dato>` (el anfitrion antepone `eval| `); ultima: `DONE b34part <modo>/<lanzamiento> n/m (skip k)`.
// El lanzador suma las partes y imprime `DONE b34 n/m (skip k)`. Solo toca la copia/soporte que trae el lanzador.
const MODE = globalThis.B34_MODE ?? 'photos';
const LAUNCH = String(globalThis.B34_LAUNCH ?? (MODE === 'photos' ? 'cold' : '1'));
const DIALOG = globalThis.B34_DIALOG ?? 'ui';
const PICK = globalThis.B34_PICK ?? 'uia';
const CHOSEN = globalThis.B34_CHOSEN ?? '';
const PROBE_TEXT = globalThis.B34_PROBE_TEXT ?? 'b34';
const EXPECT = globalThis.B34_EXPECT ?? null;

// Textos de la hoja del Mac (App/Sources/RootView.swift FirstRunSheet). La linea «Propuesta» es propia de cada SO.
const MAC_TITLE = 'Elige tu carpeta de proyectos';
const MAC_BODY = 'Cada tema vive en su propia carpeta, con sus stems, tomas y vídeo. Puedes cambiarla más tarde en Ajustes.';
const MAC_BUTTON = 'Elegir carpeta…';
const DIALOG_WAIT_MS = 120000;        // el lanzador maneja el selector: tiempo maximo hasta que la hoja se cierra
const QUEUE_WAIT_MS = 300000;         // cola de trabajos de arranque (recuperacion/analisis) antes de medir
const TILE_SETTLE_MS = 6000;          // sin cambios en las fotos durante este tiempo = asentado
const TILE_CAP_MS = 90000;            // tope de espera a las fotos (cold con red: 2 peticiones a la vez)
const TILE_MIN_MS = 3000;
// Color de iniciales del Mac (ArtistTile.color: FNV-1a del nombre plegado, HSB 0,45/0,5 = HSL 29% 38,75%)
const TILE_SAT_L = 'hsl(%H 29% 38.75%)';

const sleep = ms => new Promise(r => setTimeout(r, ms));
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const txt = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
const T0 = Date.now();
let ok = 0, bad = 0, skip = 0;
const OK = (n, d = '') => { ok++; log(`OK ${n} ${d}`.trimEnd()); return true; };
const FAIL = (n, d = '') => { bad++; log(`FAIL ${n} ${d}`.trimEnd()); return false; };
const SKIP = (n, d = '') => { skip++; log(`SKIP ${n} ${d}`.trimEnd()); return false; };
const INFO = (n, d = '') => log(`INFO ${n} ${d}`.trimEnd());
const check = (n, cond, d = '') => (cond ? OK(n, d) : FAIL(n, d));
const err = e => `${e?.code ? e.code + ': ' : ''}${e?.message ?? e}`;
const call = (m, p, t = 60000) => bridge.call(m, p ?? {}, { timeout: t });
const tryCall = async (m, p, t) => { try { return { ok: true, v: await call(m, p, t) }; } catch (e) { return { ok: false, e }; } };
async function until(fn, ms = 5000, step = 100) {
  const t = Date.now();
  for (;;) {
    let v = null; try { v = await fn(); } catch { v = null; }
    if (v) return v;
    if (Date.now() - t > ms) return null;
    await sleep(step);
  }
}
const btn = re => $$('button').find(b => re.test(txt(b)));
const foldName = s => (s ?? '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
const samePath = (a, b) => (a ?? '').replace(/[\\/]+/g, '/').replace(/\/$/, '').toLowerCase() === (b ?? '').replace(/[\\/]+/g, '/').replace(/\/$/, '').toLowerCase();

// Errores de la pagina durante el guion (degradacion sin red = ninguno)
const pageErrors = [];
window.addEventListener('error', e => pageErrors.push(String(e.message)));
window.addEventListener('unhandledrejection', e => pageErrors.push('rechazo: ' + String(e.reason?.message ?? e.reason)));

const goLibrary = async () => {
  $$('.nav-item').find(b => txt(b) === 'Biblioteca')?.click();
  await sleep(150);
  if ($('.link-back')) { $('.link-back').click(); await sleep(150); }
};
const alerts = () => $$('[role=alert], .toast, .banner-error, .modal-error').map(txt).filter(Boolean);

// ---------------------------------------------------------------- B3
async function firstrunOne() {
  const info = await call('app.info');
  INFO('app', `platform=${info.platform} version=${info.version} carpeta=${info.projectsFolder ?? 'null'} mediaBase=${info.mediaBase} lanzamiento=${LAUNCH} dialogo=${DIALOG} selector=${PICK}`);
  const emptyShown = () => $$('.empty').some(e => /Todavía no hay temas/.test(txt(e)));
  const sheet = () => $$('.modal').find(m => /carpeta de proyectos/i.test(txt(m)));

  if (LAUNCH === '2') {
    // Segundo lanzamiento: el perfil ya tiene la carpeta; no puede haber hoja.
    await goLibrary();
    check('fr2.carpeta-del-perfil', samePath(info.projectsFolder, CHOSEN), `app.info=${info.projectsFolder} esperada=${CHOSEN}`);
    const l = await tryCall('library.list');
    check('fr2.library.list-ok', l.ok && Array.isArray(l.v.projects) && l.v.projects.length === 0, l.ok ? `${l.v.projects.length} temas` : err(l.e));
    await sleep(800);
    check('fr2.sin-hoja', !sheet() && !$('.modal'), `modal=${txt($('.modal')).slice(0, 80)}`);
    check('fr2.biblioteca-vacia-usable', emptyShown() && !!btn(/^Importar tema$/) && !btn(/^Importar tema$/).disabled, `vacia=${emptyShown()}`);
    const s = await tryCall('settings.get');
    check('fr2.settings', s.ok && samePath(s.v.projectsFolder, CHOSEN) && samePath(s.v.activeProjectsFolder, CHOSEN), s.ok ? `perfil=${s.v.projectsFolder} activa=${s.v.activeProjectsFolder}` : err(s.e));
    await probeMedia(info, 'fr2');
    return;
  }

  // Lanzamiento 1: sin carpeta.
  check('fr1.app.info-sin-carpeta', !info.projectsFolder, `carpeta=${info.projectsFolder ?? 'null'}`);
  const l0 = await tryCall('library.list');
  check('fr1.library.list-no-projects-folder', !l0.ok && l0.e?.code === 'no-projects-folder', l0.ok ? 'respondio ok' : err(l0.e));
  const s0 = await tryCall('settings.get');
  check('fr1.settings.get-sin-carpeta', s0.ok && !s0.v.projectsFolder && !s0.v.activeProjectsFolder, s0.ok ? `perfil=${s0.v.projectsFolder ?? 'null'} activa=${s0.v.activeProjectsFolder ?? 'null'}` : err(s0.e));
  await goLibrary();
  const m = await until(sheet, 8000);
  if (!check('fr1.hoja-visible', !!m, m ? '' : `modales=${$$('.modal').length}; texto de pagina: ${txt(document.body).slice(0, 200)}`)) return;
  const mt = txt(m);
  INFO('fr1.texto-hoja', mt);
  // Mismos pasos que el Mac: titulo, texto, propuesta, un unico boton «Elegir carpeta…», sin forma de cerrarla.
  check('fr1.titulo', txt($('.modal-title', m)) === MAC_TITLE, txt($('.modal-title', m)));
  check('fr1.texto', mt.includes(MAC_BODY), 'texto del Mac presente');
  const prop = $$('p', m).map(txt).find(t => /^Propuesta/.test(t));
  check('fr1.propuesta', !!prop, prop ?? '(sin linea Propuesta)');
  INFO('fr1.propuesta-vs-mac', `win=«${prop ?? ''}» mac=«Propuesta: ~/Music/ToneForge» (SO distinto: la ruta es ${/Música|Music/.test(prop ?? '') ? 'la de Windows' : '?'})`);
  const buttons = $$('button', m).map(txt);
  check('fr1.un-solo-boton', buttons.length === 1 && buttons[0] === MAC_BUTTON, JSON.stringify(buttons));
  m.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  $('.modal-backdrop')?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
  $('.modal-backdrop')?.click();
  await sleep(400);
  check('fr1.no-se-cierra', !!sheet(), 'Esc y clic fuera no la cierran (interactiveDismissDisabled del Mac)');
  check('fr1.sin-error-visible', alerts().length === 0, alerts().join(' | '));

  if (DIALOG !== 'ui') {
    SKIP('fr1.completar', 'B34_DIALOG=none: el selector es nativo (NSOpenPanel/IFileOpenDialog); aqui no se pulsa. El resto se prueba en el 2.o lanzamiento (perfil escrito por el lanzador)');
    return;
  }
  // Completar por la interfaz: el boton abre IFileOpenDialog; el lanzador lo rellena con UI Automation (b34-task.ps1).
  const t = Date.now();
  btn(/Elegir carpeta/).click();
  await sleep(300);
  INFO('fr1.boton-ocupado', `deshabilitado=${!!btn(/Elegir carpeta/)?.disabled} (mientras el selector esta abierto)`);
  const closed = await until(() => !sheet(), DIALOG_WAIT_MS, 250);
  const dt = Date.now() - t;
  if (!check('fr1.selector-completado', !!closed, closed ? `${dt} ms hasta cerrarse la hoja` : `la hoja sigue tras ${dt} ms: ${PICK === 'hook' ? 'el gancho TF_TEST_PICK_FOLDER no llego a la app (variable no definida?) o fallo host.pickProjectsFolder' : 'el lanzador no pudo manejar el selector (ver .dialog.txt)'}; errores: ${alerts().join(' | ')}`)) return;
  check('fr1.sin-reinicio', !$$('.modal').some(x => /Reinicia ToneForge/.test(txt(x))) && !/Cierra ToneForge y vuelve a abrirlo/.test(txt(document.body)), 'no pide reiniciar');
  await sleep(1200);
  const i2 = await call('app.info');
  check('fr1.app.info-carpeta', samePath(i2.projectsFolder, CHOSEN), `app.info=${i2.projectsFolder} esperada=${CHOSEN}`);
  const s = await tryCall('settings.get');
  check('fr1.settings-perfil-y-activa', s.ok && samePath(s.v.projectsFolder, CHOSEN) && samePath(s.v.activeProjectsFolder, CHOSEN), s.ok ? `perfil=${s.v.projectsFolder} activa=${s.v.activeProjectsFolder}` : err(s.e));
  const l = await tryCall('library.list');
  check('fr1.library.list-vacia', l.ok && l.v.projects.length === 0, l.ok ? `${l.v.projects.length} temas` : err(l.e));
  const jl = await tryCall('jobs.list');
  check('fr1.jobs.list', jl.ok && (jl.v.jobs ?? []).length === 0, jl.ok ? `${(jl.v.jobs ?? []).length} trabajos` : err(jl.e));
  const shown = await until(emptyShown, 6000);
  check('fr1.biblioteca-vacia-visible', !!shown && !$('.modal'), `vacia=${!!shown} modal=${!!$('.modal')} errores=${$$('.card').map(txt).filter(x => /Falta la carpeta/.test(x)).length}`);
  const imp = btn(/^Importar tema$/);
  check('fr1.importar-usable', !!imp && !imp.disabled, imp ? 'boton habilitado' : 'sin boton');
  if (imp && !imp.disabled) {
    imp.click();
    const link = await until(() => $$('.modal').find(x => /enlace|Importar/i.test(txt(x))), 4000);
    check('fr1.importar-abre-hoja', !!link, link ? txt($('.modal-title', link)) : 'no abrio');
    const cancel = $$('.modal button').find(b => /Cancelar|Cerrar/.test(txt(b)));
    cancel?.click(); await sleep(300);
    if ($('.modal')) { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); await sleep(300); }
  }
  await probeMedia(i2, 'fr1');
  check('fr1.sin-errores-pagina', pageErrors.length === 0, pageErrors.join(' | '));
}

// El anfitrion remapea media.toneforge a la carpeta elegida: el lanzador deja <carpeta>\b34-probe.txt.
async function probeMedia(info, tag) {
  const base = info.mediaBase ?? '';
  if (globalThis.B34_NOFETCH) return SKIP(`${tag}.medios-remapeados`, 'B34_NOFETCH (tf-webdev no deja leer medios por fetch)');
  try {
    const r = await fetch((base.endsWith('/') ? base : base + '/') + 'b34-probe.txt', { cache: 'no-store' });
    const t = r.ok ? (await r.text()).trim() : '';
    check(`${tag}.medios-remapeados`, r.ok && t === PROBE_TEXT, `HTTP ${r.status} contenido=«${t.slice(0, 20)}» (media.toneforge apunta a la carpeta elegida)`);
  } catch (e) { FAIL(`${tag}.medios-remapeados`, String(e)); }
}

// ---------------------------------------------------------------- B4
// Nombre de fichero de la cache (ArtistPhotoService.fileStem): plegado, 40 caracteres alfanumericos o «-», FNV-1a hex.
function fileStem(name) {
  const key = foldName(name);
  let h = 0xcbf29ce484222325n;
  for (const b of new TextEncoder().encode(key)) h = ((h ^ BigInt(b)) * 0x100000001b3n) & 0xffffffffffffffffn;
  const slug = [...key].map(c => (/[\p{L}\p{N}\p{M}]/u.test(c) ? c : '-')).slice(0, 40).join('');
  return `${slug}-${h.toString(16)}`;
}
const initialsOf = name => name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => [...w][0]).join('').toUpperCase() || '?';
function colorOf(name) {
  let h = 0xcbf29ce484222325n;
  for (const b of new TextEncoder().encode(foldName(name))) h = ((h ^ BigInt(b)) * 0x100000001b3n) & 0xffffffffffffffffn;
  const probe = document.createElement('div');
  probe.style.background = TILE_SAT_L.replace('%H', String(Number(h % 360n)));
  document.body.appendChild(probe);
  const c = getComputedStyle(probe).backgroundColor; probe.remove(); return c;
}
const dataBytes = u => { const i = u.indexOf(','); const b64 = u.slice(i + 1); return Math.floor(b64.length * 3 / 4) - (b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0); };
const dataMime = u => (/^data:([^;,]+)/.exec(u) ?? [])[1] ?? '?';

async function photos() {
  const info = await call('app.info');
  INFO('app', `platform=${info.platform} version=${info.version} carpeta=${info.projectsFolder} lanzamiento=${LAUNCH} online=${navigator.onLine}`);
  check('ph.carpeta-copia', !!info.projectsFolder && /b34|tf-qa/i.test(info.projectsFolder), info.projectsFolder);
  // Cola de arranque vacia antes de medir tiempos (precedente b1: huella de stems puede encolar analisis/guitarras).
  const quiet = await until(async () => {
    const j = (await tryCall('jobs.list')); const l = (await tryCall('library.list'));
    return j.ok && (j.v.jobs ?? []).length === 0 && l.ok && !l.v.projects.some(p => ['running', 'queued'].includes(p.separationState));
  }, QUEUE_WAIT_MS, 1500);
  INFO('ph.cola-arranque', quiet ? `vacia a los ${Date.now() - T0} ms` : 'NO se vacio (los tiempos pueden salir inflados)');
  const list = (await call('library.list')).projects;
  const names = [...new Map(list.map(p => [foldName(p.artist ?? ''), (p.artist ?? '').trim()])).values()];
  check('ph.hay-artistas', names.length > 0, `${list.length} temas, ${names.length} artistas: ${names.map(n => n || '(sin artista)').join(' | ')}`);
  const stems = Object.fromEntries(names.filter(Boolean).map(n => [n, fileStem(n)]));
  log(`INFO stems ${JSON.stringify(stems)}`);

  // Rejilla de Artistas: tiempo hasta que sale cada foto (observador de mutaciones).
  await goLibrary();
  const radio = $$('[role=radio]').find(b => txt(b) === 'Artistas');
  if (!check('ph.vista-artistas', !!radio, radio ? '' : 'no hay interruptor «Artistas»')) return;
  const seen = new Map();   // nombre -> ms desde el clic en que aparecio su <img>
  const t0 = Date.now();
  let lastChange = t0;
  const tileName = t => (t.getAttribute('aria-label') ?? '').replace(/, \d+ temas?$/, '').replace(/^Sin artista$/, '');
  const scan = () => $$('.tiles .tile').forEach(t => {
    const n = tileName(t);
    if (!seen.has(n) && t.querySelector('.tile-cover img')) { seen.set(n, Date.now() - t0); lastChange = Date.now(); }
  });
  const mo = new MutationObserver(scan);
  INFO('ph.vista-inicial', `Artistas ya activa antes del clic: ${radio.getAttribute('aria-checked')} (si es true la rejilla se montó antes de medir y ms-hasta-foto sale 0)`);
  radio.click();
  const grid = await until(() => $('.tiles'), 5000, 50);
  if (!check('ph.rejilla', !!grid, '.tiles')) return;
  mo.observe(grid, { childList: true, subtree: true, attributes: true });
  scan();
  const tiles0 = $$('.tiles .tile');
  check('ph.un-recuadro-por-artista', tiles0.length === names.length, `recuadros=${tiles0.length} artistas=${names.length}`);
  for (;;) {
    scan();
    const el = Date.now() - t0;
    if (el >= TILE_CAP_MS || (el >= TILE_MIN_MS && Date.now() - lastChange >= TILE_SETTLE_MS)) break;
    await sleep(250);
  }
  mo.disconnect();
  INFO('ph.asentado', `${Date.now() - t0} ms; con foto ${seen.size}/${names.length}`);

  const shownPhoto = [];
  for (const t of $$('.tiles .tile')) {
    const n = tileName(t);
    const cover = $('.tile-cover', t), img = $('img', cover);
    const stem = n ? fileStem(n) : '';
    let tile, bytes = 0, mime = '', dims = '';
    if (img) {
      tile = 'foto'; bytes = dataBytes(img.src); mime = dataMime(img.src);
      dims = `${img.naturalWidth}x${img.naturalHeight}`;
      check(`ph.decodifica[${n}]`, img.complete && img.naturalWidth > 0, `${mime} ${dims}`);
      shownPhoto.push(stem);
    } else if (!n) {
      tile = 'persona';
      check('ph.sin-artista-marcador', !!$('.tile-person', cover) && !$('.tile-initials', cover), 'icono de persona, sin iniciales (como el Mac)');
    } else {
      tile = 'iniciales';
      const ini = txt($('.tile-initials', cover)), col = getComputedStyle(cover).backgroundColor;
      check(`ph.marcador[${n}]`, ini === initialsOf(n) && col === colorOf(n), `iniciales=${ini} (esp ${initialsOf(n)}) fondo=${col} (esp ${colorOf(n)})`);
    }
    // La llamada directa ya encuentra la cache (o la negativa): su tiempo es el de la RPC en caliente.
    let rpcMs = -1, rpcBytes = 0, same = '';
    if (n) {
      const a = Date.now(); const r = await tryCall('library.artistPhoto', { name: n }, 30000); rpcMs = Date.now() - a;
      if (!r.ok) FAIL(`ph.rpc[${n}]`, err(r.e));
      else {
        rpcBytes = r.v.photo ? dataBytes(r.v.photo) : 0;
        same = img ? String(r.v.photo === img.src) : String(r.v.photo == null);
        check(`ph.rpc-coherente[${n}]`, (r.v.photo != null) === !!img && (!img || r.v.photo === img.src), `rpc=${r.v.photo ? dataMime(r.v.photo) + ' ' + rpcBytes + ' B' : 'null'} recuadro=${tile}`);
      }
    }
    log(`INFO photo ${stem || '-'}|${n || '(sin artista)'}|${tile}|${bytes}|${seen.get(n) ?? -1}|${rpcMs}|${mime}${dims ? ' ' + dims : ''}`);
  }
  log(`INFO columnas-photo stem|artista|recuadro|bytes-pagina|ms-hasta-foto(-1=no salio)|ms-rpc-caliente|mime`);

  if (LAUNCH === 'warm' || LAUNCH === 'offline') {
    const want = new Set(EXPECT?.photo ?? []);
    for (const [n, stem] of Object.entries(stems)) {
      const has = shownPhoto.includes(stem);
      check(`ph.${LAUNCH}.foto[${n}]`, has === want.has(stem), `foto=${has} esperada=${want.has(stem)}`);
    }
    if (LAUNCH === 'warm') {
      const slow = [...seen.entries()].filter(([, ms]) => ms > 2500);
      check('ph.warm.rapida', slow.length === 0, `todas las fotos de cache salen en <2,5 s: lentas=${JSON.stringify(slow)} (sin red ni credenciales: una peticion nueva fallaria)`);
    }
  }
  check('ph.degradacion-sin-alertas', alerts().length === 0, alerts().join(' | ') || 'sin alertas ni toasts');
  check('ph.sin-errores-pagina', pageErrors.length === 0, pageErrors.join(' | '));
  // Asignar/quitar a mano: el Mac no lo permite (ArtistGrid solo muestra; no hay menu ni RPC equivalentes).
  const assign = await tryCall('library.setArtistPhoto', { name: names.find(Boolean) ?? 'x', path: '' }, 5000);
  const menuItems = (() => { const t = $('.tiles .tile'); return t ? 'clic derecho no probado' : ''; })();
  if (!assign.ok && /unknown|unsupported|not.?found|desconoc/i.test(`${assign.e?.code} ${assign.e?.message}`)) SKIP('ph.asignar-quitar-a-mano', `el Mac no lo ofrece y Windows tampoco (library.setArtistPhoto: ${err(assign.e)}); ${menuItems}`);
  else if (!assign.ok) SKIP('ph.asignar-quitar-a-mano', `el Mac no lo ofrece (ArtistGrid.swift solo muestra); RPC de prueba: ${err(assign.e)}`);
  else FAIL('ph.asignar-quitar-a-mano', 'existe library.setArtistPhoto en Windows pero el Mac no lo ofrece: revisar');
}

try {
  if (MODE === 'firstrun') await firstrunOne(); else await photos();
} catch (e) {
  FAIL('guion', `excepcion: ${err(e)} ${(e?.stack ?? '').split('\n').slice(0, 2).join(' / ')}`);
}
log(`DONE b34part ${MODE}/${LAUNCH} ${ok}/${ok + bad} (skip ${skip})`);
