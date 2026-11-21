// Etiquetas y formas de acorde. Port de StudyKit (ChordLabel.swift, ChordShapes.swift) y SpanishNotes de BackingView.swift.

export const QUALITY_COUNT = 14;
export const UNKNOWN_INDEX = 168;
export const NO_CHORD_INDEX = 169;

/// Notas en español para las tonalidades («La menor»); los acordes llevan letra («Am»).
export const SPANISH_NOTES = ['Do', 'Do#', 'Re', 'Re#', 'Mi', 'Fa', 'Fa#', 'Sol', 'Sol#', 'La', 'La#', 'Si'];
const SHARP = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

// Orden del modelo: min, maj, dim, aug, min6, maj6, min7, minmaj7, maj7, 7, dim7, hdim7, sus2, sus4.
const Q = { min: 0, maj: 1, dim: 2, aug: 3, min6: 4, maj6: 5, min7: 6, minmaj7: 7, maj7: 8, dom7: 9, dim7: 10, hdim7: 11, sus2: 12, sus4: 13 };
const SUFFIX = ['m', '', '°', '+', 'm6', '6', 'm7', 'm(maj7)', 'maj7', '7', '°7', 'ø7', 'sus2', 'sus4'];

const mod12 = n => ((n % 12) + 12) % 12;

export const isChord = index => index >= 0 && index < 12 * QUALITY_COUNT;
export const rootOf = index => (isChord(index) ? Math.floor(index / QUALITY_COUNT) : null);
export const qualityOf = index => (isChord(index) ? index % QUALITY_COUNT : null);

/// Sube (o baja) la raíz `semitones`; X y N no cambian.
export function transposed(index, semitones) {
  if (!isChord(index) || !semitones) return index;
  return mod12(rootOf(index) + semitones) * QUALITY_COUNT + qualityOf(index);
}

/// Texto del botón de calidad del editor (ChordEditor del Mac): el sufijo, «mayor» para la mayor.
export const qualityLabel = q => SUFFIX[q] || 'mayor';

export function chordName(index) {
  if (!isChord(index)) return index === NO_CHORD_INDEX ? 'N' : 'X';
  return SHARP[rootOf(index)] + SUFFIX[qualityOf(index)];
}

/// «La menor» desde un nombre `.lab` («A:min»), transpuesto; «—» si no se reconoce.
export function keyName(lab, transpose = 0) {
  if (!lab) return '—';
  const [root, quality] = lab.split(':');
  let r = SHARP.indexOf(root);
  if (r < 0) r = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'].indexOf(root);
  if (r < 0) return '—';
  return SPANISH_NOTES[mod12(r + transpose)] + (quality === 'min' ? ' menor' : ' mayor');
}

const FLAT = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

/// Raíz (0-11) y modo de una tonalidad `.lab` («A:min», «F#:maj»); null si no se reconoce.
export function keyParts(lab) {
  if (!lab) return null;
  const [root, quality] = lab.split(':');
  let r = SHARP.indexOf(root);
  if (r < 0) r = FLAT.indexOf(root);
  if (r < 0 || (quality !== 'min' && quality !== 'maj')) return null;
  return { root: r, minor: quality === 'min' };
}

/// Etiqueta `.lab` GUARDADA (sin transponer, con sostenidos) de una tonalidad elegida en pantalla (ya transpuesta).
export const storedKeyLabel = (shownRoot, minor, transpose = 0) => `${SHARP[mod12(shownRoot - transpose)]}:${minor ? 'min' : 'maj'}`;

