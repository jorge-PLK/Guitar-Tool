// Simulador del núcleo para el modo mock: biblioteca en memoria (fixtures de mock/) y cola de trabajos con progreso.
// Query: ?link=candidatos|youtube|repetido|posible-repetido|resolviendo|error|descargando|m4a|fallo (link.resolve/import),
// ?state=empty|nofolder, ?dup=1 (import.file devuelve duplicado), ?fail=trash (library.trash falla).

const wait = ms => new Promise(r => setTimeout(r, ms));
const err = (code, message) => Object.assign(new Error(message), { code });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class MockSim {
  constructor(emit, params) {
    this.emit = emit;
    this.params = params;
    this.jobs = new Map();       // id -> Job vivo
    this.queue = [];             // ids de temas en cola de separación
    this.busy = false;
    this.importSeq = 0;
    this.linkSeq = 0;
    this.resolveWaiter = null;
    this.ready = this.#init();
  }

  async #fetch(name) {
    const r = await fetch(new URL(`mock/${name}.json`, document.baseURI));
    if (!r.ok) throw err('unknown-method', `sin fixture ${name}`);
    return r.json();
  }

  async #init() {
    this.info = await this.#fetch('app.info');
    this.projects = (await this.#fetch('library.list')).projects;
    this.skipped = (await this.#fetch('library.list')).skipped;
    this.details = {};
    for (const p of this.projects) {
      try { this.details[p.id] = await this.#fetch(`library.project.${p.id}`); } catch { /* se genera al pedirlo */ }
    }
    // Trabajos vivos de los fixtures: el que "separa" arranca a mitad; los demás esperan.
    for (const p of this.projects) {
      if (p.separationState === 'running') this.#enqueue(p.id, 0.35);
      else if (p.separationState === 'queued') this.#enqueue(p.id, 0);
    }
  }

  #emitJob(j) { this.emit('jobs.progress', { ...j }); }
  #changed() { this.emit('library.changed', {}); }
  #find(id) {
    if (!UUID.test(id ?? '')) throw err('bad-params', 'id no válido');
    const p = this.projects.find(x => x.id === id);
    if (!p) throw err('not-found', 'No existe ese tema');
    return p;
  }

  #enqueue(id, start = 0) {
    const p = this.projects.find(x => x.id === id);
    if (!p || this.jobs.has(id)) return;
    p.separationState = 'queued';
    const job = { id, title: p.folderName, stage: 'separation', state: 'queued', fraction: null, text: 'En cola', error: null, start };
    this.jobs.set(id, job);
    this.queue.push(id);
    this.#emitJob(job);
    this.#pump();
  }

  async #pump() {
    if (this.busy) return;
    this.busy = true;
    while (this.queue.length) {
      const id = this.queue.shift();
      const job = this.jobs.get(id);
      const p = this.projects.find(x => x.id === id);
      if (!job || !p) continue;
      job.state = 'running'; job.fraction = job.start; p.separationState = 'running';
      while (this.jobs.get(id) === job && job.fraction < 1) {
        job.text = `Separando… ${Math.round(job.fraction * 100)} %`;
        this.#emitJob(job); this.#changed();
        await wait(400);
        job.fraction = Math.min(1, job.fraction + 0.04);
      }
      if (this.jobs.get(id) !== job) continue;   // cancelado
      job.stage = 'analysis'; job.fraction = null; job.text = 'Analizando…'; this.#emitJob(job);
      await wait(1500);
      if (this.jobs.get(id) !== job) continue;
      this.jobs.delete(id);
      p.separationState = 'done'; p.stemCount = 4; p.hasAnalysis = true;
      this.#emitJob({ ...job, state: 'done', fraction: 1, text: '' });
      this.#changed();
    }
    this.busy = false;
  }

  async #import(path) {
    if (this.params.get('dup') === '1') return { id: this.projects[0].id, duplicate: true };
    const name = path.split(/[\\/]/).pop().replace(/\.[^.]+$/, '');
    const id = `import-${++this.importSeq}`;
    const job = { id, title: name, stage: 'import', state: 'running', fraction: 0, text: 'Importando… 0 %', error: null };
    this.jobs.set(id, job);
    for (let f = 0; f < 1; f += 0.1) {
      job.fraction = f; job.text = `Importando… ${Math.round(f * 100)} %`;
      this.#emitJob(job); await wait(250);
    }
    this.jobs.delete(id);
    const n = 100 + this.importSeq;
    const uid = `${n.toString(16).padStart(8, '0')}-0000-4000-8000-${n.toString(16).padStart(12, '0')}`;
    this.projects.push({ id: uid, title: name, artist: null, folderName: name, duration: 180, sampleRate: 44100, cover: null,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), separationState: 'none', stemCount: 0,
      takeCount: 0, rigCount: 0, hasAnalysis: false, origin: null, guitars: [] });
    this.projects.sort((a, b) => a.title.localeCompare(b.title, 'es'));
    this.#emitJob({ ...job, state: 'done', fraction: 1, text: '' });
    this.#enqueue(uid);
    this.#changed();
    return { id: uid, duplicate: false };
  }

  // Enlaces (8.3b): el caso sale de ?link=, o de la URL (spotify -> candidatos, youtube -> youtube).
  async #resolve(url) {
    if (!url || !String(url).trim()) throw err('bad-params', 'Enlace vacío');
    this.resolveWaiter?.(); this.resolveWaiter = null;
    const spotify = /spotify/i.test(url);
    const kase = this.params.get('link') ?? (spotify ? 'candidatos' : 'youtube');
    await wait(300);
    if (kase === 'resolviendo') {
      await new Promise(res => { this.resolveWaiter = res; });
      throw err('cancelled', 'Cancelado\n');
    }
    if (kase === 'error') {
      throw err('extractor-broken', 'yt-dlp puede estar desactualizado (versión 2026.10.26)\nERROR: [youtube] 4CJwzwOIPAY: Unable to extract nsig function code');
    }
    if (kase === 'unsupported') throw err('unsupported-link', 'Enlace no admitido\nSe admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no.');
    const ex = this.projects[0];
    if (kase === 'repetido') {
      return { link: 'spotify', pastedURL: url, title: 'La luna me sabe a poco', artist: 'Marea', album: null, duration: 253, thumbnail: null,
        existing: { id: ex.id, title: ex.title, artist: ex.artist }, possibleDuplicate: null, noCloseCandidate: false, candidates: [] };
    }
    const yt = (id, t, a, d, extra = {}) => ({ id, title: t, artist: a, duration: d, thumbnail: `https://i.ytimg.com/vi/${id}/mqdefault.jpg`, source: 'youtube',
      url: `https://www.youtube.com/watch?v=${id}`, isClose: false, isLive: false, difference: null, inLibrary: null, ...extra });
    if (!spotify) {
      return { link: 'youtube', pastedURL: url, title: 'La luna me sabe a poco', artist: 'Marea', album: null, duration: 253,
        thumbnail: 'https://i.ytimg.com/vi/4CJwzwOIPAY/mqdefault.jpg', existing: null, possibleDuplicate: null, noCloseCandidate: false,
        candidates: [yt('4CJwzwOIPAY', 'La luna me sabe a poco', 'Marea', 253)] };
    }
    return { link: 'spotify', pastedURL: url, title: 'La luna me sabe a poco', artist: 'Marea', album: 'Besos de Perro', duration: 253, thumbnail: null,
      existing: null,
      possibleDuplicate: kase === 'posible-repetido' ? { id: ex.id, title: 'La luna me sabe a poco', artist: 'Marea' } : null,
      noCloseCandidate: false,
      candidates: [
        yt('4CJwzwOIPAY', 'La luna me sabe a poco', 'Marea', 252, { isClose: true, difference: -1 }),
        yt('bbbbbbbbbbb', 'Marea - La luna me sabe a poco (directo Madrid)', 'Marea Oficial', 255, { isClose: true, isLive: true, difference: 2 }),
        yt('ccccccccccc', 'La luna me sabe a poco - Marea', 'Rock en español', 261, { difference: 8, inLibrary: { id: ex.id, title: ex.title, artist: ex.artist } })] };
  }

  // Búsqueda en Spotify (L-F2): ?search=vacio|fallo|credenciales.
  async #search(query) {
    if (!query || !String(query).trim()) throw err('bad-params', '«query» está vacía.');
    await wait(400);
    const kase = this.params.get('search');
    if (kase === 'fallo') throw err('spotify-offline', 'Sin conexión con Spotify');
    if (kase === 'credenciales') throw err('spotify-missing-credentials', 'Búsqueda en Spotify no disponible: falta la clave (.env)');
    const q = String(query).trim();
    if (kase === 'vacio' || /zzz/i.test(q)) return { query: q, tracks: [] };
    const t = (id, name, artists, album, year, durationText) => ({ id, name, artists, album, year, durationText, imageURL: null,
      trackURL: `https://open.spotify.com/track/${id}`, appURL: `spotify:track:${id}` });
    return { query: q, tracks: [
      t('3demoDemoDemoDemoDemox', 'La luna me sabe a poco', ['Marea'], 'Besos de Perro', 2004, '4:13'),
      t('3demoDemoDemoDemoDemoy', 'La luna me sabe a poco (En directo)', ['Marea', 'Invitado'], 'Directo', null, '4:40'),
      t('3demoDemoDemoDemoDemoz', 'Luna', ['Marea'], 'Mentiras Sinceras', 2008, '3:21')] };
  }

  // «Pega un enlace de YouTube» (L-F3): ?manual=error falla como un enlace no admitido.
  async #addManual(url) {
    const cur = this.lastRes;
    if (!cur || !cur.candidates.length && !cur.title) throw err('unsupported-link', 'Enlace no admitido');
    await wait(300);
    const m = /[?&]v=([\w-]{11})|youtu\.be\/([\w-]{11})/.exec(url ?? '');
    if (!m || this.params.get('manual') === 'error') throw err('unsupported-link', `Enlace no admitido\nSe admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no.`);
    const id = m[1] ?? m[2];
    const c = { id, title: 'La luna me sabe a poco (vídeo pegado)', artist: 'Marea', duration: 253, thumbnail: `https://i.ytimg.com/vi/${id}/mqdefault.jpg`,
      source: 'youtube', url: `https://www.youtube.com/watch?v=${id}`, isClose: true, isLive: false, difference: 0, inLibrary: null };
    cur.candidates = [c, ...cur.candidates.filter(x => x.id !== id)];
    return { added: id, selectable: true, resolution: cur };
  }

  async #linkImport(p) {
    if (!p.candidateId && !p.url) throw err('bad-params', 'Falta el candidato');
    const id = `link-${++this.linkSeq}`;
    const kase = this.params.get('link');
    const title = p.title || 'La luna me sabe a poco';
    const job = { id, title: `${p.artist ? p.artist + ' - ' : ''}${title}`, stage: 'download', state: 'running', fraction: 0, text: 'Descargando audio… 0 %', error: null };
    this.jobs.set(id, job);
    this.#emitJob(job);
    (async () => {
      if (kase === 'descargando') { job.fraction = 0.42; job.text = 'Descargando audio… 42 %'; this.#emitJob(job); return; }
      if (kase === 'm4a') { job.fraction = null; job.text = 'Convirtiendo a WAV…'; this.#emitJob(job); return; }
      for (let f = 0; f <= 1 && this.jobs.get(id) === job; f += 0.1) {
        job.fraction = f; job.text = `Descargando audio… ${Math.round(f * 100)} %`; this.#emitJob(job); await wait(300);
      }
      if (this.jobs.get(id) !== job) return;
      if (kase === 'fallo') {
        this.jobs.delete(id);
        this.#emitJob({ ...job, state: 'failed', error: 'ERROR: [youtube] Unable to extract nsig function code' });
        this.emit('link.finished', { jobId: id, id: null, duplicate: false, notices: [], error: { code: 'extractor-broken',
          message: 'yt-dlp puede estar desactualizado (versión 2026.10.26)\nERROR: [youtube] 4CJwzwOIPAY: Unable to extract nsig function code' } });
        return;
      }
      job.fraction = null; job.text = 'Convirtiendo a WAV…'; this.#emitJob(job); await wait(600);
      job.stage = 'import';
      for (let f = 0; f < 1; f += 0.25) { job.fraction = f; job.text = `Importando… ${Math.round(f * 100)} %`; this.#emitJob(job); await wait(200); }
      this.jobs.delete(id);
      const n = 200 + this.linkSeq;
      const uid = `${n.toString(16).padStart(8, '0')}-0000-4000-8000-${n.toString(16).padStart(12, '0')}`;
      this.projects.push({ id: uid, title, artist: p.artist || null, folderName: job.title, duration: 253, sampleRate: 44100, cover: null,
        createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), separationState: 'none', stemCount: 0, takeCount: 0,
        rigCount: 0, hasAnalysis: false, origin: 'youtube', guitars: [] });
      this.projects.sort((a, b) => a.title.localeCompare(b.title, 'es'));
      this.#emitJob({ ...job, state: 'done', fraction: 1, text: '' });
      this.#enqueue(uid);
      this.emit('link.finished', { jobId: id, id: uid, duplicate: false, notices: ['La descarga cayó a M4A y se convirtió a WAV.'], error: null });
      this.#changed();
    })();
    return { jobId: id };
  }

  async handle(method, p = {}) {
    await this.ready;
    switch (method) {
      case 'app.info': {
        const launch = { ...this.info.launch };
        if (this.params.get('screen')) launch.screen = this.params.get('screen');
        if (this.params.get('project')) launch.project = this.params.get('project');
        return { ...this.info, launch };
      }
      case 'library.list':
        if (this.params.get('state') === 'nofolder') throw err('no-projects-folder', 'No hay carpeta de proyectos');
        if (this.params.get('state') === 'empty') return { projects: [], skipped: [] };
        return { projects: this.projects.map(x => ({ ...x, separationState: x.separationState })), skipped: this.skipped };
      case 'library.project': {
        const sum = this.#find(p.id);
        const base = this.details[sum.id] ?? { separationError: null, stems: [], parts: [], videoCount: 0 };
        return { ...base, ...sum };
      }
      case 'library.reveal': this.#find(p.id); return { revealed: true };
      case 'jobs.list': return { jobs: [...this.jobs.values()].map(({ start, ...j }) => j) };
      case 'jobs.cancel': {
        const j = this.jobs.get(p.id);
        if (!j || j.stage !== 'separation') return { cancelled: false };
        this.jobs.delete(p.id);
        this.queue = this.queue.filter(x => x !== p.id);
        this.#find(p.id).separationState = 'none';
        this.#emitJob({ ...j, state: 'cancelled', text: '' });
        this.#changed();
        return { cancelled: true };
      }
      case 'library.separate': this.#find(p.id); this.#enqueue(p.id); return { queued: true };
      case 'library.rename': {
        const sum = this.#find(p.id);
        const title = (p.title ?? '').trim();
        if (!title) throw err('empty-title', 'El título no puede estar vacío');
        sum.title = title; sum.artist = (p.artist ?? '').trim() || null;
        this.projects.sort((a, b) => a.title.localeCompare(b.title, 'es'));
        this.#changed();
        return { id: sum.id, title: sum.title, artist: sum.artist };
      }
      case 'library.trash': case 'library.delete': {
        this.#find(p.id);
        if (this.params.get('fail') === 'trash' && method === 'library.trash') {
          throw err('trash-failed', 'No se pudo mover a la Papelera (el disco no tiene Papelera). No se ha borrado nada; te queda «Eliminar del disco».');
        }
        this.jobs.delete(p.id);
        this.queue = this.queue.filter(x => x !== p.id);
        this.projects = this.projects.filter(x => x.id !== p.id);
        this.#changed();
        return { removed: true };
      }
      case 'host.pickAudioFile': await wait(150); return { path: 'C:\\Música\\Demo importado.flac' };
      case 'host.pickProjectsFolder': await wait(150); return { path: 'C:\\Users\\jorge\\ToneForge', restartRequired: true };
      case 'import.file': return this.#import(p.path);
      case 'link.resolve': { const r = await this.#resolve(p.url); this.lastRes = r; return r; }
      case 'link.search': return this.#search(p.query);
      case 'link.addManual': return this.#addManual(p.url);
      case 'host.pickAudioFiles': await wait(150); return { paths: this.params.get('pick') === 'uno' ? ['C:\\Música\\Demo importado.flac']
        : ['C:\\Música\\Demo importado.flac', 'C:\\Música\\Otro tema.mp3', 'C:\\Música\\Notas.txt'] };
      case 'link.cancel': {
        if (p.jobId) {
          const j = this.jobs.get(p.jobId);
          if (!j) return { cancelled: false };
          this.jobs.delete(p.jobId);
          this.#emitJob({ ...j, state: 'cancelled', text: '' });
          this.emit('link.finished', { jobId: p.jobId, id: null, duplicate: false, notices: [], error: { code: 'cancelled', message: 'Cancelado\n' } });
          return { cancelled: true };
        }
        const had = !!this.resolveWaiter; this.resolveWaiter?.(); this.resolveWaiter = null; return { cancelled: had };
      }
      case 'link.import': return this.#linkImport(p);
      case 'tools.updateYtDlp': await wait(800); return { version: '2026.11.10', origin: 'updated', alreadyLatest: this.params.get('latest') === '1' };
      default: throw err('unknown-method', `método desconocido: ${method}`);
    }
  }
}
