/*
 * ToneForge <-> alphaTab bridge (Fase 5, parte 0). Mini-spec: docs/spec.md, "Tablatura".
 *
 * Input: "tf-score" JSON built by Swift (TabScore). Schema (version 1):
 *
 *   {
 *     "version": 1, "title": "...", "artist": "...",
 *     "bars": [ { "num": 4, "den": 4, "tempo": 120, "start": 0.0 }, ... ],   // one per master bar
 *     "tracks": [ {
 *       "name": "Guitarra", "kind": "guitar" | "bass" | "drums",
 *       "tuning": [40, 45, 50, 55, 59, 64],        // MIDI, LOW -> HIGH; string index 0 = lowest. Omitted for drums
 *       "bars": [ [ beat, ... ], ... ]             // one array of beats per master bar, same count as "bars"
 *     } ]
 *   }
 *   beat = { "d": 8,                       // duration denominator: 1 2 4 8 16 32
 *            "dots": 0,                    // optional
 *            "tuplet": 3 | [3, 2],         // optional; 3 = eighth triplet (3 in the time of 2)
 *            "notes": [ { "s": 0, "f": 5 } ],   // pitched: string index (0 = lowest) and fret
 *            "hits": [ 35, 42 ] }               // drums: GM percussion numbers (35 36 38 42 47 49 ...)
 *   A beat with neither "notes" nor "hits" is a rest. "tempo" is in quarter notes per minute;
 *   an automation is written only when it differs from the previous bar (the first bar always).
 *   "start" (seconds of the bar in the song) is optional and only used by setCursorTime.
 *
 * Browser API (window.TF): load(json), setCursor(bar, fraction), setCursorTime(seconds),
 *   exportGpBase64(options), selectTrack(index). Events go to webkit.messageHandlers.tf.
 * Headless API (Node / Deno, no DOM): buildScore(json), exportGp(json, options) -> Uint8Array,
 *   readGp(bytes) -> summary.
 */
