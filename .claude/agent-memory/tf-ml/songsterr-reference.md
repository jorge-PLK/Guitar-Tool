---
name: songsterr-reference
description: Songsterr como verdad de referencia (Fase 5b) — búsqueda, trampas de descarga (103, gzip), formato JSON y cómo alinear la tablatura con el audio
metadata:
  type: project
---

- Búsqueda sin página: `GET https://www.songsterr.com/api/songs?size=20&pattern=...` (JSON con songId y pistas) respondió
  200 con UA de navegador. URL de página: `/a/wsa/<slug>-tab-s<songId>`.
- La página responde **103 Early Hints** antes del 200: `urllib`/`http.client` de Python 3.12 toma el 103 como final.
  Pedirla con `curl` (subprocess). El script guarda la página en Temp/p5b/songsterr/page_s<id>.html para no volver a pedirla.
- El CDN (`https://dqsljvtekg760.cloudfront.net/<songId>/<revisionId>/<image>/<partId>.json`) sirve **gzip sin
  Content-Encoding**: descomprimir si empieza por 1f 8b.
- Formato: measures[].voices[].beats[].notes[] con string (0 = la más aguda; pitch = tuning[string] + fret), fret, tie,
  rest; beat.duration = [num, den] de redonda, ya incluye puntillo y tresillo; measure.repeatStart / repeat (veces);
  automations.tempo [{measure, bpm}].
- **Alineación**: ni la F de ataques (librosa en eléctrica distorsionada es mala y el rasgueo periódico confunde
  desfases de 2 negras) ni la DTW por croma por pulso sirven; lo que funcionó es la saliencia CQT del stem en la altura
  exacta de cada nota de la tablatura, desfase global y luego por bloques de 4 compases (Viterbi). Comprobar siempre
  con un tramo (el solo) que la clase de altura casa: pc F ≈ 0,05 = referencia desalineada, no un modelo malo.

- El campo `frets` de una pista de Songsterr no es el número real de trastes (vale 32): para un techo de registro,
  usar el traste máximo que aparece en la pista.
- Rítmica desde acordes BTC: `ChordShapes` está en **StudyKit** (no en TabKit); port en Probes/P5b-guitarra/btc_rhythm.py.
  `librosa.onset.onset_detect` con normalización global da ~145 ataques en un stem distorsionado: normalizar el
  envelope por contraste local (máximo en 2 s) y `normalize=False`.

**Why:** dos enfoques de alineación dieron métricas falsas (solo a 0) antes de dar con la saliencia.
**How to apply:** reutilizar Probes/P5b-guitarra/songsterr_fetch.py y eval_reference.py. Ver [[guitab-muscriptor-eval]].