// MARK: formas (afinación estándar, 6.ª a 1.ª; null = muteada)
const OPEN = {
  '0:1': [null, 3, 2, 0, 1, 0], '0:9': [null, 3, 2, 3, 1, 0], '0:8': [null, 3, 2, 0, 0, 0], '0:12': [null, 3, 0, 0, 1, 3],
  '2:1': [null, null, 0, 2, 3, 2], '2:0': [null, null, 0, 2, 3, 1], '2:2': [null, null, 0, 1, 3, 1], '2:4': [null, null, 0, 2, 0, 1],
  '2:5': [null, null, 0, 2, 0, 2], '2:6': [null, null, 0, 2, 1, 1], '2:7': [null, null, 0, 2, 2, 1], '2:8': [null, null, 0, 2, 2, 2],
  '2:9': [null, null, 0, 2, 1, 2], '2:10': [null, null, 0, 1, 0, 1], '2:11': [null, null, 0, 1, 1, 1], '2:12': [null, null, 0, 2, 3, 0],
  '2:13': [null, null, 0, 2, 3, 3],
  '5:8': [null, null, 3, 2, 1, 0],
  '7:1': [3, 2, 0, 0, 0, 3], '7:9': [3, 2, 0, 0, 0, 1], '7:8': [3, 2, 0, 0, 0, 2], '7:5': [3, 2, 0, 0, 0, 0],
};
const E_FORM = {
  [Q.maj]: [0, 2, 2, 1, 0, 0], [Q.min]: [0, 2, 2, 0, 0, 0], [Q.dim]: [0, 1, 2, 0, null, null], [Q.aug]: [0, 3, 2, 1, 1, 0],
  [Q.min6]: [0, 2, 2, 0, 2, 0], [Q.maj6]: [0, 2, 2, 1, 2, 0], [Q.min7]: [0, 2, 0, 0, 0, 0], [Q.minmaj7]: [0, 2, 1, 0, 0, 0],
  [Q.maj7]: [0, 2, 1, 1, 0, 0], [Q.dom7]: [0, 2, 0, 1, 0, 0], [Q.dim7]: [0, 1, 2, 0, 2, null], [Q.hdim7]: [0, 1, 0, 0, null, null],
  [Q.sus4]: [0, 2, 2, 2, 0, 0],
};
const A_FORM = {
  [Q.maj]: [null, 0, 2, 2, 2, 0], [Q.min]: [null, 0, 2, 2, 1, 0], [Q.dim]: [null, 0, 1, 2, 1, null], [Q.aug]: [null, 0, 3, 2, 2, 1],
  [Q.min6]: [null, 0, 2, 2, 1, 2], [Q.maj6]: [null, 0, 2, 2, 2, 2], [Q.min7]: [null, 0, 2, 0, 1, 0], [Q.minmaj7]: [null, 0, 2, 1, 1, 0],
  [Q.maj7]: [null, 0, 2, 1, 2, 0], [Q.dom7]: [null, 0, 2, 0, 2, 0], [Q.dim7]: [null, 0, 1, 2, 1, 2], [Q.hdim7]: [null, 0, 1, 0, 1, null],
  [Q.sus2]: [null, 0, 2, 2, 0, 0], [Q.sus4]: [null, 0, 2, 2, 3, 0],
};

function makeShape(frets, barre = null) {
  const pressed = frets.filter(f => f != null && f > 0);
  const max = pressed.length ? Math.max(...pressed) : 0;
  return { frets, barre, baseFret: max > 4 ? Math.min(...pressed) : 1 };
}

function barreShape(template, firstString, rootFret) {
  const frets = template.map(f => (f == null ? null : f + rootFret));
  let barre = null;
  if (rootFret > 0) {
    const zeros = [];
    template.forEach((f, i) => { if (f === 0) zeros.push(6 - i); });
    if (zeros.length >= 2) barre = { fret: rootFret, fromString: firstString, toString: Math.min(...zeros) };
  }
  return makeShape(frets, barre);
}

const highest = s => Math.max(0, ...s.frets.filter(f => f != null));

/// Forma del acorde con capo: la de la etiqueta transpuesta −capo. null para X y N.
export function chordShape(index, capo = 0) {
  const idx = transposed(index, -capo);
  if (!isChord(idx)) return null;
  const root = rootOf(idx), q = qualityOf(idx);
  const open = OPEN[`${root}:${q}`];
  if (open) return makeShape(open);
  const cands = [];
  if (E_FORM[q]) cands.push(barreShape(E_FORM[q], 6, mod12(root - 4)));
  if (A_FORM[q]) cands.push(barreShape(A_FORM[q], 5, mod12(root - 9)));
  if (!cands.length) return null;
  return cands.reduce((a, b) => (highest(b) < highest(a) ? b : a));
}
