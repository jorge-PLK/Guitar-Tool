// B2: cambiar la carpeta de proyectos en caliente desde Ajustes > Biblioteca. Cuerpo de funcion async con (bridge, log).
// El lanzador (b2-launch.ps1 / b2-dry.sh) antepone: B2_PHASE ('a'|'b'), B2_P0..B2_P3 (carpetas), B2_P2_COUNT (temas que trae P2),
//   B2_PICK_HOOK (ruta o ''; la del gancho TF_TEST_PICK_FOLDER con que se lanzo la app: host.chooseFolder la devuelve sin dialogo),
//   B2_NOFETCH (true: el anfitrion no deja leer media por fetch, p. ej. tf-webdev), B2_DISK_WAIT_MS (espera tras cada marcador DISK).
// Fase a (primer arranque, --projects-folder P0):
//   1. con un tema abierto en Backing y reproduciendo, MOVER P0 -> P1 por la interfaz (Ajustes > Biblioteca > Cambiar carpeta > «Mover los temas aqui»);
//      se espera: estudio cerrado, app en la Biblioteca, mismos temas en P1 sin reiniciar, tema se abre y suena desde P1, media servida.
//   2. APUNTAR P1 -> P2 (P2 ya trae un tema): P1 conserva sus ficheros, la app lista los de P2.
//   3. con trabajo en cola (library.separate): relocate se rechaza con `work-in-progress` y la interfaz lo dice.
// Fase b (segundo lanzamiento SIN --projects-folder, mismo --support-dir): la carpeta activa sigue siendo P2 (perfil persistido).
// El dialogo nativo de elegir carpeta NO se puede manejar: se intercepta host.chooseFolder en el transporte (postMessage) y se contesta con la ruta
//   elegida; si la intercepcion no cabe, se llama a library.relocate directo (INFO ui.sin-interceptor). El resto es la interfaz real.
// Los ficheros en disco (viejo vacio, nuevo completo...) los mide el lanzador al ver las lineas `DISK <etiqueta> <ruta>` (b2-disk-verdict.py).
// Linea: `OK|FAIL|SKIP|INFO <nombre> <dato>` (el anfitrion antepone `eval| `); ultima: `DONE b2 <ok>/<total> (skip <n>)`.
const PHASE = globalThis.B2_PHASE ?? 'a';
const P = { p0: globalThis.B2_P0, p1: globalThis.B2_P1, p2: globalThis.B2_P2, p3: globalThis.B2_P3 };
const P2_COUNT = globalThis.B2_P2_COUNT ?? 1;
const PICK_HOOK = globalThis.B2_PICK_HOOK ?? '';   // gancho del anfitrion: solo sirve para la ruta que trae (una por lanzamiento)
const NOFETCH = !!globalThis.B2_NOFETCH;
const DISK_WAIT_MS = globalThis.B2_DISK_WAIT_MS ?? 6000;   // el lanzador mira el log cada 1 s y tarda en recorrer la carpeta
const QUEUE_MAX_MS = 25 * 60000;                           // espera a que acaben los trabajos que la app encola sola al arrancar / abrir Backing
const MOVE_MAX_MS = 20 * 60000;
const PLAY_MS = 1500;
const UI_WAIT_MS = 15000;
const STEM_CANDIDATES = ['guitar.wav', 'vocals.wav', 'drums.wav', 'bass.wav', 'other.wav'];
const RANGE_BYTES = 65535;

const sleep = ms => new Promise(r => setTimeout(r, ms));
const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
const txt = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
let ok = 0, bad = 0, skip = 0;
const OK = (n, d = '') => { ok++; log(`OK ${n} ${d}`.trimEnd()); return true; };
const FAIL = (n, d = '') => { bad++; log(`FAIL ${n} ${d}`.trimEnd()); return false; };
const SKIP = (n, d = '') => { skip++; log(`SKIP ${n} ${d}`.trimEnd()); return false; };
const INFO = (n, d = '') => log(`INFO ${n} ${d}`.trimEnd());
const check = (n, cond, d = '') => (cond ? OK(n, d) : FAIL(n, d));
const err = e => `${e?.code ? e.code + ': ' : ''}${e?.message ?? e}`;
const call = (m, p, t = 60000) => bridge.call(m, p ?? {}, { timeout: t });
const norm = s => String(s ?? '').replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();
const same = (a, b) => norm(a) === norm(b);
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
const state = () => import(new URL('state.js', document.baseURI).href);
const disk = async (label, path) => { log(`DISK ${label} ${path}`); await sleep(DISK_WAIT_MS); };

