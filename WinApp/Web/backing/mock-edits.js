// Simulador de las ediciones de 8.6c-B para `?mock=1`: análisis, guitarras y secciones (contrato 8.5b).
// Lo llama mock-study.js con el estado del tema abierto. Variantes: `?study=` (ver mock-study.js) y `?process=processing|failed`.
import { mockEmit, BridgeError } from '../bridge.js';

const MIN_SECTION = 0.5;
const clone = o => JSON.parse(JSON.stringify(o));
const params = new URLSearchParams(location.search);
let saved = null;             // secciones guardadas (las de `cur.sections` son las de edición)
let guitars = null;

function init(cur) {
  if (saved && cur.__b === true) return;
  cur.__b = true;
  saved = clone(cur.sections ?? []);
  const proc = params.get('process');
  guitars = {
    stereoSplit: false, usesSeparatedGuitars: !!cur.usesSeparatedGuitars,
    names: { rhythm: 'Guitarra rítmica', left: 'Guitarra izq.', right: 'Guitarra der.', lead: 'Guitarra solista' },
    process: proc === 'processing' || proc === 'failed' ? proc : 'idle', error: proc === 'failed' ? 'No se pudieron separar las guitarras (modelo no disponible)' : null,
    saveError: null,
  };
  for (const c of cur.transport?.channels ?? []) if (c.guitarRole) guitars.names[c.guitarRole] = c.name;
}

function state(ctx, added = null) {
  const { cur, tr, clone: cl } = ctx;
  return {
    analysis: cl(cur.analysis), chordOverrides: cl(cur.chordOverrides ?? []), sections: cl(cur.sections ?? []),
    unappliedSections: JSON.stringify(cur.sections) !== JSON.stringify(saved), loops: cl(cur.loops ?? []),
    guitars: cl(guitars), added, transport: cl(tr),
  };
}

const bad = m => { throw new BridgeError('bad-params', m); };
const find = (cur, id) => cur.sections.find(s => s.id === id) ?? (() => { throw new BridgeError('not-found', 'No existe esa sección'); })();

export async function mockEditsB(method, p, ctx) {
  const { cur, tr, emitState } = ctx;
  init(cur);
  switch (method) {
    case 'study.snapshot': {
      const { transport: _t, ...rest } = cur;
      return { ...clone(rest), unappliedSections: JSON.stringify(cur.sections) !== JSON.stringify(saved), guitars: clone(guitars), transport: clone(tr) };
    }
    case 'study.analyze': {
      if (params.get('study') === 'unseparated') throw new BridgeError('not-separated', 'El tema no tiene la separación terminada: no se puede analizar.');
      if (cur.analysis.state === 'ready') return state(ctx);
      cur.analysis = { ...cur.analysis, state: 'analyzing', error: null };
      mockEmit('study.analysis', { state: 'analyzing', error: null });
      setTimeout(async () => {
        const fx = await (await fetch(new URL('mock/study.open.json', document.baseURI))).json();
        Object.assign(cur, { analysis: fx.analysis, sections: fx.sections });
        saved = clone(cur.sections);
        mockEmit('study.analysis', { state: 'ready', error: null });
      }, 1800);
      return state(ctx);
    }
    case 'study.setGuitarStereo': {
      guitars.stereoSplit = !!p.on;
      guitars.process = 'processing';
      setTimeout(() => { guitars.process = 'idle'; emitState(); }, 2500);
      return state(ctx);
    }
    case 'study.renameGuitar': {
      if (!['rhythm', 'left', 'right', 'lead'].includes(p.role)) bad('role desconocido');
      const def = { rhythm: 'Guitarra rítmica', left: 'Guitarra izq.', right: 'Guitarra der.', lead: 'Guitarra solista' }[p.role];
      guitars.names[p.role] = p.name.trim() || def;
      for (const c of tr.channels) if (c.guitarRole === p.role) c.name = guitars.names[p.role];
      emitState();
      return state(ctx);
    }
    case 'study.markSection': {
      if (!(p.end > p.start) || p.start < 0 || p.end > tr.duration) bad('tramo no válido');
      if (cur.sections.some(s => p.start >= s.start && p.start < s.end) || p.end - p.start < MIN_SECTION) {
        throw new BridgeError('section-not-created', 'La sección no se puede crear ahí');
      }
      const id = crypto.randomUUID();
      cur.sections.push({ id, name: p.solo ? 'Solo' : `Sección ${cur.sections.length + 1}`, start: p.start, end: p.end, solo: !!p.solo, color: null,
        paletteIndex: p.solo ? null : cur.sections.length % 7 });
      cur.sections.sort((a, b) => a.start - b.start);
      return state(ctx, id);
    }
    case 'study.updateSection': {
      const s = find(cur, p.id);
      if ('solo' in p) { s.solo = !!p.solo; s.paletteIndex = s.solo ? null : 0; }
      if ('name' in p) s.name = (p.name ?? '').trim() || (s.solo ? 'Solo' : 'Sección');
      if ('color' in p) { if (p.color != null && !(p.color >= 0 && p.color <= 6)) bad('color fuera de la paleta'); s.color = p.color ?? null; }
      if (p.start != null) s.start = Math.min(p.start, s.end - MIN_SECTION);
      if (p.end != null) s.end = Math.max(p.end, s.start + MIN_SECTION);
      return state(ctx);
    }
    case 'study.previewSectionEdge': {
      // Empuje simple (sin cascada): la propia sección y la vecina no bajan de 0,5 s; un solo frena el borde.
      const s = find(cur, p.id);
      if (!Number.isFinite(p.to)) bad('«to» debe ser un tiempo');
      const secs = clone(cur.sections).sort((a, b) => a.start - b.start);
      const i = secs.findIndex(x => x.id === p.id), x = secs[i], prev = secs[i - 1], next = secs[i + 1];
      if (p.start) {
        const lo = prev ? (prev.solo ? prev.end : Math.min(prev.end, prev.start + MIN_SECTION)) : 0;
        x.start = Math.min(Math.max(p.to, lo), x.end - MIN_SECTION);
        if (prev && prev.end > x.start) prev.end = x.start;
      } else {
        const hi = next ? (next.solo ? next.start : Math.max(next.start, next.end - MIN_SECTION)) : Math.max(tr.duration, x.end);
        x.end = Math.max(Math.min(p.to, hi), x.start + MIN_SECTION);
        if (next && next.start < x.end) next.start = x.end;
      }
      void s;
      return { sections: secs };
    }
    case 'study.nudgeSectionEdge': {
      const s = find(cur, p.id);
      const step = (p.forward ? 1 : -1) * (p.bar ? 2 : 0.5);
      if (p.start) s.start = Math.max(0, Math.min(s.start + step, s.end - MIN_SECTION));
      else s.end = Math.min(tr.duration, Math.max(s.end + step, s.start + MIN_SECTION));
      return state(ctx);
    }
    case 'study.deleteSection': find(cur, p.id); cur.sections = cur.sections.filter(s => s.id !== p.id); return state(ctx);
    case 'study.applySections':
      if (params.get('apply') === 'fail') { guitars.saveError = 'No se pudo guardar project.json (disco lleno)'; throw new BridgeError('save-failed', guitars.saveError); }
      saved = clone(cur.sections); guitars.saveError = null; return state(ctx);
    case 'study.discardSections': cur.sections = clone(saved); return state(ctx);
    default: return undefined;
  }
}
