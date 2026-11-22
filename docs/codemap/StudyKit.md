# Packages/StudyKit

Pulso, acordes, tonalidad y su caché (ADR-009). No depende de ningún paquete propio.

| Fichero | qué hace (ADR-009): APIs públicas |
| --- | --- |
| `Sources/StudyKit/Beat/BeatAnalyzer.swift` | `BeatAnalyzer(modelURL:).analyze(mix:)` → `BeatGrid`; Beat This! en Core ML CPU+GPU FP32, trozos de 1500 tramas |
| `Sources/StudyKit/Beat/LogMel.swift`, `BeatAudio.swift` | Log-mel (módulo / 32, mel Slaney 128) y lectura de audio; `BeatError` |
| `Sources/StudyKit/Beat/BeatGrid.swift` | `BeatGrid` (`beats`, `downbeats`, `bpm`, `beatsPerBar`, `bar(at:)`, `snap(_:to:)`, `clicks(in:)`), `Click` |
| `Sources/StudyKit/Chord/CQT.swift`, `ChordAudio.swift` | CQT estilo librosa (144 bins, 24 por octava) con FIR Kaiser, y su lectura de audio |
| `Sources/StudyKit/Chord/ChordRecognizer.swift` | `ChordRecognizer(modelURL:).analyze(stems:)` → `ChordAnalysis` (`segments`, `chroma`, `lab`); BTC FP16 en Neural Engine; `ChordError` |
| `Sources/StudyKit/Key/KeyDetector.swift` | `KeyDetector.detect(chroma:segments:)` → `KeyEstimate` (perfiles de Temperley); `StudyAnalysis` (beats + chords + key) |
| `Sources/StudyKit/Audio/MonoResampler.swift` | Mono y remuestreo a 22 050 Hz |
| `Sources/StudyKit/ChordLabel.swift` | `ChordLabel` (170 etiquetas, `name`, `labName`, `transposed(by:)`), `ChordQuality` |
| `Sources/StudyKit/ChordShapes.swift` | `ChordShapes.shape(for:capo:)` → `ChordShape` (diagrama de 6 cuerdas) |
| `Sources/StudyKit/ChordTimeline.swift` | `ChordSegment`, `ChordOverride`, `ChordTimeline.effective(detected:overrides:)` |
| `Sources/StudyKit/AnalysisCache.swift` | `AnalysisFingerprint`, `AnalysisCache.load(at:expecting:)` y `save` |
| `Sources/StudyKit/SectionEdgePicker.swift` | (ADR-014) `SectionEdgePicker`: qué borde de sección se agarra con el ratón (asas de las cajas de secciones) |
| `Sources/StudyKit/` LogMel, CQT, decodificación (Fase 7c, paso 6) | (ADR-020) `LogMel` y `CQT` sobre `NativeDSP` (log-mel frente al fixture 4,05e-5; CQT frente a librosa, medio 5e-6); decodificación con `AudioFileReader`. En Windows, `MonoResampler` y `makeBeatPredictor`/`makeChordPredictor` (internos) son stubs `[paso 7]` remuestreador y onnx-runtime |
| `Sources/StudyKit/OnnxPredictors.swift` (Fase 7c, paso 7) | (ADR-020) Solo Windows: `makeBeatPredictor` y `makeChordPredictor` (internos) sobre `NativeONNX` (Beat This! y BTC); `MonoResampler` sobre `NativeResample`. Ya no hay stubs. Los tests con modelo leen `TF_MODELS_DIR` (`DevelopmentModels.swift`) |
| `Sources/StudyKit/Beat/SongsterrGridFile.swift` (Fase 7c, paso 8) | (ADR-020) `SongsterrGridFile` (`songId`, `revisionId`, `beats`, `downbeats`, `writtenTempo`; `save(to:)`, `load(_:)`, `metronomeGrid(songId:revisionId:)`): rejilla de `tab/songsterr-grid.json`, antes duplicada en `App/Sources/StudySession.swift` y en AppCore. Test `SongsterrGridFileTests` |
| `Tests/StudyKitTests/` | 47 tests (`BeatTests`, `ChordTests`, `ChordRecognizerTests`; pesados `BeatHeavyModelTests` y `ChordHeavyModelTests` con `TF_MODEL_TESTS=1` bajo `guard.py`). Fixtures en `Fixtures/` con su README; las genera `Probes/P4-modelos/fixtures/make_fase2_fixtures.py` |