let mediaBase = '';
const mediaUrl = rel => (mediaBase.endsWith('/') ? mediaBase : mediaBase + '/') + rel.split('/').map(encodeURIComponent).join('/');
const listProjects = async () => (await call('library.list', {}, 60000)).projects ?? [];
const jobsLive = async () => (await call('jobs.list', {}, 30000).catch(() => ({ jobs: [] }))).jobs ?? [];
const busy = (list, jobs) => list.some(p => ['queued', 'running'].includes(p.separationState)) || jobs.some(x => ['queued', 'running'].includes(x.state));

async function waitQueueEmpty(label) {
  let list = await listProjects(), jobs = await jobsLive();
  if (!busy(list, jobs)) { INFO(`${label}.cola`, 'vacia'); return true; }
  const t = Date.now(); let beat = t;
  INFO(`${label}.espera-cola`, `trabajos: ${jobs.map(x => `${x.stage}/${x.state} ${x.title ?? ''} ${x.text ?? ''}`).join(' | ')}`);
  const r = await until(async () => {
    list = await listProjects(); jobs = await jobsLive();
    if (Date.now() - beat >= 60000) { beat = Date.now(); INFO(`${label}.latido`, `${Math.round((Date.now() - t) / 1000)} s: ${jobs.map(x => `${x.stage}/${x.state} ${x.text ?? ''}`).join(' | ')}`); }
    return !busy(list, jobs);
  }, QUEUE_MAX_MS, 3000);
  INFO(`${label}.espera-cola.fin`, `${Math.round((Date.now() - t) / 1000)} s ${r ? 'vacia' : 'TOPE'}`);
  return !!r;
}

// Un tema se sirve desde mediaBase: primero project.json y luego un stem (Range: solo la cabecera).
async function checkMedia(name, p) {
  if (NOFETCH) return SKIP(name, 'el anfitrion no deja leer media por fetch');
  const got = [];
  try {
    const r = await fetch(mediaUrl(`${p.folderName}/project.json`), { cache: 'no-store' });
    got.push(`project.json HTTP ${r.status}`);
    if (!r.ok) return FAIL(name, got.join('; '));
  } catch (e) { return FAIL(name, `project.json: ${err(e)}`); }
  for (const f of STEM_CANDIDATES) {
    try {
      const r = await fetch(mediaUrl(`${p.folderName}/stems/${f}`), { cache: 'no-store', headers: { Range: `bytes=0-${RANGE_BYTES}` } });
      if (r.status === 404) { got.push(`${f} 404`); continue; }
      if (!r.ok) return FAIL(name, `${got.join('; ')}; ${f} HTTP ${r.status}`);
      const buf = new Uint8Array(await r.arrayBuffer());
      const magic = String.fromCharCode(...buf.slice(0, 4));
      return check(name, magic === 'RIFF' || magic === 'RF64', `${got.join('; ')}; stems/${f} HTTP ${r.status} ${buf.length} B cabecera «${magic}»`);
    } catch (e) { return FAIL(name, `${got.join('; ')}; ${f}: ${err(e)}`); }
  }
  return FAIL(name, `${got.join('; ')}; ningun stem servido`);
}