(function (root) {
  'use strict';

  // GM percussion articulations written for the drum track (spec: bombo 35, caja 38, tom 47, charles 42,
  // platos 49). Fields copied from alphaTab 1.9.0 PercussionMapper (elementType, staffLine, output MIDI,
  // note head default/half/whole, technique symbol, placement, id) so the GP exporter can map them to the
  // Guitar Pro drum kit (OutputRSESound). The 5 note-head symbols are SMuFL codepoints used by alphaTab.
  const DRUM_ARTICULATIONS = {
    35: ['Acoustic Kick Drum', 8, 35, 57508, 57507, 57506, -1, 0],
    36: ['Kick Drum', 7, 36, 57508, 57507, 57506, -1, 0],
    38: ['Snare', 3, 38, 57508, 57507, 57506, -1, 0],
    42: ['Charley', -1, 42, 57513, 57513, 57513, -1, 0],
    47: ['Tom Medium', 4, 47, 57508, 57507, 57506, -1, 0],
    49: ['Crash High', -2, 49, 57592, 57592, 57592, -1, 0],
  };

  const KIND_DEFAULTS = {
    // program = GM program for MIDI playback; channels avoid 9 (percussion) except for drums.
    guitar: { program: 30, clefName: 'G2', displayTranspose: -12 },
    bass: { program: 33, clefName: 'F4', displayTranspose: -12 },
    drums: { program: 0, clefName: 'Neutral', displayTranspose: 0 },
  };


  // RSE de la bateria en Guitar Pro 8. Comparado con un .gp hecho en GP cuya bateria suena (Temp/Flojos_De_Pantalon.gp),
  // el gpif de alphaTab 1.9.0 difiere en la pista de percusion en: (1) <Sounds> trae un Sound "Midi/0" (piano GM, rol
  // Factory) sin <RSE> en vez de "Drums/Drums/Drumkit" (rol User) con <RSE><SoundbankPatch>Drumkit-Master + cadena de
  // efectos; (2) <AudioEngineState>MIDI en vez de RSE; (3) falta <NotationPatch> tras <InstrumentSet>; (4) Port 1 en vez de 0.
  // `patchDrumGpif(xml, drumTrackId)` aplica esos cuatro cambios al score.gpif exportado (texto, sin DOM).
  const DRUM_SOUND_XML =
    '<Sounds><Sound><Name><![CDATA[Drum Kit]]></Name><Label><![CDATA[000 Drum Kit]]></Label>' +
    '<Path>Drums/Drums/Drumkit</Path><Role>User</Role><MIDI><LSB>0</LSB><MSB>0</MSB><Program>0</Program></MIDI>' +
    '<RSE><SoundbankPatch>Drumkit-Master</SoundbankPatch><ElementsSettings></ElementsSettings>' +
    '<Pickups><OverloudPosition>0</OverloudPosition><Volumes>1 1</Volumes><Tones>1 1</Tones></Pickups>' +
    '<EffectChain><Effect id="M06_DynamicAnalogDynamic"><Parameters>0 0 0.75189 0.38 0.29046 0.4 0.6057 0.5</Parameters></Effect>' +
    '<Effect id="M08_GraphicEQ10Band"><Parameters>0 0 0.3547 0.343434 0.393939 0.545455 0.474747 0.383838 0.343434 0.363636 0.525253 0.606061 0.686869</Parameters></Effect>' +
    '<Effect id="M05_StudioReverbPlatePercussive"><Parameters>1 0.13 0.3 0.5 0.5</Parameters></Effect></EffectChain>' +
    '</RSE></Sound></Sounds>';

  function patchDrumGpif(xml, drumTrackId) {
    const open = '<Track id="' + drumTrackId + '">';
    const start = xml.indexOf(open);
    if (start < 0) throw new Error('drum track not found');
    let end = xml.indexOf('</Track>', start) + '</Track>'.length;
    let t = xml.substring(start, end);
    // (3) NotationPatch con las articulaciones del InstrumentSet
    const names = [];
    t.replace(/<Element><Name>([^<]*)<\/Name>.*?<Articulations>(.*?)<\/Articulations><\/Element>/g, function (m, en, arts) {
      const list = [];
      arts.replace(/<Articulation><Name>([^<]*)<\/Name><StaffLine>(-?\d+)<\/StaffLine>/g, function (m2, an, line) {
        list.push('<Articulation><Name>' + an + '</Name><StaffLine>' + line + '</StaffLine></Articulation>');
        return m2;
      });
      names.push('<Element><Name>' + en + '</Name><Articulations>' + list.join('') + '</Articulations></Element>');
      return m;
    });
    const notation = '<NotationPatch><Name>Drumkit-Standard</Name><LineCount>5</LineCount><Elements>' + names.join('') +
      '</Elements></NotationPatch>';
    t = t.replace('</InstrumentSet>', '</InstrumentSet>' + notation);
    // (1) Sound y su automatizacion
    t = t.replace(/<Sounds>.*?<\/Sounds>/, DRUM_SOUND_XML);
    t = t.replace(/(<Automation><Type>Sound<\/Type>.*?<Value>)<!\[CDATA\[[^\]]*\]\]>(<\/Value>)/,
      '$1<![CDATA[Drums/Drums/Drumkit;Drum Kit;User]]>$2');
    // (2) motor RSE y (4) puerto
    t = t.replace('<AudioEngineState>MIDI</AudioEngineState>', '<AudioEngineState>RSE</AudioEngineState>');
    t = t.replace(/<Port>\d+<\/Port>/, '<Port>0</Port>');
    return xml.substring(0, start) + t + xml.substring(end);
  }

  function create(alphaTab) {
    const model = alphaTab.model;

    function makeArticulation(gm) {
      const a = DRUM_ARTICULATIONS[gm];
      if (!a) throw new Error('Unsupported drum piece: ' + gm);
      return new model.InstrumentArticulation(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], gm);
    }

    function newSettings() {
      return new alphaTab.Settings();
    }

    function buildScore(json, opts) {
      opts = opts || {};
      const score = new model.Score();
      score.title = json.title || '';
      score.artist = json.artist || '';
      score.tab = 'ToneForge';

      let previousTempo = null;
      json.bars.forEach(function (b) {
        const mb = new model.MasterBar();
        mb.timeSignatureNumerator = b.num;
        mb.timeSignatureDenominator = b.den;
        if (b.tempo != null && b.tempo !== previousTempo) {
          mb.tempoAutomations.push(model.Automation.buildTempoAutomation(false, 0, b.tempo, 2));
          previousTempo = b.tempo;
        }
        score.addMasterBar(mb);
      });

      let guitarChannel = 0;
      json.tracks.forEach(function (t, ti) {
        const kind = KIND_DEFAULTS[t.kind];
        if (!kind) throw new Error('Unknown track kind: ' + t.kind);
        if (t.bars.length !== json.bars.length) {
          throw new Error('Track "' + t.name + '" has ' + t.bars.length + ' bars, expected ' + json.bars.length);
        }
        const track = new model.Track();
        track.name = t.name;
        track.shortName = t.name.length > 10 ? t.name.substr(0, 10) : t.name;
        track.ensureStaveCount(1);
        score.addTrack(track);
        const staff = track.staves[0];
        const isDrums = t.kind === 'drums';

        if (isDrums) {
          track.playbackInfo.primaryChannel = 9;
          track.playbackInfo.secondaryChannel = 9;
          staff.isPercussion = true;
          staff.showTablature = false;
          staff.showStandardNotation = true;
          if (!opts.drumsDefaultKit) {
            // Explicit list: the note index below is an index into this list.
            Object.keys(DRUM_ARTICULATIONS).forEach(function (gm) {
              track.getOrRegisterPercussionArticulation(makeArticulation(Number(gm)));
            });
          }
        } else {
          track.playbackInfo.primaryChannel = guitarChannel;
          track.playbackInfo.secondaryChannel = guitarChannel + 1;
          guitarChannel += 2;
          if (guitarChannel === 8) guitarChannel = 10; // skip the percussion channel (9)
          staff.showTablature = true;
          // opts.tabOnly (pantalla): solo la tablatura, con el ritmo en ella; el .gp lleva tambien el pentagrama.
          staff.showStandardNotation = !opts.tabOnly;
          if (!t.tuning || t.tuning.length < 4) throw new Error('Track "' + t.name + '" needs a tuning');
          // alphaTab lists tuning HIGH -> LOW; its note.string 1 is the lowest string.
          setTuning(staff, t.tuning.slice().reverse());
          staff.displayTranspositionPitch = kind.displayTranspose;
        }
        track.playbackInfo.program = kind.program;
        track.playbackInfo.bank = 0;

        t.bars.forEach(function (beats) {
          const bar = new model.Bar();
          bar.clef = model.Clef[kind.clefName];
          staff.addBar(bar);
          const voice = new model.Voice();
          bar.addVoice(voice);
          beats.forEach(function (bt) {
            const beat = new model.Beat();
            beat.duration = bt.d;
            beat.dots = bt.dots || 0;
            if (bt.tuplet) {
              const tp = Array.isArray(bt.tuplet) ? bt.tuplet : [bt.tuplet, bt.tuplet === 3 ? 2 : bt.tuplet - 1];
              beat.tupletNumerator = tp[0];
              beat.tupletDenominator = tp[1];
            }
            voice.addBeat(beat);
            if (isDrums) {
              (bt.hits || []).forEach(function (gm) {
                const note = new model.Note();
                note.percussionArticulation = opts.drumsDefaultKit
                  ? gm
                  : track.getOrRegisterPercussionArticulation(makeArticulation(gm));
                beat.addNote(note);
              });
            } else {
              (bt.notes || []).forEach(function (n) {
                if (n.s < 0 || n.s >= t.tuning.length) throw new Error('String out of range: ' + n.s);
                const note = new model.Note();
                note.string = n.s + 1;
                note.fret = n.f;
                beat.addNote(note);
              });
            }
          });
        });
      });

      score.finish(newSettings());
      return score;
    }

    function setTuning(staff, highToLow) {
      // Tuning(name, tunings high -> low, isStandard); isStandard/name are detected on finish().
      staff.stringTuning = new model.Tuning('', highToLow, false);
    }

    function exportGp(json, options) {
      const score = buildScore(json, options);
      const settings = newSettings();
      return new alphaTab.exporter.Gp7Exporter().export(score, settings);
    }

    function readGp(bytes) {
      const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(bytes, newSettings());
      return summarize(score);
    }

    function summarize(score) {
      return {
        tracks: score.tracks.length,
        bars: score.masterBars.length,
        trackInfo: score.tracks.map(function (tr) {
          let notes = 0;
          let beats = 0;
          tr.staves.forEach(function (st) {
            st.bars.forEach(function (bar) {
              bar.voices.forEach(function (v) {
                v.beats.forEach(function (be) {
                  beats += 1;
                  notes += be.notes.length;
                });
              });
            });
          });
          return {
            name: tr.name,
            percussion: tr.isPercussion,
            bars: tr.staves[0].bars.length,
            beats: beats,
            notes: notes,
            tuning: tr.staves[0].tuning,
          };
        }),
        tempos: score.masterBars.map(function (mb) {
          return mb.tempoAutomations.map(function (a) { return a.value; });
        }),
      };
    }

    return { buildScore: buildScore, exportGp: exportGp, readGp: readGp, summarize: summarize, newSettings: newSettings };
  }

  // ---- Browser side (WKWebView) ----
  function browser(alphaTab, core) {
    let api = null;
    let score = null;
    let json = null;
    let cursorEl = null;
    let selEl = null;
    let pending = null;
    let pendingSel = null;
    let pendingScroll = null;

    function post(msg) {
      try {
        root.webkit.messageHandlers.tf.postMessage(msg);
      } catch (e) { /* not inside the app */ }
    }

    function ensureCursor(host) {
      if (cursorEl) return cursorEl;
      cursorEl = document.createElement('div');
      cursorEl.id = 'tf-cursor';
      cursorEl.style.cssText = 'position:absolute;width:3px;background:rgba(255,140,0,.85);' +
        'pointer-events:none;display:none;z-index:10;border-radius:1px';
      host.appendChild(cursorEl);
      selEl = document.createElement('div');
      selEl.id = 'tf-selection';
      selEl.style.cssText = 'position:absolute;width:2px;background:rgba(80,160,255,.95);' +
        'pointer-events:none;display:none;z-index:9;border-radius:1px;box-shadow:0 0 6px rgba(80,160,255,.7)';
      host.appendChild(selEl);
      return cursorEl;
    }

    function load(j, trackIndex) {
      json = typeof j === 'string' ? JSON.parse(j) : j;
      score = core.buildScore(json, { tabOnly: true });
      const host = document.getElementById('alphaTab');
      if (!api) {
        const settings = new alphaTab.Settings();
        settings.core.fontDirectory = 'font/';
        settings.core.useWorkers = false;
        settings.core.enableLazyLoading = false;
        settings.player.enablePlayer = false;
        settings.display.layoutMode = alphaTab.LayoutMode.Page;
        applyTheme(settings);
        settings.notation.rhythmMode = alphaTab.TabRhythmMode.ShowWithBars;
        settings.notation.rhythmHeight = 24;
        api = new alphaTab.AlphaTabApi(host, settings);
        host.style.position = 'relative';
        ensureCursor(host);
        api.postRenderFinished.on(function () {
          if (pendingScroll != null) { window.scrollTo(0, pendingScroll); pendingScroll = null; }
          post({ event: 'rendered' });
          if (pendingSel) { const q = pendingSel; pendingSel = null; setSelection(q[0], q[1]); }
          if (pending) { const p = pending; pending = null; setCursor(p[0], p[1]); }
        });
        api.renderFinished.on(function () { /* postRenderFinished carries the bounds */ });
        api.error.on(function (e) { post({ event: 'error', message: 'alphaTab: ' + String(e && e.message || e) + '\n' + (e && e.stack || '') }); });
        api.beatMouseDown.on(function (beat) {
          post({ event: 'beatClick', track: beat.voice.bar.staff.track.index, bar: beat.voice.bar.index, beat: beat.index });
        });
        api.noteMouseDown.on(function (note) {
          post({ event: 'noteClick', track: note.beat.voice.bar.staff.track.index,
                 bar: note.beat.voice.bar.index, beat: note.beat.index, string: note.string - 1, fret: note.fret });
        });
      }
      pendingScroll = window.scrollY;
      if (cursorEl) cursorEl.style.display = 'none';
      if (selEl) selEl.style.display = 'none';
      api.renderScore(score, [trackIndex || 0]);
    }

    // Tema oscuro de la app (fondo #171A1D). Colores como en el tema de ToneForge.
    function applyTheme(settings) {
      const C = alphaTab.model.Color;
      const r = settings.display.resources;
      const light = new C(232, 234, 237, 255);
      const dim = new C(154, 163, 173, 255);
      r.mainGlyphColor = light;
      r.secondaryGlyphColor = dim;
      r.staffLineColor = new C(110, 118, 128, 255);
      r.barSeparatorColor = new C(110, 118, 128, 255);
      r.barNumberColor = new C(242, 163, 58, 255);
      r.scoreInfoColor = light;
      // Titulo y artista ya salen en la cabecera de la app: se ocultan los bloques de informacion de la partitura.
      ['ScoreTitle', 'ScoreSubTitle', 'ScoreArtist', 'ScoreAlbum', 'ScoreWords', 'ScoreMusic', 'ScoreWordsAndMusic',
       'ScoreCopyright', 'GuitarTuning'].forEach(function (n) { settings.notation.elements.set(alphaTab.NotationElement[n], false); });
    }

    function selectTrack(i) {
      if (api && score) api.renderTracks([score.tracks[i]]);
    }

    // bar: master bar index; fraction 0..1 of the bar. Linear in time inside the bar (the app converts
    // the player position with TabScore's bar times).
    function place(el, bar, fraction) {
      const mbb = api.boundsLookup.findMasterBarByIndex(bar);
      if (!mbb) { el.style.display = 'none'; return null; }
      const mb = score.masterBars[bar];
      const barTicks = mb.calculateDuration();
      const tick = Math.max(0, Math.min(1, fraction)) * barTicks;
      // MasterBarBounds -> bars[] (una por pista dibujada) -> beats[] (BeatBounds con `beat` y `onNotesX`).
      const barBounds = mbb.bars && mbb.bars.length ? mbb.bars[0] : null;
      const beats = barBounds && barBounds.beats ? barBounds.beats : [];
      let x = mbb.realBounds.x;
      let top = mbb.visualBounds.y;
      let height = mbb.visualBounds.h;
      for (let i = 0; i < beats.length; i++) {
        const b = beats[i];
        const start = b.beat.playbackStart - mb.start;
        const end = i + 1 < beats.length ? beats[i + 1].beat.playbackStart - mb.start : barTicks;
        const bx = b.onNotesX;
        const nx = i + 1 < beats.length ? beats[i + 1].onNotesX : mbb.realBounds.x + mbb.realBounds.w;
        if (tick >= start || i === 0) {
          const f = end > start ? Math.min(1, Math.max(0, (tick - start) / (end - start))) : 0;
          x = bx + (nx - bx) * f;
        }
      }
      el.style.left = x + 'px';
      el.style.top = top + 'px';
      el.style.height = height + 'px';
      el.style.display = 'block';
      return { x: x, y: top, h: height };
    }

    // follow: si el cursor sale de la vista, desplaza la pagina para dejarlo a un tercio de la altura.
    function setCursor(bar, fraction, follow) {
      if (!api || !api.boundsLookup || !cursorEl) { pending = [bar, fraction]; return; }
      const p = place(cursorEl, bar, fraction);
      if (!p) return;
      if (follow) {
        const host = document.getElementById('alphaTab').getBoundingClientRect();
        const top = host.top + window.scrollY + p.y;
        if (top < window.scrollY || top + p.h > window.scrollY + window.innerHeight) {
          window.scrollTo(0, Math.max(0, top - window.innerHeight / 3));
        }
      }
      post({ event: 'cursor', bar: bar, x: p.x, y: p.y });
    }

    // Marcador de la seleccion (sigue al compas y la fraccion; sin follow). bar < 0 lo oculta.
    function setSelection(bar, fraction) {
      if (!api || !api.boundsLookup || !selEl) { pendingSel = [bar, fraction]; return; }
      if (bar < 0) { selEl.style.display = 'none'; return; }
      place(selEl, bar, fraction);
    }

    function setCursorTime(seconds, follow) {
      if (!json) return;
      const bars = json.bars;
      let i = 0;
      while (i + 1 < bars.length && bars[i + 1].start != null && bars[i + 1].start <= seconds) i++;
      const start = bars[i].start || 0;
      const next = i + 1 < bars.length && bars[i + 1].start != null ? bars[i + 1].start : null;
      let fraction = 0;
      if (next != null && next > start) fraction = (seconds - start) / (next - start);
      setCursor(i, fraction, follow);
    }

    function exportGpBase64(options) {
      const bytes = core.exportGp(json, options);
      let s = '';
      const chunk = 0x8000;
      for (let i = 0; i < bytes.length; i += chunk) {
        s += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
      }
      return btoa(s);
    }

    // Cualquier excepcion se manda a Swift con su pila (evento error) en vez de perderse como «JavaScript exception».
    function guarded(name, fn) {
      return function () {
        try { return fn.apply(null, arguments); } catch (e) {
          post({ event: 'error', message: name + ': ' + String(e && e.message || e) + '\n' + (e && e.stack || '') });
          if (name === 'exportGpBase64') throw e;
        }
      };
    }
    return { load: guarded('load', load), selectTrack: guarded('selectTrack', selectTrack),
             setCursor: guarded('setCursor', setCursor), setCursorTime: guarded('setCursorTime', setCursorTime),
             setSelection: guarded('setSelection', setSelection), exportGpBase64: guarded('exportGpBase64', exportGpBase64) };
  }

  const api = { create: create, patchDrumGpif: patchDrumGpif, DRUM_ARTICULATIONS: DRUM_ARTICULATIONS };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  } else {
    root.TFBridge = api;
    if (root.alphaTab) {
      const core = create(root.alphaTab);
      root.TF = Object.assign({}, core, browser(root.alphaTab, core));
    }
  }
})(typeof globalThis !== 'undefined' ? globalThis : this);
