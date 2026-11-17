#!/usr/bin/env node
// Comprueba que cada tecnica de TabTechniques sobrevive a tf-bridge.js: JSON -> score de alphaTab -> .gp -> relectura.
// Uso: node Probes/P5b-guitarra/check-techniques.js   (sale con 1 si alguna falla)
'use strict';
const path = require('path');
const res = path.resolve(__dirname, '..', '..', 'App', 'Resources', 'alphaTab');
const alphaTab = require(path.join(res, 'alphaTab.min.js'));
const core = require(path.join(res, 'tf-bridge.js')).create(alphaTab);
const m = alphaTab.model;

const n = (t, f) => ({ s: 3, f: f == null ? 5 : f, t });
const b = (note, extra) => Object.assign({ d: 4, notes: [note] }, extra || {});
const pts = (...a) => a.map((v, i) => [Math.round(60 * i / (a.length - 1)), v]);
// [nombre, beat, comprobacion(nota, beat), beats que siguen]
const rest = [{ d: 4 }, { d: 4 }, { d: 4 }];
const cases = [
  ['palmMute', b(n({ pm: true })), (x) => x.isPalmMute],
  ['letRing', b(n({ lr: true })), (x) => x.isLetRing],
  ['hammerPull', { d: 8, notes: [n({ hp: true }, 5)] }, (x) => x.isHammerPullOrigin, [{ d: 8, notes: [n(null, 7)] }, { d: 4 }, { d: 4 }, { d: 4 }]],
  ['dead', b(n({ dead: true })), (x) => x.isDead],
  ['ghost', b(n({ ghost: true })), (x) => x.isGhost],
  ['staccato', b(n({ stac: true })), (x) => x.isStaccato],
  ['vibrato', b(n({ vib: 'wide' })), (x) => x.vibrato === m.VibratoType.Wide],
  ['bend', b(n({ bend: { type: 'bendRelease', pts: pts(0, 4, 0) } })),
    (x) => x.bendType === m.BendType.BendRelease && x.bendPoints.length >= 3 && x.bendPoints.some((p) => p.value === 4)], // GP duplica la cima
  ['bend4', b(n({ bend: { type: 'custom', pts: pts(0, 4, 4, 0) } })), (x) => x.bendPoints.length === 4],
  ['slideIn', b(n({ sin: 'intoFromBelow' })), (x) => x.slideInType === m.SlideInType.IntoFromBelow],
  ['slideOut', b(n({ sout: 'outDown' })), (x) => x.slideOutType === m.SlideOutType.OutDown],
  ['harmonic', b(n({ harm: { type: 'natural', fret: 12 } }, 12)), (x) => x.harmonicType === m.HarmonicType.Natural],
  ['accent', b(n({ acc: 'heavy' })), (x) => x.accentuated === m.AccentuationType.Heavy],
  ['tapping', b(n(null), { tap: true }), (x, bt) => bt.tap],
  ['tremoloPicking', b(n(null), { trem: 16 }), (x, bt) => bt.tremoloSpeed === 16],
  ['whammy', b(n(null), { whammy: { type: 'bendRelease', pts: pts(0, -4, 0) } }),
    (x, bt) => bt.whammyBarType === m.WhammyType.Dip && bt.whammyBarPoints.length === 3],
  ['pickStroke', b(n(null), { pick: 'down' }), (x, bt) => bt.pickStroke === m.PickStroke.Down],
  ['brush', b(n(null), { brush: 'up' }), (x, bt) => bt.brushType === m.BrushType.BrushUp],
];

let failed = false;
function run(name, json, check) {
  let ok = false, detail = '';
  try {
    const bytes = core.exportGp(json, {});
    const back = alphaTab.importer.ScoreLoader.loadScoreFromBytes(bytes, core.newSettings());
    const bt = back.tracks[0].staves[0].bars[0].voices[0].beats[0];
    ok = !!check(bt.notes[0], bt);
  } catch (e) { detail = String((e && e.stack) || e); }
  failed = failed || !ok;
  console.log((ok ? 'OK    ' : 'FALLA ') + name + (detail ? ' ' + detail : ''));
}
const score = (name, kind, beats) => ({ version: 1, title: name, artist: '',
  bars: [{ num: 4, den: 4, tempo: 120, start: 0 }],
  tracks: [{ name: 'T', kind, tuning: kind === 'drums' ? undefined : [40, 45, 50, 55, 59, 64], bars: [beats] }] });

for (const [name, beat, check, after] of cases) run(name, score(name, 'guitar', [beat].concat(after || rest)), check);
run('drumGhost', score('d', 'drums', [{ d: 4, hits: [38], ghosts: [38] }, { d: 4, hits: [38] }, { d: 2 }]),
  (x) => x.isGhost);