// ---------------- interfaz ----------------
let picked = null, pickerCalls = 0, interceptor = false;
function installPicker() {
  const reply = (id, result) => {
    if (window.chrome?.webview) window.chrome.webview.dispatchEvent(new MessageEvent('message', { data: { id, result } }));
    else window.__tfReceive({ id, result });
  };
  const wrap = (obj, fnName, bindTo) => {
    const orig = obj[fnName].bind(bindTo);
    const w = s => {
      let m = null; try { m = JSON.parse(s); } catch { /* no es JSON */ }
      if (m?.method === 'host.chooseFolder' && picked != null) { pickerCalls++; const id = m.id, path = picked; setTimeout(() => reply(id, { path }), 50); return; }
      return orig(s);
    };
    try { obj[fnName] = w; } catch { return false; }
    return obj[fnName] === w;
  };
  try {
    if (window.chrome?.webview) interceptor = wrap(window.chrome.webview, 'postMessage', window.chrome.webview);
    else if (window.webkit?.messageHandlers?.tf) {   // WebKit (tf-webdev): el manejador se reconstruye en cada acceso; se sustituye la propiedad
      const real = window.webkit.messageHandlers.tf, fake = { postMessage: s => real.postMessage(s) };
      interceptor = wrap(fake, 'postMessage', fake);
      Object.defineProperty(window.webkit.messageHandlers, 'tf', { configurable: true, get: () => fake });
      interceptor = interceptor && window.webkit.messageHandlers.tf === fake;
    }
  } catch (e) { INFO('ui.interceptor-error', err(e)); }
  INFO('ui.interceptor', interceptor ? 'host.chooseFolder interceptado en el transporte (el dialogo nativo no se abre)' : 'NO instalado');
}
async function openSettings() {
  const st = await state();
  st.settingsTab.value = 'library'; st.go('settings');
  return !!(await until(() => $('.pathbox'), UI_WAIT_MS));
}
const pathboxText = () => txt($('.pathbox'));

// Mover/apuntar por la interfaz. Devuelve { via, ms, fractions, result, error, notice }.
async function relocateUI(path, mode, { expectFail = false } = {}) {
  const out = { via: 'ui', ms: 0, fractions: [], result: null, error: null, notice: '' };
  const offP = bridge.on('library.relocateProgress', p => out.fractions.push(p.fraction));
  let relocated = null; const offR = bridge.on('library.relocated', p => { relocated = { ...p, at: Date.now() }; });
  try {
    const shown = await openSettings();
    const pickBtn = btn(/^Cambiar carpeta$/);
    // Si el anfitrion lleva el gancho y es la ruta que devuelve, el RPC host.chooseFolder real contesta: no se intercepta.
    const viaHook = !!PICK_HOOK && same(PICK_HOOK, path);
    if (!shown || !pickBtn || (!interceptor && !viaHook) || globalThis.B2_FORCE_RPC) {
      out.via = 'rpc'; INFO('ui.sin-interceptor', `ajustes=${shown} boton=${!!pickBtn} interceptor=${interceptor}: se llama a library.relocate directo`);
      const t = Date.now();
      try { out.result = await call('library.relocate', { path, mode }, MOVE_MAX_MS); } catch (e) { out.error = e; }
      out.ms = Date.now() - t; return out;
    }
    picked = viaHook ? null : path;
    out.pick = viaHook ? 'gancho' : 'interceptor';
    const t = Date.now();
    pickBtn.click();
    const modal = await until(() => $$('.modal, [role=dialog]').find(m => /mover los temas/i.test(txt(m))), UI_WAIT_MS);
    out.modal = modal ? txt(modal) : '';
    INFO('ui.selector', `${out.pick} para ${path}`);
    if (!modal) INFO('ui.sin-modal', `pickerCalls=${pickerCalls} avisos=[${$$('.notices .notice').map(txt).join(' | ')}] pathbox=«${pathboxText()}» boton-deshabilitado=${pickBtn.disabled}`);
    if (!modal) { out.error = new Error('no salio la pregunta mover/apuntar'); out.via = 'ui-sin-modal'; return out; }
    const choose = [...modal.querySelectorAll('button')].find(b => (mode === 'move' ? /^Mover los temas/ : /^Solo apuntar/).test(txt(b)));
    if (!choose) { out.error = new Error('falta el boton del modo'); return out; }
    const t1 = Date.now();
    choose.click();
    if (expectFail) {
      out.notice = await until(() => { const n = $$('.notices .notice.error').map(txt).join(' | '); return n || null; }, 15000) ?? '';
      out.ms = Date.now() - t1; return out;
    }
    // El progreso se ve tambien en la interfaz: «Moviendo NN %».
    let sawDom = '';
    const done = await until(() => { const d = txt($$('.srow .val').find(e => /Moviendo/.test(txt(e)))); if (d) sawDom = d; return relocated; }, MOVE_MAX_MS, 50);
    out.sawDom = sawDom; out.ms = (done?.at ?? Date.now()) - t1; out.msFromPick = (done?.at ?? Date.now()) - t;
    out.result = done; if (!done) out.error = new Error('sin evento library.relocated');
    return out;
  } finally { offP(); offR(); picked = null; }
}

