// B6: cierre ordenado con descarga en marcha. Cuerpo de funcion async con (bridge, log). Globales: B6_PHASE 'a'|'b', B6_JOBID (fase b).
// Fase a: link.import de un video de YouTube (sin Spotify) y espera a que el lanzador cierre la ventana. Fase b: tras reabrir, mira jobs.list.
// Lineas: OK|FAIL|SKIP|INFO <nombre> <dato>; ultima: DONE b6part <fase> n/m (skip k).
const PHASE = globalThis.B6_PHASE ?? 'a';
const URL_TEST = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
const sleep = ms => new Promise(r => setTimeout(r, ms));
let ok = 0, bad = 0;
const check = (n, c, d = '') => { if (c) { ok++; log(`OK ${n} ${d}`.trimEnd()); } else { bad++; log(`FAIL ${n} ${d}`.trimEnd()); } };
const call = (m, p, t = 30000) => bridge.call(m, p ?? {}, { timeout: t });
if (PHASE === 'a') {
  try {
    const r = await call('link.import', { url: URL_TEST });
    check('b6.import-iniciado', !!r?.jobId, `jobId=${r?.jobId}`);
    log(`INFO jobid ${r?.jobId}`);
  } catch (e) { check('b6.import-iniciado', false, `${e?.code ?? ''} ${e?.message ?? e}`); }
  log('INFO READY b6');
  await sleep(240000);   // el lanzador cierra la ventana (WM_CLOSE) cuando ve yt-dlp/ffmpeg vivo
} else {
  const id = globalThis.B6_JOBID ?? '';
  await sleep(20000);   // recuperacion de arranque
  const jobs = (await call('jobs.list').catch(() => ({ jobs: [] }))).jobs ?? [];
  for (const j of jobs) log(`INFO job ${j.id} stage=${j.stage} state=${j.state} error=${j.error ?? ''}`);
  const live = jobs.filter(j => j.state === 'running' || j.state === 'queued');
  check('b6.ningun-trabajo-en-marcha', live.length === 0, `en marcha=${live.length} de ${jobs.length}`);
  const mine = jobs.find(j => j.id === id);
  log(`INFO b6.trabajo-original ${mine ? 'state=' + mine.state : 'no figura en jobs.list (sin persistir)'}`);
  check('b6.trabajo-original-no-en-marcha', !mine || (mine.state !== 'running' && mine.state !== 'queued'), mine ? mine.state : 'ausente');
}
log(`DONE b6part ${PHASE} ${ok}/${ok + bad} (skip 0)`);
