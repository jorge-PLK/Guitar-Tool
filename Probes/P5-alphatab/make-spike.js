#!/usr/bin/env node
// Genera Temp/p5/spike-tf.gp (y spike-tf-drumfix.gp) con tf-bridge.js y comprueba la relectura.
// Uso: node Probes/P5-alphatab/make-spike.js [carpeta-salida]   (por defecto Temp/p5)
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
const res = path.join(root, 'App', 'Resources', 'alphaTab');
const alphaTab = require(path.join(res, 'alphaTab.min.js'));
const bridge = require(path.join(res, 'tf-bridge.js'));
const core = bridge.create(alphaTab);
const { execFileSync } = require('child_process');
const out = path.resolve(process.argv[2] || path.join(root, 'Temp', 'p5'));
fs.mkdirSync(out, { recursive: true });

const q = (notes) => ({ d: 4, notes });
const e = (notes) => ({ d: 8, notes });
const rest = (d) => ({ d });
const power = (s, f) => [{ s, f }, { s: s + 1, f: f + 2 }, { s: s + 2, f: f + 2 }]; // quinta con octava
const kick = 35, snare = 38, hat = 42, tom = 47, crash = 49;

const bars = [];
for (let i = 0; i < 8; i++) bars.push({ num: 4, den: 4, tempo: i < 4 ? 120 : 100, start: i < 4 ? i * 2 : 8 + (i - 4) * 2.4 });

// Guitarra EADGBE: 2 compases de power chords (E5, A5, E5, B5), luego una linea y un compas con tresillo.
const guitar = [
  [q(power(0, 0)), q(power(0, 0)), q(power(1, 0)), q(power(1, 0))],
  [q(power(0, 0)), q(power(0, 0)), q(power(0, 3)), q(power(0, 5))],
  [e([{ s: 3, f: 2 }]), e([{ s: 3, f: 4 }]), e([{ s: 4, f: 0 }]), e([{ s: 4, f: 2 }]), e([{ s: 4, f: 3 }]), e([{ s: 4, f: 2 }]), e([{ s: 4, f: 0 }]), e([{ s: 3, f: 4 }])],
  // tresillo de corchea (3 en el tiempo de 2) en el tiempo 1 y 3
  [{ d: 8, tuplet: 3, notes: [{ s: 4, f: 5 }] }, { d: 8, tuplet: 3, notes: [{ s: 4, f: 3 }] }, { d: 8, tuplet: 3, notes: [{ s: 4, f: 2 }] }, q([{ s: 3, f: 2 }]), rest(4), rest(4)],
  [q(power(0, 0)), rest(4), q(power(0, 0)), rest(4)],
  [e([{ s: 0, f: 0 }]), e([{ s: 0, f: 0 }]), e([{ s: 0, f: 3 }]), e([{ s: 0, f: 3 }]), e([{ s: 0, f: 5 }]), e([{ s: 0, f: 5 }]), e([{ s: 0, f: 3 }]), e([{ s: 0, f: 0 }])],
  [q(power(1, 0)), q(power(1, 0)), q(power(0, 0)), q(power(0, 0))],
  [{ d: 1, notes: power(0, 0) }],
];

// Bajo EADG: corcheas sobre la fundamental.
const bassBar = (f) => Array.from({ length: 8 }, () => e([{ s: 0, f }]));
const bass = [bassBar(0), bassBar(0), bassBar(0), bassBar(0), bassBar(0), bassBar(0), bassBar(5), [{ d: 1, notes: [{ s: 0, f: 0 }] }]];

// Bateria: bombo, caja, charles, plato (compas 1) y tom con tresillos (compas 4).
const groove = () => [
  { d: 8, hits: [kick, hat] }, { d: 8, hits: [hat] }, { d: 8, hits: [snare, hat] }, { d: 8, hits: [hat] },
  { d: 8, hits: [kick, hat] }, { d: 8, hits: [kick, hat] }, { d: 8, hits: [snare, hat] }, { d: 8, hits: [hat] },
];
const fill = () => [
  { d: 8, tuplet: 3, hits: [tom] }, { d: 8, tuplet: 3, hits: [tom] }, { d: 8, tuplet: 3, hits: [tom] },
  { d: 4, hits: [snare] }, { d: 4, hits: [tom] }, { d: 4, hits: [kick] },
];
const drums = [
  [{ d: 8, hits: [crash, kick, hat] }, ...groove().slice(1)],
  groove(), groove(), fill(), groove(), groove(), groove(),
  [{ d: 1, hits: [crash, kick] }],
];

const spike = {
  version: 1, title: 'ToneForge spike', artist: 'ToneForge', bars,
  tracks: [
    { name: 'Guitarra', kind: 'guitar', tuning: [40, 45, 50, 55, 59, 64], bars: guitar },
    { name: 'Bajo', kind: 'bass', tuning: [28, 33, 38, 43], bars: bass },
    { name: 'Bateria', kind: 'drums', bars: drums },
  ],
};
fs.writeFileSync(path.join(out, 'spike-tf.json'), JSON.stringify(spike, null, 1));

function expected(j) {
  return j.tracks.map((t) => {
    let notes = 0;
    t.bars.forEach((b) => b.forEach((bt) => { notes += (bt.notes || bt.hits || []).length; }));
    return notes;
  });
}

// .gp = zip con Content/score.gpif; parcheamos el XML de la bateria (ver patchDrumGpif en tf-bridge.js).
function patchGp(bytes, drumTrackId) {
  const work = path.join(out, 'work');
  fs.rmSync(work, { recursive: true, force: true });
  fs.mkdirSync(work, { recursive: true });
  const src = path.join(work, 'in.gp');
  fs.writeFileSync(src, bytes);
  execFileSync('unzip', ['-q', src, '-d', path.join(work, 'x')]);
  const gpif = path.join(work, 'x', 'Content', 'score.gpif');
  fs.writeFileSync(gpif, bridge.patchDrumGpif(fs.readFileSync(gpif, 'utf8'), drumTrackId));
  const dst = path.join(work, 'out.gp');
  execFileSync('zip', ['-q', '-X', '-r', dst, '.'], { cwd: path.join(work, 'x') .replace(/x$/, 'x') });
  const result = fs.readFileSync(dst);
  fs.rmSync(work, { recursive: true, force: true });
  return result;
}

let failed = false;
for (const [file, options] of [['spike-tf.gp', {}], ['spike-tf-drumfix.gp', { drumfix: true }]]) {
  let bytes = core.exportGp(spike, options);
  if (options.drumfix) bytes = patchGp(bytes, 2);
  fs.writeFileSync(path.join(out, file), bytes);
  const back = core.readGp(bytes);
  const want = expected(spike);
  const ok = back.tracks === spike.tracks.length && back.bars === spike.bars.length &&
    back.trackInfo.every((t, i) => t.notes === want[i] && t.bars === spike.bars.length);
  failed = failed || !ok;
  console.log(file, bytes.length + ' bytes', ok ? 'RELECTURA OK' : 'RELECTURA FALLA');
  console.log(JSON.stringify(back.trackInfo.map((t) => [t.name, t.bars, t.notes, t.tuning.join('/')])), 'tempos', JSON.stringify(back.tempos));
}
process.exit(failed ? 1 : 0);