// ---------------- fases ----------------
async function main() {
  const info = await call('app.info');
  mediaBase = info.mediaBase ?? '';
  INFO('app', `platform=${info.platform} version=${info.version} carpeta=${info.projectsFolder} fase=${PHASE}`);
  if (PHASE === 'b') return phaseB(info);
  if (!check('setup.carpeta-inicial', same(info.projectsFolder, P.p0), `activa «${info.projectsFolder}» esperada «${P.p0}»`)) return;
  await waitQueueEmpty('setup');
  const list0 = await listProjects();
  const done0 = list0.filter(p => p.separationState === 'done' && (p.stemCount ?? 0) > 0);
  INFO('setup.temas', list0.map(p => `«${p.title}» ${p.folderName} sep=${p.separationState} stems=${p.stemCount}`).join(' | ') || '(ninguno)');
  if (!check('setup.temas', list0.length >= 1 && done0.length >= 1, `${list0.length} temas, ${done0.length} separados`)) return;
  const proj = done0.find(p => p.title.includes('El roce')) ?? done0[0];
  installPicker();

  // ===== 1+2: mover con un tema abierto y reproduciendo =====
  const st = await state();
  st.openBacking(proj.id);
  const ready = await until(() => $('.screen.backing .mix-chans'), 20000, 100);
  check('mover.backing-abierto', !!ready, `«${proj.title}» abierto en Backing`);
  let before = null;
  try { before = await call('study.snapshot', {}, 30000); } catch (e) { FAIL('mover.estudio-abierto', err(e)); }
  if (before) {
    check('mover.estudio-abierto', before.projectId?.toLowerCase() === proj.id.toLowerCase(), `snapshot de ${before.projectId}`);
    try { const tr = await call('study.play', {}); INFO('mover.play-previo', `playing=${tr.playing} position=${tr.position?.toFixed?.(2)} audioError=${tr.audioError ?? ''}`); } catch (e) { INFO('mover.play-previo', `fallo ${err(e)}`); }
    await sleep(PLAY_MS);
  }
  await waitQueueEmpty('antes-de-mover');   // abrir Backing puede encolar el paso de guitarras si la huella no casa
  await disk('pre', P.p0);
  const ids0 = list0.map(p => p.id).sort();
  const mv = await relocateUI(P.p1, 'move');
  if (mv.error) { FAIL('mover.relocate', `${mv.via}: ${err(mv.error)}`); return; }
  OK('mover.relocate', `via ${mv.via}, ${(mv.ms / 1000).toFixed(2)} s desde «Mover» (${mv.msFromPick != null ? (mv.msFromPick / 1000).toFixed(2) : '-'} s desde «Cambiar carpeta»), resultado ${JSON.stringify(mv.result)}`);
  INFO('mover.progreso', `${mv.fractions.length} eventos library.relocateProgress, primero ${mv.fractions[0]?.toFixed(3)}, ultimo ${mv.fractions.at(-1)?.toFixed(3)}, creciente=${mv.fractions.every((f, i, a) => i === 0 || f >= a[i - 1])}; en la interfaz: «${mv.sawDom || 'no se vio'}»`);
  if (mv.via === 'ui') check('mover.modal-ruta', (mv.modal ?? '').includes(P.p1) || norm(mv.modal ?? '').includes(norm(P.p1)), (mv.modal ?? '').slice(0, 160));
  if (mv.via === 'ui') check('mover.progreso-visto', mv.fractions.length > 0 || !!mv.sawDom, `${mv.fractions.length} eventos, interfaz «${mv.sawDom}»`);
  if (mv.via === 'ui') check('mover.pantalla-biblioteca', st.screen.value === 'library', `screen=${st.screen.value}`); else SKIP('mover.pantalla-biblioteca', 'via rpc: go(library) lo hace la interfaz');
  try { const s = await call('study.snapshot', {}, 15000); FAIL('mover.estudio-cerrado', `study.snapshot sigue respondiendo (${s?.projectId})`); }
  catch (e) { OK('mover.estudio-cerrado', `study.snapshot: ${err(e)}`); }
  await disk('m1-old', P.p0);
  await disk('m1-new', P.p1);
  const info1 = await call('app.info'), set1 = await call('settings.get');
  check('mover.carpeta-activa', same(info1.projectsFolder, P.p1), `app.info.projectsFolder=${info1.projectsFolder}`);
  check('mover.perfil', same(set1.projectsFolder, P.p1) && same(set1.activeProjectsFolder, P.p1), `settings.get: ${set1.projectsFolder} / activa ${set1.activeProjectsFolder}`);
  check('mover.sin-reiniciar', same(set1.projectsFolder, set1.activeProjectsFolder), 'no pide reinicio (guardada == activa)');
  const list1 = await listProjects();
  check('mover.biblioteca-lista', JSON.stringify(list1.map(p => p.id).sort()) === JSON.stringify(ids0), `${list1.length} temas tras mover, antes ${ids0.length}: ${list1.map(p => p.title).join(' | ')}`);
  await st.go('library'); await sleep(800);
  const bodyText = txt($('.screen'));
  const missing = list1.filter(p => !bodyText.includes(p.title));
  check('mover.interfaz-lista', missing.length === 0, missing.length ? `no se ven en pantalla: ${missing.map(p => p.title).join(' | ')} (lista virtual o aun cargando)` : `los ${list1.length} titulos estan en la Biblioteca`);
  const p1proj = list1.find(p => p.id === proj.id);
  if (p1proj) {
    await checkMedia('mover.media', p1proj);
    st.openBacking(p1proj.id);
    const r2 = await until(() => $('.screen.backing .mix-chans'), 20000, 100);
    let s2 = null; try { s2 = await call('study.snapshot', {}, 30000); } catch (e) { INFO('mover.reabrir', err(e)); }
    check('mover.reabrir', !!r2 && s2?.projectId?.toLowerCase() === p1proj.id.toLowerCase() && !s2?.loadError, `Backing ${r2 ? 'abierto' : 'NO abierto'}, snapshot ${s2?.projectId}, loadError=${s2?.loadError ?? ''}`);
    if (s2) {
      try {
        const t0 = (await call('study.seek', { seconds: 5 })).position;
        const tr = await call('study.play', {}); await sleep(PLAY_MS);
        const tr2 = await call('study.pause', {});
        check('mover.reproduce', tr.playing === true && tr2.position > t0 + 0.2 && !tr2.audioError, `posicion ${t0.toFixed(2)} -> ${tr2.position.toFixed(2)} s tras ${PLAY_MS} ms; audioError=${tr2.audioError ?? ''}`);
      } catch (e) { FAIL('mover.reproduce', err(e)); }
    }
    await call('study.close', {}).catch(() => {}); st.go('library');
  } else FAIL('mover.reabrir', 'el tema ya no esta en la lista');

  // ===== 3: apuntar =====
  const ap = await relocateUI(P.p2, 'point');
  if (ap.error) FAIL('apuntar.relocate', `${ap.via}: ${err(ap.error)}`);
  else {
    OK('apuntar.relocate', `via ${ap.via}, ${(ap.ms / 1000).toFixed(2)} s, resultado ${JSON.stringify(ap.result)}`);
    check('apuntar.sin-progreso', ap.fractions.length <= 1, `${ap.fractions.length} eventos de progreso (solo apunta, no copia)`);
    await disk('p-old', P.p1);
    await disk('p-new', P.p2);
    const info2 = await call('app.info');
    check('apuntar.carpeta-activa', same(info2.projectsFolder, P.p2), `app.info.projectsFolder=${info2.projectsFolder}`);
    const list2 = await listProjects();
    check('apuntar.lista-la-nueva', list2.length === P2_COUNT,`${list2.length} temas (esperados ${P2_COUNT}): ${list2.map(p => p.title).join(' | ')}`);
    await st.go('library'); await sleep(500);
    check('apuntar.interfaz', list2.every(p => txt($('.screen')).includes(p.title)), 'los temas de la carpeta apuntada estan en la Biblioteca');
    if (list2[0]) await checkMedia('apuntar.media', list2[0]);
    if (await openSettings()) check('apuntar.pathbox', same(pathboxText(), P.p2), `«${pathboxText()}»`);
  }

  // ===== 4: trabajo en cola =====
  const listW = await listProjects();
  const target = listW.find(p => p.separationState === 'done') ?? listW[0];
  let queued = false;
  if (target) {
    try { await call('library.separate', { id: target.id }); queued = !!(await until(async () => (await jobsLive()).some(x => ['queued', 'running'].includes(x.state)), 8000, 200)); }
    catch (e) { INFO('wip.separate', err(e)); }
  }
  if (!queued) SKIP('wip.rechazo', `no se pudo dejar un trabajo en cola (tema ${target?.title ?? 'ninguno'})`);
  else {
    INFO('wip.cola', (await jobsLive()).map(x => `${x.stage}/${x.state} ${x.title ?? ''}`).join(' | '));
    try { await call('library.relocate', { path: P.p3, mode: 'move' }, 30000); FAIL('wip.rpc', 'library.relocate NO se rechazo con trabajo en cola'); }
    catch (e) { check('wip.rpc', e.code === 'work-in-progress', `library.relocate con cola -> ${err(e)}`); }
    const w = await relocateUI(P.p3, 'move', { expectFail: true });
    if (w.via === 'ui') check('wip.interfaz', /Hay trabajo en curso/i.test(w.notice), `aviso en pantalla: «${w.notice}»`);
    else check('wip.interfaz', w.error?.code === 'work-in-progress', `via ${w.via}: ${err(w.error)}`);
    const infoW = await call('app.info');
    check('wip.carpeta-intacta', same(infoW.projectsFolder, P.p2), `app.info.projectsFolder=${infoW.projectsFolder}`);
    await disk('wip-new', P.p3);
    // Se cancela el trabajo para dejar la copia en paz.
    for (const j of (await jobsLive())) await call('jobs.cancel', { id: j.id }).catch(e => INFO('wip.cancel', err(e)));
    await waitQueueEmpty('wip-fin');
  }
}

