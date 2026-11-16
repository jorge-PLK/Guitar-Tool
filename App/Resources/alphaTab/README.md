# alphaTab embebido (Fase 5)

- Version: **@coderline/alphatab 1.9.0** (estable, publicada el 2026-10-31), fijada. Origen: `npm pack @coderline/alphatab@1.9.0`.
- `alphaTab.min.js`: build UMD (sirve en `WKWebView` y en Node/Deno). Licencia MPL-2.0 (`LICENSE-alphaTab-MPL-2.0.txt`).
  Mantener visible la atribucion "alphaTab.net" que pinta la libreria.
- `font/Bravura.woff2` + `font/Bravura-OFL.txt`: fuente de musica Bravura, SIL OFL 1.1.
- `soundfont/sonivox.sf2` + `soundfont/LICENSE`: soundfont GM (SONiVOX EAS, Apache-2.0), para sintetizar con `AVAudioUnitSampler`.
- `tf-bridge.js` y `tab.html`: codigo propio de ToneForge (puente Swift <-> alphaTab, esquema JSON documentado en la cabecera).
- Generar los `.gp` de prueba: `node Probes/P5-alphatab/make-spike.js` (salida en `Temp/p5/`).
- Actualizar: cambiar la version, repetir el `npm pack`, copiar los mismos ficheros y relanzar el script anterior.
