#!/usr/bin/env node
// Fase 5c, decision 4: una pista "vocal" sobrevive a tf-bridge.js como pista de pentagrama sin tablatura:
// JSON -> score de alphaTab -> .gp -> relectura. Sin hardware.
// Uso: node Probes/P5c-voces/check-vocal.js   (sale con 1 si algo falla)
'use strict';
const path = require('path');
const res = path.resolve(__dirname, '..', '..', 'App', 'Resources', 'alphaTab');
const alphaTab = require(path.join(res, 'alphaTab.min.js'));
const core = require(path.join(res, 'tf-bridge.js')).create(alphaTab);

const vocal = (p) => ({ d: 4, notes: [{ s: 0, f: 0, p }] });
const json = {
  version: 1, title: 'T', artist: 'A',
  bars: [{ num: 4, den: 4, tempo: 120, start: 0 }],
  tracks: [
    { name: 'Guitarra', kind: 'guitar', tuning: [40, 45, 50, 55, 59, 64], bars: [[{ d: 1, notes: [{ s: 3, f: 5 }] }]] },
    { name: 'Voz', kind: 'vocal', program: 66, bars: [[vocal(64), vocal(67), { d: 4 }, vocal(72)]] },
  ],
};

let failed = false;
function check(label, ok, detail) {
  if (!ok) failed = true;
  console.log((ok ? 'ok   ' : 'FALLA') + ' ' + label + (ok ? '' : '  ' + detail));
}

const score = core.buildScore(json, { tabOnly: true });
const v = score.tracks[1];
check('sin tablatura ni afinacion', v.staves[0].showTablature === false && v.staves[0].showStandardNotation === true
  && (v.staves[0].stringTuning.tunings || []).length === 0, JSON.stringify(v.staves[0].stringTuning));
check('programa GM de la pista', v.playbackInfo.program === 66, v.playbackInfo.program);
const pitches = v.staves[0].bars[0].voices[0].beats.flatMap((b) => b.notes.map((n) => n.realValue));
check('alturas MIDI', JSON.stringify(pitches) === '[64,67,72]', JSON.stringify(pitches));

const bytes = core.exportGp(json, {});
const back = core.readGp(bytes);
check('.gp: dos pistas', back.tracks === 2, back.tracks);
const bv = back.trackInfo[1];
check('.gp: la voz conserva sus 3 notas', bv.notes === 3, JSON.stringify(bv));
const reread = alphaTab.importer.ScoreLoader.loadScoreFromBytes(bytes, core.newSettings());
const rv = reread.tracks[1];
check('.gp: voz sin tablatura', rv.staves[0].showTablature === false && rv.staves[0].showStandardNotation === true,
  JSON.stringify({ tab: rv.staves[0].showTablature, std: rv.staves[0].showStandardNotation }));
check('.gp: programa de la voz', rv.playbackInfo.program === 66, rv.playbackInfo.program);
const rp = rv.staves[0].bars[0].voices[0].beats.flatMap((b) => b.notes.map((n) => n.realValue));
check('.gp: alturas', JSON.stringify(rp) === '[64,67,72]', JSON.stringify(rp));
check('.gp: la guitarra sigue con tablatura', reread.tracks[0].staves[0].showTablature === true, '');
process.exit(failed ? 1 : 0);