for (const type of ['beforeBeat', 'onBeat']) {
  const json = score('g', 'guitar', [{ d: 32, grace: type, notes: [n({ hp: true }, 3)] }, b(n(null, 5)), { d: 4 }, { d: 4 }, { d: 4 }]);
  let ok = false, detail = '';
  try {
    const back = alphaTab.importer.ScoreLoader.loadScoreFromBytes(core.exportGp(json, {}), core.newSettings());
    const bs = back.tracks[0].staves[0].bars[0].voices[0].beats;
    ok = bs[0].graceType === m.GraceType[type.charAt(0).toUpperCase() + type.substr(1)] && bs[0].notes[0].fret === 3 &&
      bs[1].graceType === m.GraceType.None && bs[1].notes[0].fret === 5;
    detail = ok ? '' : JSON.stringify(bs.map((x) => [x.graceType, x.notes.map((y) => y.fret)]));
  } catch (e) { detail = String((e && e.stack) || e); }
  failed = failed || !ok;
  console.log((ok ? 'OK    ' : 'FALLA ') + 'grace ' + type + (detail ? ' ' + detail : ''));
}
{
  const json = score('d', 'drums', [{ d: 32, grace: 'beforeBeat', hits: [38] }, { d: 4, hits: [38] }, { d: 4 }, { d: 4 }, { d: 4 }]);
  let ok = false;
  try {
    const back = alphaTab.importer.ScoreLoader.loadScoreFromBytes(core.exportGp(json, {}), core.newSettings());
    const bs = back.tracks[0].staves[0].bars[0].voices[0].beats;
    ok = bs[0].graceType === m.GraceType.BeforeBeat && bs[0].notes.length === 1 && bs[1].graceType === m.GraceType.None;
  } catch (e) { console.log(String(e)); }
  failed = failed || !ok;
  console.log((ok ? 'OK    ' : 'FALLA ') + 'drum grace');
}
// Rastrillo (Tornado): dos beats de adorno muertos en las cuerdas 3 y 2 (indices 3 y 4 del JSON) antes de la principal
// en la 1 (indice 5). En pantalla (buildScore) y tras el .gp: los mismos beats que en el JSON (el mapa de beats va uno
// a uno), en orden, cada nota en su cuerda, y la principal y lo que sigue sin desplazar (displayStart 0 y 960).
{
  const dead = (s) => ({ s, f: 0, t: { dead: true } });
  const json = score('g', 'guitar', [{ d: 32, grace: 'beforeBeat', notes: [dead(3)] }, { d: 32, grace: 'beforeBeat', notes: [dead(4)] },
    { d: 4, notes: [{ s: 5, f: 5 }] }, { d: 4 }, { d: 4 }, { d: 4 }]);
  const shape = (bs) => bs.map((x) => [x.graceType, x.notes.map((y) => [y.string, y.fret, y.isDead]), x.displayStart]);
  const want = JSON.stringify([[m.GraceType.BeforeBeat, [[4, 0, true]]], [m.GraceType.BeforeBeat, [[5, 0, true]]],
    [m.GraceType.None, [[6, 5, false]], 0], [m.GraceType.None, [], 960]]);
  for (const [what, load] of [['pantalla', () => core.buildScore(json, { tabOnly: true })],
    ['.gp', () => alphaTab.importer.ScoreLoader.loadScoreFromBytes(core.exportGp(json, {}), core.newSettings())]]) {
    let ok = false, detail = '';
    try {
      const bs = load().tracks[0].staves[0].bars[0].voices[0].beats;
      const got = shape(bs).slice(0, 4).map((x, i) => (i < 2 ? x.slice(0, 2) : x));
      ok = bs.length === json.tracks[0].bars[0].length && JSON.stringify(got) === want;
      detail = ok ? '' : JSON.stringify(shape(bs));
    } catch (e) { detail = String((e && e.stack) || e); }
    failed = failed || !ok;
    console.log((ok ? 'OK    ' : 'FALLA ') + 'rake ' + what + (detail ? ' ' + detail : ''));
  }
}
run('drumAccent', score('d', 'drums', [{ d: 4, hits: [38, 42], accents: { 38: 'heavy' } }, { d: 4, hits: [38] }, { d: 2 }]),
  (x, bt) => bt.notes.some((y) => y.accentuated === m.AccentuationType.Heavy) &&
    bt.notes.filter((y) => y.accentuated !== m.AccentuationType.None).length === 1);
// Dibujo sin cabeza (motor SVG de alphaTab, como la pantalla con tabOnly): ningun caso debe dar error al dibujar.
// bendRelease3 es el bend-release de 3 puntos que reventaba en El roce ("t.bendPoints[3].value"); tf-bridge.js duplica
// la cima, y el JSON de Swift ya la trae duplicada (TabBend.paddedForAlphaTab).
function render(name, json) {
  let errors = [], svg = 0;
  try {
    const settings = core.newSettings();
    settings.core.engine = 'svg';
    settings.core.enableLazyLoading = false;
    const r = new alphaTab.rendering.ScoreRenderer(settings);
    r.width = 900;
    r.partialRenderFinished.on((p) => { svg += (p.renderResult || '').length; });
    r.error.on((e) => errors.push(String((e && e.message) || e)));
    r.renderScore(core.buildScore(json, { tabOnly: true }), [0]);
  } catch (e) { errors.push(String((e && e.message) || e)); }
  const ok = errors.length === 0 && svg > 0;
  failed = failed || !ok;
  console.log((ok ? 'OK    ' : 'FALLA ') + 'dibujo ' + name + (ok ? '' : ' ' + errors.join(' | ')));
}
const drawn = cases.concat([
  ['bendRelease3', b(n({ bend: { type: 'bendRelease', pts: [[0, 0], [30, 4], [60, 0]] } }))],
  ['prebendRelease2', b(n({ bend: { type: 'prebendRelease', pts: [[0, 4], [60, 0]] } }))],
  ['bendReleaseTied', { d: 8, notes: [n({ bend: { type: 'bendRelease', pts: [[0, 0], [20, 4], [60, 0]] }, hp: true }, 5)] },
    null, [{ d: 8, notes: [n({ bend: { type: 'bendRelease', pts: [[0, 0], [30, 2], [60, 0]] } }, 7)] }, { d: 4 }, { d: 4 }, { d: 4 }]],
]);
for (const [name, beat, , after] of drawn) render(name, score(name, 'guitar', [beat].concat(after || rest)));
process.exit(failed ? 1 : 0);