async function phaseB(info) {
  // Segundo lanzamiento: sin --projects-folder; la carpeta sale de profile.json del --support-dir.
  check('reinicio.carpeta', same(info.projectsFolder, P.p2), `app.info.projectsFolder=${info.projectsFolder} esperada ${P.p2}`);
  const s = await call('settings.get');
  check('reinicio.perfil', same(s.projectsFolder, P.p2) && same(s.activeProjectsFolder, P.p2), `settings.get: ${s.projectsFolder} / activa ${s.activeProjectsFolder}`);
  await waitQueueEmpty('reinicio');
  const list = await listProjects();
  check('reinicio.lista', list.length === P2_COUNT, `${list.length} temas (esperados ${P2_COUNT}): ${list.map(p => p.title).join(' | ')}`);
  if (await openSettings()) check('reinicio.pathbox', same(pathboxText(), P.p2), `«${pathboxText()}»`);
  if (list[0]) await checkMedia('reinicio.media', list[0]);
  await disk('r-p0', P.p0);
  await disk('r-p1', P.p1);
}

try { await main(); } catch (e) { FAIL('excepcion', `${err(e)} ${(e?.stack ?? '').split('\n').slice(0, 3).join(' / ')}`); }
log(`DONE b2 ${ok}/${ok + bad} (skip ${skip})`);
