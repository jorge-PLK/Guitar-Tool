# ToneForge · Mapa del código

Última actualización: 2026-11-19 · Fase 7c, paso 6 (ADR-020): capa de plataforma del port a Windows (`Packages/NativeKit` y costuras en los demás paquetes; stubs `[paso 7]` en Windows).

Una sección por paquete (nombres de `docs/plan.md`, «Forma de trabajo»), más la app, las pruebas y las herramientas. Fila por fichero: `| Fichero | qué hace (ADR-NNN): APIs públicas |`. Se lee por secciones: `grep -n '^## ' docs/CODEMAP.md`.

## Packages/AudioKit

E/S de audio y reproducción: importación (ADR-007), reproductor de estudio (ADR-009) y audio con el dispositivo (ADR-012, ADR-013).

| Fichero | qué hace (ADR-007, ADR-009, ADR-012, ADR-013): APIs públicas |
| --- | --- |
| `Sources/AudioKit/AudioImporter.swift` | Convierte WAV, FLAC o MP3 a WAV estéreo float32 a 44100 o 48000 Hz con `AVAudioConverter` en calidad máxima y por bloques. `AudioImporter.importAudio(from:to:sampleRate:progress:)`, `resample(_:to:sampleRate:)`, `metadata(of:)`; `ImportedAudio`, `AudioImportError`. AVFoundation no lee los Vorbis comments de FLAC: el título sale del nombre («Artista - Título.ext») |
| `Sources/AudioKit/StudyPlayer.swift` | `StudyPlayer` sobre `AVAudioEngine` (ADR-009): un `AVAudioPlayerNode` por stem, `AVAudioUnitVarispeed` delante de un `AVAudioUnitTimePitch` (overlap 8) que se reinicia en play, seek y cambios de velocidad o transposición. `load(tracks:)`, `play`, `pause`, `seek(to:)`, `currentTime`, `setGain`, `setMute`, `setSolo`, `masterGainDB`, `meters`, `rate` 0,5…2,0, `pitchCents`, `loop`, `metronome`, `outputDeviceName`; el metrónomo va después del TimePitch |
| `Sources/AudioKit/StudyPlayerTypes.swift` | `Track`, `Click`, `Metronome`, `ChannelMeter`, `StudyPlayerError` |
| `Sources/AudioKit/StemScheduler.swift` | Programa los stems y el bucle encadenado con precisión de muestra y fundidos de 5 ms |
| `Sources/AudioKit/PlaybackTimeline.swift` | Conversión entre tiempo de canción y de salida según `rate` |
| `Sources/AudioKit/ClickRenderer.swift` | Genera los clics del metrónomo en tiempo de salida |
| `Sources/AudioKit/OutputDevices.swift` | Dispositivos genéricos (ADR-012): `AudioDevice` (`inputChannels`, `outputChannels`, `sampleRates`, `nominalSampleRate`, `supports`, `isRunning(at:)`), `AudioDeviceProviding` (`inputDevices`, `outputDevices`, `defaultOutputDevice`, `requestSampleRate`, `setChangeHandler`), `OutputSelection` (UID y canales izquierdo y derecho), `OutputRoute`, `AudioRouting.route` (selección o salida por defecto) y `channelMap`, `CoreAudioDeviceProvider`, `SimulatedDeviceProvider` para tests. Ya no hay lógica por nombre de dispositivo |
| `Sources/AudioKit/AudioIO.swift` | Contrato de E/S (ADR-013): protocolo `AudioIO` (`start(render:capture:)`, `stop`, `sampleTime`, `declaredLatencySamples`), `AudioIOFormat`, `AudioIOClock`, `AudioIOBuffer`, `AudioIOError`, `AudioIOInterruption` |
| `Sources/AudioKit/SimulatedAudioIO.swift` | `SimulatedAudioIO`: `AudioIO` simulada sin hardware para tests y `tf-audio --simulated`, con `SimulatedInput` (retardo, ecos, saturación, ruido, `SimulatedTone`), `SimulatedEcho`, `recirculating` (bucle que realimenta), deriva en ppm, `pump`, `disconnect` |
| `Sources/AudioKit/CoreAudioIO.swift` | `CoreAudioIO`: `AudioIO` real sobre CoreAudio; un dispositivo directo o un agregado privado (`aggregateUIDPrefix`, `removeOrphanAggregates`) si entrada y salida difieren. `overloads`, `discontinuities`, `diagnostics`, `hostTimingReport()`, `ensureInputPermission()` |
| `Sources/AudioKit/CoreAudioHAL.swift` | Interno: envoltorio `HAL` de las llamadas de CoreAudio (propiedades, latencias declaradas, frecuencia nominal) |
| `Sources/AudioKit/CaptureRing.swift` | Interno: anillo de captura sin bloqueos entre el callback y el consumidor; cuenta las muestras perdidas |
| `Sources/AudioKit/AudioSession.swift` | `AudioSession` (+ `AudioSetup`, `AudioSessionError`, `AudioSessionEvent`): abre el `AudioIO` (`IOFactory`, por defecto `coreAudio`), reparte render y captura, `inputLevels`, `guitarLevelDB`, `calibrateLatency`, `startRecording`/`stopRecording`, `playbackAnchor`, `droppedFrames`, `ioDiagnostics`, `reshiftUncalibrated` |
| `Sources/AudioKit/HostedRenderer.swift` | Interno: renderiza el `AVAudioEngine` del reproductor bloque a bloque dentro del callback de la sesión (render manual en tiempo real) |
| `Sources/AudioKit/StemFeed.swift` | Interno: alimenta los stems al motor alojado con `AVAudioSourceNode`, porque `AVAudioUnitTimePitch` retrasa 4096 muestras en tiempo real |
| `Sources/AudioKit/LatencyProbe.swift` | `LatencyProbe`: barrido logarítmico de 500 a 8000 Hz (`stimulus(at:)`) y `analyze(_:channel:)` por correlación con primera llegada y submuestra; `LatencyChannelMeasurement`, `LatencyFailure` |
| `Sources/AudioKit/LatencyCalibrator.swift` | `LatencyCalibrator` (`render`, `capture`, `result`, `calibrate(on:timeout:)`), `LatencyCalibrationResult` (`applies(to:)`), `LatencyCalibrationKey`, `ReferenceInput` (canal de referencia interno) |
| `Sources/AudioKit/TakeAligner.swift` | `TakeAligner.rigDelay` (retardo del rig respecto al canal de referencia), `shiftSamples`, `reshift`; `RigDelayEstimate` |
| `Sources/AudioKit/TakeRecorder.swift` | `TakeRecorder` (`capture`, `finish(writingTo:)`), `PlaybackAnchor` (`songFrame(atOutputSample:)`), `RecordedTake`, `TakeRecorderError` |
| `Sources/AudioKit/LoudnessMatch.swift` | `LoudnessMatch.gain(take:stem:sampleRate:)` y `loudness`: ganancia que iguala la toma al stem (tope `maxGainDB` 12) para el A/B |
| `Sources/AudioKit/AlignmentCheck.swift` | `AlignmentCheck`: señal de comprobación (clics de 3 kHz cada 0,5 s sobre 60 s), `measure(take:songStart:sampleRate:songSeconds:)` → `AlignmentReport` (`ClickError`, `BackgroundTone` para detectar oscilación); `passThresholdSeconds` 0,001 |
| `Sources/AudioKit/AudioDiagnostics.swift` | `AudioIODiagnostics`, `HostedRenderStats`, `HostedPlaybackDiagnostics`, `HostTimingAnalysis.analyze` y tipos de marcas de host (`HostTimingReport`, `HostTimingStep`) para los escalones de latencia |
| `Sources/AudioKit/AppLogic.swift` | Lógica sin interfaz de la app: `RecordingGate` y `RecordBlock` (cuándo se puede grabar), `CompareMode` y `MixCompare` (A/B), `AudioSamples` (lectura de WAV, `rmsDB`) |
| `Sources/AudioKit/SignalMath.swift` | Interno: correlación, interpolación sinc, FFT y ruido con semilla |
| `Sources/AudioKit/StudyPlayer.swift` (Fase 3) | Selección de salida (`setOutput(_:)`, `OutputSelection`), `init(offlineWith:output:)`, pista de toma `setTake(_:)`/`take` (`TakeTrack`), alojamiento `attach(to:)`/`detach()`/`isHosted`, `playbackAnchor` (suma la latencia declarada del TimePitch), `hostedDiagnostics` |
| `Sources/AudioKit/StemScheduler.swift`, `PlaybackTimeline.swift` (Fase 3) | Programan y ubican también la pista de toma (`TakeTrack`: `id`, `url`, `songStart`, `gainDB`, `muted`) y el ancla |
| `Sources/AudioKit/AudioIO.swift`, `AudioSession.swift`, `SimulatedAudioIO.swift`, `CoreAudioIO.swift`, `CaptureRing.swift` (Fase 6) | (ADR-015) Marcas de reloj de host: `HostClockPoint` (muestra de salida ↔ segundos de host), `AudioSession.outputHostClock` y su equivalente simulado, con deriva configurable |
| `Sources/AudioKit/StudyPlayer.swift`, `StudyPlayerTypes.swift`, `StemScheduler.swift` (Fase 6) | (ADR-015) `StudyPlayer.setTakes(_:)`: varias pistas de toma a la vez (las mejores de las otras partes); `TakeTrack.solo` y `TakeTrack.silencedFrom` (silencio con fundido de la toma vieja desde la entrada del punch). La cuenta suena en un segundo `StudyPlayer` |
| `Sources/AudioKit/PunchFlattener.swift` | (ADR-015) `PunchFlattener`: aplana la toma base y el punch con fundidos cruzados de 10 ms; fuera del tramo conserva la base muestra a muestra |
| `Sources/AudioKit/LoudnessMeter.swift` (Fase 7) | (ADR-018) `LoudnessMeter` (BS.1770-4: `measure(_:sampleRate:)`, `measure(url:progress:)`, `report`) → `LoudnessReport` (`integratedLUFS`, `truePeakDB`, `duration`) |
| `Sources/AudioKit/MontageMixer.swift` (Fase 7) | (ADR-018) Mezcla fuera de línea del montaje: `MontageTrack` (`url`, `songStart`, `gainDB`, `group`, `presence`), `MontageGroup`, `MontagePresence`, `MontageSegment` (tramos con fundidos), `MontageNormalization` (`standard`, `standardWithoutLimiter`; -14 LUFS, techo -1,3 dBTP), `MontageMixJob`, `MontageMixer`; WAV por pista y fundido global. `MontageSpan` propio (AudioKit no depende de VideoKit) |
| `Sources/AudioKit/PeakLimiter.swift` (Fase 7) | (ADR-018) Interno: limitador con anticipación sobre pico real, en una pasada; lo usa `MontageMixer` |
| `Sources/AudioKit/TakeResampling.swift` (Fase 7) | (ADR-018) `TakeResampling.sampleRate(of:)`, `readable(_:at:)` y `read(_:at:)`: las tomas a otra frecuencia se remuestrean al cargar (caché en el temporal) |
| `Sources/AudioKit/AudioImporter.swift`, `PunchFlattener.swift`, `StudyPlayer.swift`, `TakeAligner.swift` (Fase 7) | (ADR-018) Retoques para el montaje y la lectura de tomas remuestreadas; `Package.swift` compila el target con `-O` también en Debug |
| `Tests/AudioKitTests/HostClockTests.swift`, `PunchAndTakesTests.swift` (Fase 6) | (ADR-015) Marcas de host, varias pistas de toma, silencio del punch y aplanado |
| `Sources/tf-audio/` | Ejecutable de desarrollo, no embebido (`TFAudio`, `Commands`, `Options`, `Rig`): `devices`, `latency` (`--restarts`), `verify`, `record`; `--simulated`; salidas en `Temp/tf-audio/` (incluye `verify-hal.csv`) |
| `Sources/AudioKit/PlatformShims.swift`, `IOTimingLog.swift`, `DuplexClockSync.swift` (Fase 7c, paso 6) | (ADR-020) Costuras de plataforma. `StateLock` interno (`OSAllocatedUnfairLock` en Mac), `HostTimeLog`/`IOCounters` sobre `NativePlatform.HostClock`. `DuplexClockSync` (público): `addRenderClock`, `addCapturePacket`, `renderBuffer`, `captureHostSeconds`, `driftPPM`, `resetCapture`, `seconds(qpc100ns:)`; el offset de captura sale de dos rectas de mínimos cuadrados (50 arranques con ±0,5 ms de temblor: peor caso 0,10 ms) |
| `Sources/AudioKit/WASAPIAudioIO.swift` (Fase 7c, paso 6) | (ADR-020) Solo Windows: `WASAPIAudioIO`, stub `[paso 7] wasapi` con el contrato documentado. `AudioSession.systemIO` elige CoreAudio (Mac) o WASAPI (Windows) por defecto en `makeIO` |
| `Sources/AudioKit/` bajo `#if canImport(AVFoundation)` (Fase 7c, paso 6) | (ADR-020) `StudyPlayer`, `StemFeed`, `StemScheduler`, `HostedRenderer`, `ClickRenderer`, `CoreAudioIO` y `CoreAudioDeviceProvider` no existen en Windows (sin clase stub). `AudioImporter` conserva la API y lanza `paso 7: remuestreador`. El análisis (`AlignmentCheck`, `SignalMath`, `LoudnessMeter`, etc.) va sobre `NativeDSP`; `tf-audio` compila en Windows y sale con aviso |
| `Tests/AudioKitTests/DuplexClockSyncTests.swift` (Fase 7c, paso 6) | (ADR-020) Offset, temblor, paquete suelto y deriva del reloj dúplex. En Windows se saltan 4 pruebas de grabación alineada (`AudioSessionTests`, `TakeAlignmentTests`, `FeedbackLoopTests`) por depender de `StudyPlayer` |
| `Tests/AudioKitTests/` | 144 tests, 1 omitido (Fase 7: `LoudnessMeterTests`, `MontageMixerTests`, `MontageMixerOrderTests`, `MontageLimiterSinglePassTests`, `MontageLimiterTruePeakTests`, `TakeResamplingTests`; `AudioImporterTests`, `StudyPlayerTests` en render offline; Fase 3: `AudioRoutingTests`, `AudioSessionTests`, `LatencyCalibratorTests`, `TakeAlignmentTests`, `PlayerHostingTests`, `HostTimingTests`, `FeedbackLoopTests`, `LoudnessMatchTests`, `AppLogicTests`, `TFAudioToolTests`; Fase 6: `HostClockTests`, `PunchAndTakesTests`). Fixtures en `Fixtures/` (unos 300 KB), con un README de los comandos ffmpeg |

## Packages/ModelKit

Descarga, verificación y compilación de modelos (paquete añadido en la Fase 1, ADR-007).

| Fichero | qué hace (ADR-007): APIs públicas |
| --- | --- |
| `Sources/ModelKit/ModelDescriptor.swift` | `ModelDescriptor`, `ModelRole`, `ModelArchiveKind` (`zippedCompiledModel`: zip con `.mlmodelc`, no se compila; `bundledZippedMLPackage`: zip de `.mlpackage` dentro de la app, se compila la primera vez) y `ModelCatalog` (`separatorBSRoformerSW`, `beatsBeatThis` (HF `jessengatai/supracut-beat-this`, commit `33fe1a5`), `chordsBTC` (embebido), `all` con los tres): URL, SHA-256 y tamaño (ADR-007, ADR-009) |
| `Sources/ModelKit/ModelStore.swift` | `actor ModelStore`: `ensureInstalled`, `install(_:fromArchive:)`, `delete`, `state`, `states`, `updates`, `diskUsage`; `ModelState`, `ModelError`. El inicializador admite `bundleResourceDirectory` (la app pasa el bundle, los tests un directorio). Descarga, SHA-256, `ditto`, compila y guarda solo el `.mlmodelc` (351 MB) con su `manifest.json` en `Application Support/ToneForge/Models/<id>/` |
| `Sources/ModelKit/Downloading.swift` | Protocolos `ModelDownloading` y `ModelCompiling`; `URLSessionDownloader`; `ModelDownloadError` |
| `Sources/ModelKit/CoreMLCompiler.swift` | `CoreMLCompiler`: `compileModel` (1,7 s; la especialización para la GPU ocurre en la primera carga) |
| `Sources/ModelKit/ModelDescriptor.swift` (Fase 5) | (ADR-016) `ModelCatalog.drumsADTOF`: ADTOF FP32 con GRU nativa, embebido (zip de `.mlpackage`, 1,7 MB, CC BY-NC-SA), entra en `all` |
| `Sources/ModelKit/ModelDescriptor.swift`, `ModelStore.swift`, `Downloading.swift`, `CoreMLCompiler.swift` (Fase 7c, paso 6) | (ADR-020) `public enum ModelFormat { coreML, onnx; static var native }`. `CoreMLCompiler` en Windows es un stub `[paso 7] onnx-runtime`. La descompresión usa `ChildProcess` (`ditto` en Mac, `tar.exe -xf` en Windows); `defaultRoot` = `SupportFolder.toneForge/Models`; descarga con FoundationNetworking. Depende de `NativeKit` (`NativePlatform`) y, en Windows, de swift-crypto |
| `Tests/ModelKitTests/ZipHelper.swift` (Fase 7c, paso 6) | (ADR-020) Crea zips de prueba (`tar.exe -a -c -f` en Windows). En Windows se saltan 2 pruebas `[windows]`: zips de `App/Resources/Models` no sincronizados y `file://` en `URLSession` |
| `Tests/ModelKitTests/` | 16 tests (`ModelOriginsTests`: orígenes y catálogo); 1 pesado con `TF_MODEL_TESTS=1` |

## Packages/StemKit

Separación de stems con BS-RoFormer SW en Core ML, `.cpuAndGPU` (ADR-004, ADR-007).

| Fichero | qué hace (ADR-007): APIs públicas |
| --- | --- |
| `Sources/StemKit/RoformerContract.swift` | Constantes del modelo y `Stem` (`fileName`). Trabaja a 44,1 kHz por dentro |
| `Sources/StemKit/SpectralTransform.swift` | STFT e iSTFT con Accelerate, compatibles con torch |
| `Sources/StemKit/ChunkPlan.swift` | Plan de trozos con solape |
| `Sources/StemKit/MaskModel.swift` | Envoltorio del modelo Core ML; la máscara FP16 llega con el último eje rellenado a 32 y se lee con vImage |
| `Sources/StemKit/ChunkProcessor.swift` | Procesa un trozo: STFT, máscara, iSTFT |
| `Sources/StemKit/AudioIO.swift` | Lectura y escritura de WAV |
| `Sources/StemKit/RoformerSeparator.swift` | `RoformerSeparator.separate(input:outputDirectory:…)`. Entrada a 48 kHz: se remuestrea y los stems salen a 48 kHz con la longitud exacta |
| `Sources/StemKit/MemoryGuard.swift` | `MemoryGuard` (`start`, `stop`, `peakBytes`, `limitExceeded`, `footprint(pid:)`): `phys_footprint` con `proc_pid_rusage`, SIGKILL por encima de `defaultLimitBytes` (10 GB) |
| `Sources/StemKit/SeparationRunner.swift` | `SeparationRunner.run(model:input:outputDirectory:)` lanza el helper, lee el progreso en JSON (`SeparationEvent`, `SeparationError`) y cancela con SIGTERM y luego SIGKILL |
| `Sources/StemKit/StemLevelMeter.swift` | `StemLevelMeter.measure(url:)` (RMS y pico en dBFS por bloques, `StemLevel`), `isEmpty` (RMS < −60 y pico < −40 dBFS) (ADR-009) |
| `Sources/StemKit/GuitarStemComposer.swift` | (ADR-014) `LeadGuitarSeparating` (protocolo del separador de solista), `GuitarStemComposer.compose(input:outputDirectory:stereo:soloSpans:…)` (pistas `guitar_rhythm`, `guitar_L`, `guitar_R`, `guitar_lead` que suman `guitar.wav`; fundidos de 100 ms), `GuitarStemTrack`, `GuitarSoloSpan.normalized` |
| `Sources/StemKit/CoreMLLeadSeparator.swift` | (ADR-014) `CoreMLLeadSeparator`: Mel-Band RoFormer lead/rhythm en Core ML FP16 sobre `MaskModelContract.leadRhythm` (num_overlap 2); la rítmica es entrada − solista |
| `Sources/StemKit/PanSplitter.swift`, `PanSoloSpan.swift` | (ADR-014) `PanSplitter` (máscaras de panorama por canal, puerta del centro por tramos), `GuitarSide`, `PanSoloSpan`. Sin uso en la app: descartado, ver ADR-014 |
| `Sources/tf-separate/` | Ejecutable `tf-separate` (producto): un proceso por tema, vigilado por `MemoryGuard` |
| `Sources/tf-memhog/` | Ejecutable `tf-memhog`, solo para tests del vigilante |
| `Sources/StemKit/` STFT, `AudioIO.swift`, `MaskModel` (Fase 7c, paso 6) | (ADR-020) STFT/iSTFT sobre `NativeDSP` (ida y vuelta 5,4e-7 a hop 512). Protocolo `MaskModel`; `SystemMaskModel.load` es un stub `[paso 7] onnx-runtime` en Windows; `MaskTensor.copy` ya no depende de Core ML. El remuestreo de `AudioIO` es stub: en Windows solo 44,1 kHz. `arc4random_buf` pasa a semilla `SystemRandomNumberGenerator` + SplitMix64 |
| `Sources/StemKit/WindowsProcess.swift` (Fase 7c, paso 6) | (ADR-020) Solo Windows: `MemoryGuard` con `K32GetProcessMemoryInfo` + `TerminateProcess` (código 137). `MemoryGuard` usa `Int32` en vez de `pid_t`. `tf-separate` y `tf-memhog` compilan en ARM64 y x64 |
| `Tests/StemKitTests/` | 36 tests (`StemLevelMeterTests`); 3 pesados con `TF_MODEL_TESTS=1` y 1 de referencia Python con `TF_REF_DIR` |

## Packages/StudyKit

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
| `Tests/StudyKitTests/` | 47 tests (`BeatTests`, `ChordTests`, `ChordRecognizerTests`; pesados `BeatHeavyModelTests` y `ChordHeavyModelTests` con `TF_MODEL_TESTS=1` bajo `guard.py`). Fixtures en `Fixtures/` con su README; las genera `Probes/P4-modelos/fixtures/make_fase2_fixtures.py` |

## Packages/SourceKit

Importar desde enlaces de YouTube y Spotify (ADR-008, ADR-011). No depende de ningún paquete propio: la app hace de puente con Store. Red y procesos van detrás de `HTTPFetching` y `ProcessRunning`.

| Fichero | qué hace (ADR-008, ADR-011): APIs públicas |
| --- | --- |
| `Sources/SourceKit/SourceLink.swift` | Analiza el enlace pegado: `SourceLink.parse` (vídeo de YouTube o tema de Spotify), `PlaylistLink.parse` (listas y álbumes), `SourceInput.parse` (distingue los dos); `canonicalURL` |
| `Sources/SourceKit/HTTPFetching.swift` | Protocolo `HTTPFetching`; `URLSessionFetcher` (tiempo límite de metadatos 15 s) |
| `Sources/SourceKit/SpotifyEmbedClient.swift` | `SpotifyMetadataFetching` → `SpotifyEmbedClient`: `track(id:)`, `playlist(id:)`, `album(id:)` sobre el `__NEXT_DATA__` del embed; `SpotifyTrack`, `SpotifyPlaylist` (`mayBeTruncated` con 100 temas), `SpotifyPlaylistTrack` |
| `Sources/SourceKit/ProcessRunning.swift` | Protocolo `ProcessRunning`, `ProcessRequest`, `ProcessResult`, `ProcessTimeout`; `SystemProcessRunner` (SIGTERM y luego SIGKILL) y versión simulada `ScriptedProcessRunner` con `ScriptedResponse` |
| `Sources/SourceKit/YtDlpClient.swift` | `YtDlpClient`: `version`, `info(url:)`, `search(query:)`, `playlist(url:)`, `download(url:into:…)`; clasifica el error por stderr; `VideoInfo`, `Candidate`, `YouTubePlaylist`, `DownloadedAudio` (`fellBackToM4A`); `formatSelector` Opus y caída a M4A |
| `Sources/SourceKit/CandidateRanker.swift` | `CandidateRanker.rank(_:referenceDuration:…)`, `closeThreshold` 3 s, `isLive(title:)`; `RankedCandidate` (`isClose`, `isLive`, `difference`) |
| `Sources/SourceKit/AudioTranscoder.swift` | `AudioTranscoder(ffmpeg:runner:).convert(input:output:)`: ffmpeg a WAV de 24 bit sin remuestrear |
| `Sources/SourceKit/HelperLocator.swift` | Rutas de yt-dlp (la más nueva entre el bundle y `Application Support`, `YtDlpChoice`), `deno()` y `ffmpeg()`; `removeUpdate()`, `compare`; `YtDlpInstallInfo` |
| `Sources/SourceKit/YtDlpUpdater.swift` | `YtDlpUpdater.update()`: baja `yt-dlp_macos` y `SHA2-256SUMS` de la última release, verifica y instala |
| `Sources/SourceKit/SourceError.swift` | `SourceError` (`returnsToCandidates`, `suggestsYtDlpUpdate`), `UnavailableReason` |
| `Sources/SourceKit/SourceImporter.swift` | `@MainActor SourceImporter`: `resolve`, `resolveWithoutSearch`, `addManualCandidate`, `download(candidate:title:artist:)`, `reset`, `removeOrphanedDownloads`; publica `ImportState`; `ResolvedSource`, `ImportedSource`, `ImportedOrigin`, `ImportNotice` |
| `Sources/SourceKit/PlaylistImporter.swift` | `PlaylistImporter` (listas y álbumes): `load`, `setSelected`, `selectAll`, `selectNone`, `searchCandidates`, `choose`, `run`, `resume`, `cancel`, `retryFailed`; `PlaylistItem`, `PlaylistTrack`, `PlaylistTotals`, `PlaylistPhase` |
| `Sources/tf-fetch/main.swift` | Ejecutable de desarrollo `tf-fetch <enlace> --helpers <dir> --out <dir> [--pick N]`; no se embebe |
| `Sources/SourceKit/Songsterr/` | (ADR-017) `SongsterrClient` (búsqueda y pistas), `SongsterrReader` (estado de la página), `SongsterrModels`, `SongsterrLookup` (artista y título → resultados), `SongsterrServing` (protocolo que implementa la app con el `WKWebView`), `SongsterrIssue` (errores y avisos). Sin red en los tests |
| `Tests/SourceKitTests/SongsterrTests.swift`, `SongsterrLookupTests.swift` | (ADR-017) Lector y búsqueda con páginas de muestra |
| `Sources/SourceKit/ProcessRunning.swift`, `HelperLocator`, `YtDlpUpdater`, `SongsterrClient` (Fase 7c, paso 6) | (ADR-020) `SystemProcessRunner` sobre `ChildProcess` (sin `kill`/`pid_t`). `HelperLocator.fileName(_:)` (público): nombre por plataforma (`.exe` en Windows); `defaultSupportDirectory` = `SupportFolder.toneForge/Helpers`. `YtDlpUpdater` en Windows borra y mueve (no atómico). Songsterr descomprime con `CMiniz` (deflate crudo) en Windows y `Compression` en Mac. swift-crypto en Windows y FoundationNetworking. Sin stubs ni saltos; `tf-fetch` no enlaza en Windows (`curl.lib`) |
| `Tests/SourceKitTests/` | 63 tests (`SourceKitTests`, `PlaylistTests`, `OrphanTests`) con fixtures grabados; sin red ni helpers |

## Packages/AnalysisKit

Huella del tono y distancia. Sin código (solo test de humo).

## Packages/MatchKit

Optimizador. Sin código (solo test de humo).

## Packages/HeadRushKit

Conector del Remote Editor de la Flex Prime. Sin código (solo test de humo).

## Packages/Tone3000Kit

Conector de TONE3000. Sin código (solo test de humo).

## Packages/TabKit

Transcripción y tablatura (ADR-014).

| Fichero | qué hace (ADR-014): APIs públicas |
| --- | --- |
| `Sources/TabKit/BasicPitch/BasicPitchTranscriber.swift` | `actor BasicPitchTranscriber`: Basic Pitch oficial en Core ML, por ventanas; con `BasicPitchContract` y `BasicPitchNotes` (notas desde las salidas del modelo) |
| `Sources/TabKit/Audio/MonoAudio.swift`, `NoteEvent.swift` | Lectura a mono y `NoteEvent` |
| `Sources/TabKit/Passages/PassageClassifier.swift` | `PassageClassifier` (rítmica o solista por pasajes, con contexto de pista), `GuitarRole`, `GuitarPassage`. Fuera de la cola de la biblioteca: sin propuesta automática (ADR-014) |
| `Sources/TabKit/Score/TabScore.swift` | (ADR-016) `TabScore` (Codable, `ticksPerBeat` 12, `trackIndex(id:)`), `TabBar`, `TabBeat`, `GridPoint`, `Subdivision`, `TabTrackKind`, `DrumPiece`, `TabNote`, `TabDrumHit`, `TabTrack` (`fret(of:)`) |
| `Sources/TabKit/Score/TabGrid.swift` | `BeatTimes`, `TabScoreError`, `ScorePosition`; conversión tiempo ↔ posición (`time(of:)`, `timeRange(of:)`, `position(at:)`, `time(at:)`, `nearestPoint(to:in:)`); cuantización a semicorcheas o tresillos y tempos enteros con corrección de deriva (`maxWrittenDrift`) |
| `Sources/TabKit/Score/Tuning.swift`, `Fingering.swift` | `TuningPreset`, `Tuning` (`guitar(_:)`, `bass(_:)`); Viterbi de cuerdas y trastes con coste por cuerda saltada, bajo monofónico |
| `Sources/TabKit/Score/TabTrackBuilder.swift` | `TabTrackBuilder.pitchedTrack(...)` y `drumTrack(...)`, `DrumOnset`, `TabBuildReport` (avisos de notas fuera de registro) |
| `Sources/TabKit/Score/TabEditor.swift` | `TabEditor` y `TabEditError`: cambiar traste, pasar de cuerda, borrar, añadir, duración, golpes de batería; deshacer y rehacer |
| `Sources/TabKit/Score/TrackSourceFingerprint.swift` | `TrackSourceFingerprint` (`of(fileAt:path:modelVersion:…)`), `TabStaleness`, `TabScore.staleness(current:)` |
| `Sources/TabKit/Drums/` | `DrumTranscriber` (actor; `transcribe(url:progress:)`, troceo con 30 s de contexto), `TranscribedDrumHit`; `DrumContract`, `DrumSpectrogram` (STFT y banco logarítmico con Accelerate), `DrumPeaks` |
| `Sources/TabKit/Synth/TabSynthRenderer.swift` | `TabSynthRenderer.render(track:in:sampleRate:duration:…)`: WAV fuera de tiempo real con el soundfont (`GuitarSound`), `TabSynthError` |
| `Sources/TabKit/Bridge/AlphaTabScore.swift` | `AlphaTabScore`, `AlphaTabBeatRef`, `AlphaTabExporter.make(score:title:artist:)`: JSON propio v1 para alphaTab |
| `Sources/TabKit/Songsterr/` | (ADR-017) `SongsterrTrackConverter` (versión 3, con técnicas), `SongsterrAligner` (desfase global con rango ampliado `globalShifts`, fino, bloques de 4 compases con `blockChangePenaltyPerBeat`, intro y anacrusa), `SongsterrBeatGrid` (`writtenTempo`, `prepare`, `regularize`, `build` → `SongsterrMeterGrid`), `SongsterrPairing` (parejas por croma, solos por `soloSalience`), `SongsterrScorePlacement`, `SongsterrImportPlan` (emparejamiento editable, `SongsterrSoloAssignment`, extras, avisos), `SemitoneSpectrogram` |
| `Sources/TabKit/Score/TabTechniques.swift` | (ADR-017) Adornos: `TabBend` (`paddedForAlphaTab`, `simplified`), `TabGrace`, técnicas de nota y de batería (`TabDrumHit.grace`); `TabTrack.imported` |
| `Sources/TabKit/Score/Tuning.swift` (Fase 5b) | (ADR-017) `TuningPreset.custom/.fixed`, `Tuning.custom(strings:)`, `customLabel` |
| `Sources/TabKit/Audio/SilenceGate.swift`, `Drums/DrumCymbalSeries.swift` | (ADR-017) Puerta de silencio a −60 dBFS; platos en series → charles abierto; `TabTrackBuilder.guitarPitchCeiling` (MIDI 86, `parametersVersion` 3) |
| `Sources/TabKit/Bridge/AlphaTabScore.swift`, `Synth/TabSynthRenderer.swift` (Fase 5b) | (ADR-017) Adornos al JSON de alphaTab y al `.gp`; suenan P.M., staccato, muteadas, ghost, acentos, bends, palanca y vibrato |
| `Tests/TabKitTests/` (Fase 5b) | (ADR-017) `Songsterr*Tests` (conversor, alineador, rejilla, tempo escrito, plan, técnicas, solos), `AlphaTabTechniquesTests`, `SilenceGateTests`, `DrumCymbalSeriesTests`, `TuningCustomTests`; puertas reales con `TF_P5B_TESTS=1` y datos de `P5BProjects.swift` (`TF_P5B_PROJECTS`) |
| `Tests/TabKitTests/` | Tests de Basic Pitch (paridad con Python en fixtures; pesado con `TF_MODEL_TESTS=1`) y del clasificador; Fase 5: `TabGridTests`, `TabQuantizeTests`, `TabTempoDriftTests`, `TabFingeringTests`, `TabEditorTests`, `TabFingerprintTests`, `TabSynthTests`, `AlphaTabScoreTests`, `DrumTranscriberTests`, `DrumHeavyModelTests` (con `Fixtures/drums/`) |
| `Sources/TabKit/Score/TabScore.swift`, `TabTrackNames.swift` (Fase 5c) | (ADR-019) `TabTrackKind.vocal` (solo pentagrama, altura MIDI), `TabTrack.program: Int?`, `TabScore.trackDisplayNames`; `TabTrackNames` (`defaultName`, `resolve`: nombre de Songsterr o instrumento, con número si se repite) |
| `Sources/TabKit/Songsterr/` (Fase 5c) | (ADR-019) `SongsterrTrack.resolvedNames`, `SongsterrTrackConverter.isVocal` (GM 52–54 o nombre), `SongsterrImportPlan.trackNames` |
| `Sources/TabKit/Synth/TabSynthRenderer.swift` (Fase 5c) | (ADR-019) `instrument(for:)`, `vocalProgram` (53 por defecto); internos: adornos de la Parte 1 (canal y sampler por cuerda con curvas, flams 30 ms antes del pulso) y ligadura (`Link.tie`, `inheritingTies`) |
| `Sources/TabKit/Score/TabOrnaments.swift`, `TabEditor.swift`, `TabTechniques.swift` (Fase 5c) | (ADR-019) `TabOrnament` y extensión de `TabEditor`: `toggle(_:trackID:noteIDs:)`, `toggle(_:trackID:hitPoints:)`, `noteIDs(in:trackID:)`, `hitPoints(in:trackID:)`, `bendCycle`, `whammyVibrato`, `graceFretsBelow`, `setGraceFret(_:trackID:noteID:)`; `TabTechniques.tieDestination`, `TabEditError.noTieOrigin` |
| `Sources/TabKit/Score/TabSpan.swift` (Fase 5c) | (ADR-019) `TabSpan`: tramo de pulsos seleccionado (Parte 2) |
| `Sources/TabKit/Bridge/AlphaTabScore.swift` (Fase 5c) | (ADR-019) JSON v1: `kind:"vocal"`, `program`, notas con `p`, `tie` → `isTieDestination` |
| `Sources/TabKit/Synth/TabSynthRenderer.swift`, `SamplerTabSynth.swift` (Fase 7c, paso 6) | (ADR-020) Protocolo interno `TabSynthBackend`: `SamplerTabSynth` en Mac (el sampler de antes) y `PendingTabSynth` en Windows (`[paso 7] sintetizador`). `melodicBankMSB` (0x79) y `percussionBankMSB` (0x78), con test contra AudioToolbox. Espectrograma de batería sobre `NativeDSP` (6,4e-7); lectura de audio con `NativeAudioFile.readMono`. En Windows, `BasicPitchTranscriber` solo tiene `init(modelURL:)` y los transcriptores son stubs `[paso 7]` onnx-runtime; `MonoAudio` depende del remuestreador (stub) |
| `Tests/TabKitTests/` (Fase 5c) | (ADR-019) `TabSpanTests`, `TabSynthAdornmentTests`, `TabSynthTieTests`, `TabVocalTests`, `TabVocalRealTests` (`TF_P5B_TESTS=1`), `TabOrnamentsTests` |

## Packages/VideoKit

Captura y montaje de vídeo (ADR-015). No depende de AudioKit: la app hace de puente.

| Fichero | qué hace (ADR-015): APIs públicas |
| --- | --- |
| `Sources/VideoKit/HostTimeMap.swift` | `HostClock` (ticks ↔ segundos de host) y `HostTimeMap`: ancla del reproductor (`Anchor`) + puntos del reloj de salida; `songTime(atHostSeconds:)`, `hostSeconds(atSongTime:)`, `outputSample(atHostSeconds:)` |
| `Sources/VideoKit/CameraDevice.swift` | `CameraDevice`, `CameraFormat`, `FrameRateRange`, `CameraKind`, `CameraRequest`, `VideoFormat`; `CameraProviding` con `AVCameraProvider` (real, `ensureAccess()`) y `SimulatedCameraProvider`; un solo manejador de cambios (`setChangeHandler`) |
| `Sources/VideoKit/CameraCapture.swift` | `CameraCapture` (`start(_:onFrame:)`, `stop()`), `CameraFrame` con marca de host, `CameraError`; `AVCameraCapture` (real) y `SimulatedCameraCapture` (retardo, jitter y fotogramas perdidos) |
| `Sources/VideoKit/VideoTakeWriter.swift` | `VideoTakeWriter`: `AVAssetWriter` HEVC con PTS = tiempo del tema, sin aplicar el desfase manual |
| `Sources/VideoKit/VideoTakeRecorder.swift` | `VideoTakeRecorder`: une captura, `HostTimeMap` y escritor; graba fotogramas en tiempo del tema |
| `Sources/VideoKit/TakePreview.swift` | `TakePreview.load(audioURL:songStart:videoURL:punches:)`, `pieces(videoOffset:punchOffsets:)` y `composition(videoOffset:punchOffsets:)`: vídeo + toma procesada con desfase y punches, sin recodificar; `PreviewPunch`, `PreviewPiece` |
| `Sources/VideoKit/GuitarFramer.swift`, `GuitarFramer+Vision.swift` (Fase 7) | (ADR-018) Encuadre: `PoseJoint`, `PosePoint`, `PoseSample`; `GuitarFramer.box(joints:)`, `analyze(samples:frameWidth:frameHeight:fingerprint:)` (caja fija y trayectoria suavizada), `crop(box:frameSize:aspect:)`, `fingerprint(video:)` (incluye el giro si no es 0°); la extensión con Vision lee la pose de los fotogramas; `GuitarFramerError` |
| `Sources/VideoKit/MontagePlan.swift` (Fase 7) | (ADR-018) Plan de entrada, con tipos propios: `MontageSpan`, `MontageCanvas` (`landscape`, `portrait`), `MontageLayoutKind` (cinco layouts; `isSingle`, `honorsVideoAspect`), `MontageCut`, `FramingBox`, partes, pistas, rótulo; `MontagePlan.singleCutCandidates(at:)` y `singleShots()` |
| `Sources/VideoKit/MontageLayout.swift` (Fase 7) | (ADR-018) `MontageLayout.rects(_:count:canvas:…)`: geometría de cada layout sin solapes |
| `Sources/VideoKit/MontageTimeline.swift` (Fase 7) | (ADR-018) Estado de los recuadros en `t`: `MontageTimeline` (`Part.coverage()`, `singleAppearances`, `imageBrightness`, `singleShots()`), `MontageBoxState` (`opacity`, `blur`, `crop`, `brightness`), `MontageFrameState`, `MontageShot`, tiempos de fotograma |
| `Sources/VideoKit/MontageAudioEnvelope.swift` (Fase 7) | (ADR-018) `MontageAudioEnvelope.gain(_:at:timeline:)`: curva de los fundidos de audio, común a la vista previa y la exportación |
| `Sources/VideoKit/MontageCompositor.swift` (Fase 7) | (ADR-018) `MontageCompositor` (`AVVideoCompositing`, Core Image): dibuja recuadros, relleno difuminado, fundido a negro y rótulo |
| `Sources/VideoKit/MontageBuilder.swift` (Fase 7) | (ADR-018) `MontageBuilder.load(_:includeAudio:)` y `make(renderSize:includeAudio:)` → `MontagePreview` (`composition`, `videoComposition`, `audioMix`, `makePlayerItem()`, `songTime(itemTime:)`, `itemTime(songTime:)`); `MontageError` |
| `Sources/VideoKit/MontageExporter.swift` (Fase 7) | (ADR-018) `MontageExporter.export(plan:mixURL:settings:to:…)` con `AVAssetReader`/`AVAssetWriter` (audio AAC); `MontageExportSettings` (`codec`, tamaño, `fps`, `container`), `MontageCodec`, `MontageVideoContainer` (MOV, MP4), `MontageExportSummary` |
| `Sources/VideoKit/LoadedTakeVideo.swift` (Fase 7) | (ADR-018) Interno: `LoadedTakeVideo.load(_:)` carga una toma (base y punches) y da su tamaño ya girado (`MontagePartVideo.rotation`) para la composición |
| `Sources/VideoKit/VideoRotation.swift` (Fase 7) | (ADR-018) `VideoRotation` (0°, 90°, 180°, 270° horario): `init(degrees:)`, `next`, `rotatedSize(_:)`, `transform(naturalSize:)`, `orientation`, `apply(_:)` sobre `CIImage` y `CGImage`; `MontagePartVideo.rotation` |
| `Sources/VideoKit/TakePreview.swift` (Fase 7) | (ADR-018) Aplica el giro de la toma con `preferredTransform` |
| `Sources/tf-video/` | Ejecutable de desarrollo, no embebido: `cameras`, `record`, `sync` (medida de fotogramas, jitter, deriva y retardo contra el host) |
| `Sources/tf-video/MontageCommands.swift` (Fase 7) | (ADR-018) `frame` (encuadre de un vídeo: caja, PNG) y `montage` (plan sintético, exportación de pruebas; `--mix`, `--codec`, `--container`) |
| `Sources/VideoKit/MediaFoundationStubs.swift` (Fase 7c, paso 6) | (ADR-020) Solo Windows, API igual que la de Apple: `MediaFoundationCameraProvider` (sin cámaras), `MediaFoundationCameraCapture` y `VideoTakeWriter` (lanzan `paso 7: media-foundation`); `MontageExporter.export` (comprueba la extensión y lanza media-foundation); `MontageBuilder.load` (lanza `paso 7: direct2d`; `renderSize` sí funciona); `GuitarFramer.analyze` (lanza `paso 7: encuadre`) |
| `Sources/VideoKit/` costuras (Fase 7c, paso 6) | (ADR-020) `public typealias FramePixelBuffer` (= `CVPixelBuffer` en Mac, clase vacía en Windows) en `CameraFrame.pixelBuffer`. `VideoKit.HostClock` delega en `NativePlatform.HostClock` (API pública igual). `MontagePlan.frameTicks(fps:)` (interno, sin CoreMedia). `GuitarFramer.fingerprint` con swift-crypto en Windows. Solo Apple (sin clase en Windows): `AVCameraProvider`, `AVCameraCapture`, `TakePreview` (con su `plan`), `MontagePreview`, `MontageCompositor`, `LoadedTakeVideo`, `VideoRotation.transform`. `tf-video` solo Mac (en Windows sale con aviso). La biblioteca sigue sin depender de `AudioKit`; depende de `NativeKit` |
| `Tests/VideoKitTests/SyncPortableTests.swift` (Fase 7c, paso 6) | (ADR-020) `testHostClockIsTheNativePlatformClock` y `testTakesWithoutPlayerLandWithinHalfAFrameWithTheSameOffset` (puerta F6 sin `StudyPlayer`: Mac y VM idénticos, máximo 2,299 ms) |
| `Tests/VideoKitTests/` | 55 tests: `SyncGateTests` (puerta: 3 tomas con cámara simulada), `HostTimeMapTests`, `VideoFileTests`, `TFVideoToolTests`, `VideoKitTests`; Fase 7 (ADR-018): `GuitarFramerTests`, `MontageTimelineTests`, `MontageRendererTests`, `MontageGateTests` (puerta del montaje: portrait y landscape), `MontageSingleCoverageTests`, `MontageCompositionCoverageTests`, `MontageOptionsTests`, `MontageFrameGridTests`, `MontageAudioFadeTests`, `VideoRotationTests` |

## Packages/Store

Archivo de proyecto (JSON por carpeta), índice en SwiftData y orquestación de la biblioteca (ADR-007, ADR-009, ADR-011).

| Fichero | qué hace (ADR-007, ADR-009, ADR-011): APIs públicas |
| --- | --- |
| `Sources/Store/Models.swift` | `Project` (`schemaVersion` 2, `study`; un v1 se lee como v2), `StudyState`, `ChordOverride`, `Loop`, `StemMix`, `PlayerSettings`, `Song` (`origin` opcional), `SongOrigin` (`kind`, `url`, `videoID`, `spotifyID`, `channel`, `album`, `artwork`, `codec`, `ytDlpVersion`, `importedAt`, `playlistID`, `playlistName`; ADR-011), `SeparationState`, `SeparationStatus`, `StemKind`, `Stem` (`isEmpty`, `levelMeasured`), `Guitar`, `Section`, `Rig`, `Take`, `Video` |
| `Sources/Store/Files.swift` | `ProjectFile.load/save` (escritura atómica), `ProjectLayout` (rutas de la carpeta, `analysisCache`), `FolderNaming`, `ProjectCleaner.plan/execute` (`CleanupPlan`), `DiskSize.allocatedBytes`; `ProjectLayout.coverFile` (`source/cover.jpg`) |
| `Sources/Store/EquipmentProfile.swift` | `EquipmentProfile` (`masterGainDB`, `projectsFolder` opcional, `workingSampleRate` 44100 o 48000, guitarras `OwnedGuitar`, `PickupType`) y `ProfileStore` (`load`, `save`) |
| `Sources/Store/AudioSettings.swift` | `AudioSettings` (ADR-012: `outputDeviceUID`, `inputDeviceUID`, `backingOut`, `guitarIn`, `bufferFrames`, `latency`; `validate`, `canRecord`, `calibrationKey(sampleRate:)`, `validLatency(sampleRate:)`, `chooseOutput`, `chooseInput`), `ChannelPair`, `CalibrationKey`, `ReferenceChannel`, `LatencyCalibration`, `AudioSettingsError`, `ClockMode` |
| `Sources/Store/LibraryIndex.swift` | `LibraryEntry` (@Model) y `actor LibraryIndex` (`make`, `rebuild`, `upsert`, `remove`, `entries`) que devuelve `LibraryEntryInfo` Sendable; `ProjectScanner`, `RebuildReport` |
| `Sources/Store/Library.swift` | `actor Library`: `importSong(from:metadata:progress:)` con `ImportMetadata` (título, artista, `SongOrigin` y carátula), `project(withVideoID:)`, `project(withSpotifyID:)`, `trashProject` (Papelera) y `deleteProject` (definitivo, con salvaguarda de ruta), `updateSongInfo`, cola FIFO de separación de uno en uno (`separate`, `cancelSeparation`), `recoverInterrupted` (ahora re-encola las separaciones interrumpidas en vez de marcarlas fallidas), `stopAllForShutdown`, `removeOrphanTemporaries(in:)`, `open` (reconversión de frecuencia en segundo plano), `cleanup`, `cleanupAll`, `diskUsage`, `relocate(to:mode:)` (`.pointOnly`/`.move`), `events`. `saveStudy`, `ensureAnalysis` (→ `AnalysisState`), `needsReseparation`; mide los stems tras separar y al abrir, y analiza tras la separación. Protocolos `AudioImporting`, `StemSeparating`, `StemLevelMeasuring` y `StudyAnalyzing`, que implementa la app |
| `Sources/Store/EquipmentProfile.swift` (Fase 3) | `EquipmentProfile.audio: AudioSettings?` (ADR-012) |
| `Sources/Store/Models.swift`, `Files.swift`, `Library.swift` (Fase 3) | `Take` con campos nuevos opcionales (`songStart`, `sampleRate`, `latencySamples`, `rigDelaySamples`, `rigDelayReliable`, `latencyCalibrated`, `calibrationKey`, `clock`); `ProjectLayout.processedURL(takeId:)` (`takes/<id>/processed.wav`); `Library.saveTake(id:take:)` y `saveTakes(id:_:)` |
| `Sources/Store/Guitars.swift` (Fase 4) | (ADR-014) `GuitarOptions` (`stereoSplit`, `soloSpans`), `GuitarSettings`, `GuitarSoloSpan`, `Guitar` (`role`, `name`, `file`, `confidence`), `GuitarRole` (rhythm, left, right, lead; `fileName`), `GuitarConfidence`, `GuitarAppliedState`, `GuitarSplitState`, `SeparatedGuitar`, `GuitarSplitResult` y el protocolo `GuitarSplitting` |
| `Sources/Store/SectionEditor.swift` | (ADR-014) `SectionEditor`: `mark`, `rename`, `setSolo`, `remove`, `setColor`, `paletteIndices`, `setEdge`, `snapEdge`, `nudgeEdge`; longitud mínima 0,5 s |
| `Sources/Store/Library.swift` (Fase 4) | `saveGuitarNames`, `saveGuitarStereoSplit`, `guitarSplitState`; paso `splitGuitars` en la cola tras el análisis. `Section` gana `color` y `isSolo` |
| `Sources/Store/Recording.swift` (Fase 6) | (ADR-015) `RecordingState` (`parts`, `mix`, `startSectionID`, `countIn`, `preRollBars`), `RecordingPart` (`id`, `name`, `replaces`, `isLead`, `takeIDs`, `bestTakeID`), `TakePunch` |
| `Sources/Store/VideoSettings.swift` (Fase 6) | (ADR-015) `VideoSettings` (`cameraUID`, `resolution`, `fps`, `offsets` por cámara, `export`), `VideoExportDefaults`; `EquipmentProfile.video` |
| `Sources/Store/Models.swift`, `Files.swift`, `Library.swift`, `EquipmentProfile.swift` (Fase 6) | (ADR-015) `Take` gana `partID`, `videoFile`, `videoOffset`, `videoFormat`, `punches`, `baseProcessedFile`; `Project.recording`; `ProjectLayout.videoURL(takeId:)`, `baseProcessedURL(takeId:)`, `punchDirectory(takeId:n:)`; `Library.saveRecording` y `deleteTake` (la quita de su parte y reasigna la mejor) |
| `Tests/StoreTests/RecordingTests.swift` | (ADR-015) Campos nuevos, proyectos y perfiles anteriores, borrado de tomas |
| `Sources/Store/Montage.swift` (Fase 7) | (ADR-018) `MontageState` (`layout`, `singleRhythmPartID`, `singleCuts`, `caption`, `cutGaps`, `partOrder`, `showPartLabels`, `keepVideoAspect`, `export`, `framing`), `MontageLayoutKind`, `MontageSingleCut` (`normalizedSingleCuts()`), `NormalizedRect`, `FramingMode`, `TakeFraming` (`rotatedClockwise(quarterTurns:)`), `FramingOffset`; `Library.saveMontage` |
| `Sources/Store/Models.swift`, `Files.swift`, `Recording.swift`, `VideoSettings.swift` (Fase 7) | (ADR-018) `Take.videoRotation` y `rotationDegrees`; `VideoSettings.rotations`, `defaultRotation(for:)`, `setDefaultRotation`, `normalizedRotation(_:)`; `RecordingState.partMix`; rutas `framingCacheURL(takeId:)`, `montageVideoURL(layout:)`, `montageTracksDirectory(layout:)`; copias `project.json.bak-AAAAMMDD` y `.lost-<fecha-hora>` al escribir |
| `Tests/StoreTests/MontageTests.swift`, `ProjectBackupTests.swift`, `VideoRotationTests.swift` (Fase 7) | (ADR-018) Estado del montaje y compatibilidad hacia atrás; copias `.bak`/`.lost` (`testWriteLosingTabSourceCreatesLostCopy`); rotación por cámara y por toma |
| `Sources/Store/LibraryIndexJSON.swift`, `PlatformPaths.swift`, `WindowsFileMove.swift` (Fase 7c, paso 6) | (ADR-020) `LibraryIndex` con dos implementaciones: SwiftData en Apple y `Library.json` en Windows (caché reconstruible, unos 250 B por tema); en Windows no existe `LibraryEntry`. `PlatformPaths` (interno) elige rutas por sistema. `windowsMoveReplacing` (interno, `MoveFileEx` con `MOVEFILE_REPLACE_EXISTING`, porque `replaceItemAt` aborta en Windows). La Papelera de reciclaje es un stub `[paso 7]`. swift-crypto en Windows |
| `Tests/StoreTests/HashTests.swift` (Fase 7c, paso 6) | (ADR-020) Vectores SHA-256 conocidos: mismos hashes en Apple y Windows. En Windows 201 pasados y 1 salto `[windows]` (`RelocateTests.testMoveFailureMidwayKeepsOriginal`) |
| `Tests/StoreTests/` | 166 tests (`AudioSettingsTests`: ajustes de audio y caducidad de la calibración; `StudyQueueTests`: cola, stems vacíos, v1 → v2; `OriginTests`: origen, duplicados, importación con metadatos; `TrashTests`: Papelera, borrado y edición; `RecoveryTests`: re-encolado al arrancar; Fase 6: `RecordingTests`) |

Fase 6 (ADR-015): la carpeta de proyecto añade `takes/<id>/video.mov`, `takes/<id>/base/processed.wav` (toma original antes de un punch) y `takes/<id>/punch-<n>/`.
| `Sources/Store/Files.swift` (Fase 5) | (ADR-016) `ProjectLayout.tabDir`, `tabScoreFile` (`tab/score.json`), `tabCacheDir` (`cache/tab/`), `tabSynthURL(trackID:)` |
| `Sources/Store/TabSources.swift` | (ADR-016) `TabSource` (`id`, `name`, `kind` guitar/bass/drums, `relativePath`, `playerTrackID`) y extensión de `Project` que lista las pistas de la tablatura según `GuitarSettings` y stems no vacíos; probado en `TabSourcesTests` |
| `Sources/Store/TabSourceChoice.swift` | (ADR-017) `TabSourceChoice` (`.songsterr(songId, revisionId, pairings: [TabStemPairing])` o `.automatic`), `TabStemPairing` (`stemID`, `partId`, `solos`); `Project.tabSource`, `Library.saveTabSource`, `ProjectLayout.songsterrCacheDir` y `tabSongsterrGridFile` (`tab/songsterr-grid.json`). Probado en `TabSourceChoiceTests` |
| `Sources/Store/TabSources.swift` (Fase 5c) | (ADR-019) `TabSource.Kind.vocal`, `Project.vocalTabSource(fileExists:)` (vincula la vocal al stem `vocals`); probado en `TabSourcesTests` |

Carpeta de proyecto: `project.json`, `source/original.<ext>`, `audio/song.wav` (regenerable), `stems/<stem>.wav` (regenerable), `stems/.partial`, `takes/` (`takes/<id>/processed.wav`, ADR-013), `tab/score.json` (tablatura con ediciones; no es caché, ADR-016), `video/`, `rigs/`, `cache/` (regenerable; `cache/analysis.json` es el análisis automático con huella; `cache/tab/` los WAV sintetizados). Perfil e índice en `~/Library/Application Support/ToneForge/` (`profile.json`, `Library.store`). Límite conocido: en la reconversión la sustitución es atómica por fichero, no entre ficheros; `project.json` se actualiza al final y, si falla a mitad, se reintenta al abrir.

## Packages/NativeKit

Capa de plataforma del port a Windows (paquete nuevo, Fase 7c paso 6, ADR-020). Lo usan casi todos los demás paquetes; en el Mac delega en Apple, en Windows usa código C vendorizado (fuentes con su licencia, sin binarios en git).

| Fichero | qué hace (ADR-020): APIs públicas |
| --- | --- |
| `Sources/CPocketFFT/` | pocketfft (BSD-3) en C: FFT real y compleja para el motor portátil |
| `Sources/CDrAudio/` | dr_wav 0.14.7, dr_flac 0.13.5 y dr_mp3 0.7.5 (`dr_audio.c`, cabecera `CDrAudio.h`) |
| `Sources/CMiniz/` | miniz 3.0.2 (MIT); `SourceKit` lo usa para el deflate crudo de Songsterr (`tinfl_decompress_mem_to_heap`) |
| `Sources/NativeDSP/Types.swift`, `AccelerateDSP.swift`, `PortableDSP.swift`, `PortableDFT.swift`, `README.md` | Fachada `DSP` con 46 operaciones de vDSP/vForce y vImage 16F: `DSPAccelerate` (Mac, pasa directa a vDSP) y `DSPPortable` (Swift + pocketfft, Windows; en el Mac se prueba contra vDSP operación por operación). DFT y biquad como clases `DSP.RealDFT`, `ComplexDFT`, `ComplexDFTD` y `Biquad` (el biquad portátil usa `Double`). La tabla de operaciones está en el `README.md` |
| `Sources/NativeAudioFile/NativeAudioFile.swift` | `NativeAudioFile.read`, `readMono` y `write` (`WAVSampleFormat`), `DecodedAudio`, `AudioFileError`; `AVAudioFile` en Mac y dr_* en Windows |
| `Sources/NativeAudioFile/AudioFileIO.swift` | `AudioFileReader` (`init(url:)`, `read(into:maxFrames:)`, `read(maxFrames:)`, `seek(toFrame:)`) y `AudioFileWriter` |
| `Sources/NativePlatform/HostClock.swift` | `HostClock`: `now`, `seconds(ticks:)`, `ticks(seconds:)`, `nanoseconds(ticks:)`, `nowSeconds`, `timebase`; `mach_absolute_time` en Mac y QPC en Windows, con la misma unidad |
| `Sources/NativePlatform/ChildProcess.swift` | `ChildProcess` (`run`, `terminate(grace:)`, `kill`, `waitUntilExit`, `terminationStatus`, `terminationReason`): grupo de procesos con SIGTERM → SIGKILL en Mac; Job Object `KILL_ON_JOB_CLOSE` en Windows (código 143, sin parada ordenada). `terminatedExitCode` 143 y `killedExitCode` 137 |
| `Sources/NativePlatform/SupportFolder.swift`, `PlatformError.swift` | `SupportFolder.base` y `toneForge` (`Application Support` o `%LOCALAPPDATA%\ToneForge`); `PlatformError.unsupported("paso 7: <pieza>")`, el error de los stubs de Windows |
| `Tests/NativeKitTests/` | `DSPEngineTests` y `DSPCases` (58 casos frente a vDSP; FFT ≤ 7,1e-8), `DSPReferenceData` (referencias regenerables con `TF_NATIVEKIT_WRITE_REFS=1 Tools/test.sh NativeKit WriteReference`), `AudioFileAndProcessTests` (WAV24 y FLAC Δ0, MP3 ≤ 3,1e-5), `PlatformTests`. Mac 21 tests (1 salto); VM 12 en ARM64 y x64 |

## App

Proyecto Xcode generado con XcodeGen (`App/project.yml`; el `.xcodeproj` también está versionado). macOS 15+, arm64, Swift 6, bundle id `local.toneforge.ToneForge`, firma automática con el equipo personal, sin sandbox (ADR-007).

| Fichero | qué hace (ADR-007) |
| --- | --- |
| `App/project.yml` | Definición XcodeGen, esquema `ToneForge`, Info.plist con permisos de cámara, micrófono y red local, y fase de script que compila `tf-separate` en release, lo copia a `Contents/MacOS/` y lo firma; fase «Embed helpers» (ADR-011) que copia yt-dlp, Deno y ffmpeg de `Vendor/helpers/` a `Contents/MacOS/` y los firma, y falla nombrando el script si falta la carpeta; el catálogo de iconos |
| `App/Sources/Adapters.swift` | `AppAudioImporter` (sobre `AudioImporter`) y `AppStemSeparator` (sobre `SeparationRunner`, `SeparationFailure`); `AppStemLevelMeter` (sobre `StemLevelMeter`) y `AppStudyAnalyzer` (BeatAnalyzer + ChordRecognizer + KeyDetector sobre `ModelStore`) (ADR-009) |
| `App/Sources/AppModel.swift` | `AppModel` (`@Observable @MainActor`); `LaunchOptions` solo en DEBUG: `--support-dir`, `--projects-folder`, `--install-model-from` (repetible), `--import`, `--screen`, `--project`, `--seek`, `--loop`, `--rate`, `--mute`, `--transpose`, `--capo`, `--analysis-state`, `--snapshot`, `--snapshot-delay`, `--chords-expanded`, `--chords-edit`, `--grid-hit-selftest`, `--link-import-demo`, `--detail-edit`, `--delete-dialog`; Fase 3 (ADR-013): `--screen settings-audio` (dispositivos simulados), `--screen calibration-sheet` y `--screen backing-ab`. Fase 3: `profile.audio`, `outputSelection`, proveedor de dispositivos, `audio` (`AudioController`) y `showCalibrationSheet`. Fase 2b (ADR-011): `linkImport` y `playlistImport` (la cola vive aquí), `trashRequest` (`requestTrash`, `performTrash`, `performDelete`), `updateSongInfo`, `toolsInfo`, `updateYtDlp`, `revertYtDlp`, comprobación de repetidos (`scanLibraryIDs`), y al salir cancela todo y mata los procesos hijos (tope 3 s); al arrancar limpia temporales huérfanos |
| `App/Sources/LinkImportSheet.swift` | `LinkImportSession` (estados de la hoja: enlace, resolviendo, candidatos, descarga, error; `Hooks`, `LibraryLookup`, `ExistingTrack`), `SourceMessages` (mensajes de la tabla de errores) y `LinkImportSheet` (ADR-011) |
| `App/Sources/PlaylistImport.swift` | `PlaylistImportSession` (pasos temas, candidatos, cola y resumen; la cola vive en `AppModel`) y `PlaylistImportView` (ADR-011) |
| `App/Sources/ExternalSources.swift` | `ExternalSources`: cablea SourceKit (`HelperLocator`, `YtDlpUpdater`, importadores) con la app; `ExternalToolsInfo`, `LiveYtDlpRunner`, `PossibleDuplicate` (aviso suave por título y artista), `CoverConverter`, extensión de `SongOrigin` (ADR-011) |
| `App/Sources/LinkImportDemo.swift` | Solo DEBUG: `--link-import-demo <caso>` abre la hoja con fuentes simuladas (`DemoSources`, `DemoHTTP`) para capturas |
| `App/Sources/RootView.swift` | `RootView`, `Sidebar`, `FirstRunSheet` (pregunta la carpeta de proyectos; propone `~/Music/ToneForge`) |
| `App/Sources/LibraryView.swift` | Pantalla de biblioteca y `ProjectDetailView`; ADR-011: menú «Importar tema» (fichero o enlace), eliminar tema (diálogo Papelera o definitivo) y edición de título y artista en el detalle |
| `App/Sources/SettingsView.swift` | Ajustes: `LibrarySettings`, `GuitarEditor`, frecuencia de trabajo en Audio; bloque «Fuentes externas» (versiones, «Actualizar yt-dlp», «Volver a la embebida») (ADR-011) |
| `App/Sources/BackingView.swift` | `BackingView` y `BackingContent`: pantalla Backing (ADR-009); `SpanishNotes`, `SectionKinds`. Fase 3: aloja los controles de grabación y A/B de `BackingRecord.swift`. `BackingMixer` y `BackingTimeline` reciben cambios menores para el canal de la toma |
| `App/Sources/BackingController.swift` | `BackingController` (`@Observable`): une `StudyPlayer` y `StudySession`; aplica mezcla, ajustes del reproductor, metrónomo y master (`masterGainDB`, `setMaster`, `onMasterChange`). Fase 3: A/B (`compareMode`, `setCompare`, `applyCompareMute`, `liveDifferenceDB`, `refreshLiveDifference`), toma cargada (`loadedTake`, `loadLastTake`, `lastTake`, `takeGainDB`, `takeFaderDB`, `setTakeGain`, `takeError`) y `takesChanged(isNew:)` |
| `App/Sources/BackingTimeline.swift` | `BackingTimelineCard`: secciones (`SectionsLane`, `SectionEditor`), tira de acordes con `ChordEditor` y `ProgressBarView` (slider de posición) |
| `App/Sources/BackingMixer.swift` | `BackingMixer`: canales (`MixerChannel`), master (`MasterChannel`), `MixerToggle`, `Fader`; versión compacta con la rejilla expandida |
| `App/Sources/ChordGrid.swift` | `ChordGridView` (rejilla por compases), `ChordGridLayout`, `ChordGridGeometry` |
| `App/Sources/ChordDiagram.swift` | `ChordDiagram`: diagrama de guitarra de un `ChordShape` |
| `App/Sources/StudySession.swift` | `StudySession` (`@Observable`): estudio del proyecto abierto: `analysis`, `analysisState`, `effectiveChords` (`ChordTimeline` con los overrides), `effectiveKey`, `beats`, `audibleStems`, `emptyStems`; ediciones (overrides, tonalidad, secciones, bucles, mezcla, `updatePlayer`) guardadas en `project.json` con rebote de 0,5 s; `flush()`. Fase 3: `playableTakes`, `saveTakes(_:)` y `takeSaveError` |
| `App/Sources/StudyBridge.swift` | `StudyBridge`: conversión entre Store y StudyKit (`ChordOverride` choca de nombre y el enum `StudyKit` tapa el módulo, por eso importa solo StudyKit) y a AudioKit (`clicks`); `nearestBeat`, `snap` |
| `App/Sources/AudioDeviceMonitor.swift` | `AudioDeviceMonitor` (antes `FlexPrimeMonitor`, ADR-012): estado del dispositivo de salida elegido en la barra lateral, actualizado por la notificación de cambios de CoreAudio; sin lógica por nombre |
| `App/Sources/AudioSettingsView.swift` | Ajustes · Audio (ADR-013): `AudioSettingsView`, `AudioDeviceList`, `ChannelChoices`/`ChannelChoice`, `InputMeters`; selectores de entrada y salida, canales de guitarra y backing, frecuencia y estado de la calibración |
| `App/Sources/AudioController.swift` | `AudioController` (`@Observable @MainActor`): dueño de la `AudioSession`, abre y cierra según los ajustes, calibra (`CalibrationSummary`, `CalibrationOutcome`) y reaplica la calibración guardada |
| `App/Sources/AudioBridge.swift` | `AudioBridge`: conversión entre Store y AudioKit (`AudioSettings` ↔ `AudioSetup`, claves de calibración, `Take` ↔ `RecordedTake`) |
| `App/Sources/CalibrationSheet.swift` | `CalibrationSheet`: hoja de calibración con instrucciones del cable, progreso y resultado (latencia en ms, dispersión, motivo del fallo) |
| `App/Sources/BackingRecord.swift` | Controles de grabación y A/B en Backing: `RecordButton`, `RecordStatus`, `ComparePanel`, `TakeChannel` (canal de la toma en la mezcla) |
| `App/Sources/AudioDemo.swift` | Solo DEBUG: `AudioDemo` y `PacedSimulatedIO` para capturas y pruebas visuales con audio simulado |
| `App/Resources/Models/BTC_large_voca_fp16.mlpackage.zip` | Recurso: BTC embebido (5,4 MB, ADR-009) |
| `App/Sources/GuitarBridge.swift` | (ADR-014) `makeLeadSeparator(modelStore:)` y `AppGuitarSplitter` (sobre `GuitarSplitting`: `GuitarStemComposer` + `CoreMLLeadSeparator`) |
| `App/Sources/GuitarOptionsViews.swift` | (ADR-014) `GuitarStereoToggle` («Guitarras en L y R»), `SectionApplyButtons` («Aplicar» / «Descartar»), `GuitarStatusView` |
| `App/Sources/SectionBoxes.swift`, `SectionGridBoxes.swift` | (ADR-014) Cajas de secciones sobre la tira de acordes, compacta y expandida: `SectionBoxes`, `SectionPopover`, `SectionMenu`, asas, ◀ ▶, Supr (`SectionKeyMonitor`), colores `TF.sectionPalette` |
| `App/Sources/BackingMixer.swift` (Fase 4) | (ADR-014) un canal por guitarra (`guitarChannel`) con nombre editable y confianza; sin stems vacíos; plegado en columnas nombre + M/S. Sin grabación ni A/B en Backing: `BackingRecord.swift`, `loadLastTake`, `setCompare` y `AudioController.bind` quedan sin uso desde la UI hasta la Fase 6 |
| `App/Resources/Models/BasicPitch_nmp.mlpackage.zip`, `LeadRhythmMelRoformer_fp16.mlpackage.zip` | (ADR-014) Recursos: Basic Pitch (116 KB) y lead/rhythm (156 MB) |
| `App/Sources/VideoSettingsView.swift` (Fase 6) | (ADR-015) Ajustes · Cámara y vídeo: cámara, resolución, fps, desfase por cámara y exportación por defecto |
| `App/Sources/RecordController.swift`, `RecordTiming.swift` (Fase 6) | (ADR-015) Flujo de grabación (cuenta, margen, audio y vídeo, punch-in, partes y tomas, re-sondeo de cámaras cada 2 s) y cálculo de tiempos en compases |
| `App/Sources/RecordView.swift`, `RecordMixer.swift` (Fase 6) | (ADR-015) Pantalla Grabar (vídeo lo más grande, sin scroll en 16:9; panel «Partes») y mezclador compacto por defecto con los canales «Tú · parte» |
| `App/Sources/OffsetSheet.swift`, `PunchTimeline.swift` (Fase 6) | (ADR-015) Hoja «Ajustar desfase» (±500 ms, ±1 fotograma, ±1 ms) y línea de tiempo para marcar el tramo del punch |
| `App/Sources/RecordDemo.swift` (Fase 6) | (ADR-015) Datos simulados en DEBUG. Opciones `--screen settings-video\|record\|record-counting\|record-offset\|record-mixer-expanded` y `--window WxH` |
| `App/Sources/AudioController.swift`, `AppModel.swift`, `RootView.swift`, `SettingsView.swift`, `App/project.yml` (Fase 6) | (ADR-015) `AudioController.takeSink`, pantalla Grabar en la barra lateral, Ajustes · Cámara y vídeo; `project.yml` enlaza VideoKit |
| `App/Sources/TabController.swift` | (ADR-016) Orquestación de la tablatura: transcribe por pista con progreso y huella, guarda `tab/score.json`, edición con deshacer, afinación por pista, sintetizado como pista extra del `StudyPlayer` («Oír transcripción»), cursor y exportación a `.gp` |
| `App/Sources/TabScreen.swift` | (ADR-016) Pantalla Tablatura: pestañas de pista, transporte, «Editar notas», «Exportar a Guitar Pro» |
| `App/Sources/TabWebHost.swift` | (ADR-016) `WKWebView` con alphaTab y puente Swift ↔ JS |
| `App/Sources/AppModel.swift`, `RootView.swift`, `BackingView.swift`, `BackingController.swift` (Fase 5) | (ADR-016) Pestaña Tablatura, acceso desde Backing y opciones DEBUG `--screen tab`, `--tab-track N`, `--tab-edit`, `--tab-listen`, `--tab-export <ruta>`; log con `TF_TAB_LOG` |
| `App/Sources/SongsterrWebLoader.swift` | (ADR-017) Lector de Songsterr con `WKWebView` oculto (`…/song-tab-s<id>`); implementa `SongsterrServing` |
| `App/Sources/TabSourceSheet.swift`, `SongsterrPreview.swift` | (ADR-017) Hoja «Tablatura de Songsterr»: búsqueda, resultados, «Usar esta», enlace pegado, «Transcribir automáticamente», lista de emparejamiento con confianza y avisos; vista previa en `WKWebView` visible (`websiteDataStore .default()`) |
| `App/Sources/TabController.swift`, `TabScreen.swift`, `TabWebHost.swift`, `BackingController.swift`, `Resources/alphaTab/tf-bridge.js` (Fase 5c) | (ADR-019) `TabController`: mute/solo por pista (`isMuted`, `isSolo`, `isDimmed`, `toggleMute`, `toggleSolo`, `syncSynthMix`), `ListenMode`, `listenMode`, `setAllListening`, `synthProgress`, `span`, bucle por selección, `toggleOrnament`, `ornament(forKey:shift:drums:)`, `graceMode`, `source(of:)` con stem de voz. `TabScreen`: M/S por pista, selector «Stems / Transcripción», icono `mic`, «Selección» en el menú de bucle. `BackingController`: estado compartido de mute/solo. `tf-bridge.js`: selección de tramo (resaltado, ⇧clic, arrastre) |
| `App/Sources/SongsterrProbe.swift` | (ADR-017) Opciones DEBUG `--songsterr-probe`, `--tab-songsterr`, `--tab-summary`, `--tab-songsterr-sheet` |
| `App/Sources/StudySession.swift`, `TabController.swift`, `SectionGridBoxes.swift` (Fase 5b) | (ADR-017) `StudySession.metronomeBeats` con la rejilla de Songsterr (Backing y Tablatura); menú «Fuente», `TabController.customTuning(of:)`; `SpaceKeyMonitor` (espacio = play/pausa); arreglo del cursor en `tf-bridge.js` |
| `App/Resources/alphaTab/` | (ADR-016) alphaTab 1.9.0 embebido (MPL-2.0, 2,8 MB con soundfont Sonivox): `alphaTab.min.js`, `tab.html`, `tf-bridge.js` (construye el `Score` desde el JSON v1), `font/`, `soundfont/`, `VERSION`, licencia |
| `App/Resources/Models/ADTOF_FrameRNN_fp32.mlpackage.zip` | (ADR-016) Recurso: ADTOF (1,7 MB) |
| `App/Sources/MontageView.swift` (Fase 7) | (ADR-018) Pantalla Montaje: `MontageView`, `MontageContent`; columnas Layout (cinco), Vista previa y Exportación compacta con popover (i) de «Transiciones»; línea de tiempo con carriles arrastrables, carril «Plano» y botones «Encuadre» y «Rotar» |
| `App/Sources/MontageController.swift` (Fase 7) | (ADR-018) `MontageController` (`@Observable`): puente Store → `MontagePlan` y `MontageMixer`, análisis de encuadre, vista previa, exportación con progreso y cancelación, `planeShots`, `cutPartCovered`, rotación por toma |
| `App/Sources/MontagePlanning.swift` (Fase 7) | (ADR-018) Lógica pura: `MontagePlanning.build(project:layout:state:barDuration:…)` → `MontageDraft`, `cutEligibleParts(plan:at:)`, `planeShots(plan:)`; `MontageLane`, `LaneSpan`, `LaneSegment`, `PlaneShot` |
| `App/Sources/MontageFramingSheet.swift` (Fase 7) | (ADR-018) Hoja «Encuadre»: fotograma con la caja, «Seguir la guitarra», zoom y «Restablecer» |
| `App/Sources/MontageAudioTypes.swift`, `MontageVideoTypes.swift` (Fase 7) | (ADR-018) Alias para desambiguar nombres repetidos entre AudioKit, VideoKit y Store: `MixSpan`, `MixSegment` (AudioKit), `VideoSpan`, `VideoLayoutKind` (VideoKit); cada fichero importa un solo módulo |
| `App/Sources/MontageDemo.swift` (Fase 7) | (ADR-018) Solo DEBUG: `--screen montage` con datos sintéticos, `--montage-layout side\|grid\|stack\|single\|single-landscape`, `--montage-export`, `--montage-container`, `--montage-order`, `--montage-no-part-labels`, `--montage-keep-aspect`, `--montage-cuts`, `--montage-neutral` |
| `App/Sources/AppModel.swift`, `AudioController.swift`, `BackingController.swift`, `RecordController.swift`, `RecordTiming.swift`, `RecordView.swift`, `OffsetSheet.swift`, `VideoSettingsView.swift` (Fase 7) | (ADR-018) Cableado del montaje; parada automática al acabar la sección más el margen (`BarTiming.sectionStop`); fader «Tú · parte» restaurado al reabrir; botón «Rotar» en Grabar (inactivo al grabar) y en Ajustes de vídeo |
| `App/Sources/Theme.swift` | `TF`: colores y medidas (ampliado en la Fase 2b) |
| `App/Resources/AppIcon.svg`, `App/Resources/Assets.xcassets/` | Icono de la app (de Jorge): los PNG salen del SVG con `Tools/make-icon.sh`; `project.yml` fija `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` |
| `App/Sources/ToneForgeApp.swift` | Punto de entrada |

## Probes

Sondas de la Fase 0 (`Probes/P<n>-<tema>/`), desechables; resultados en `docs/probes/`.

| Fichero | qué hace (ADR-NNN) |
| --- | --- |
| `Probes/P2-audio-usb/` | Paquete Swift `P2AudioUSB`: CLI `p2` (`Sources/p2`: `Commands`, `HAL`, `Session`) sobre CoreAudio y `P2Core` (WAV, FFT, señales, detectores, analizador, autotest) con `Tests/P2CoreTests`. Audio USB de la Flex Prime (ADR-006) |
| `Probes/P4-modelos/common/{guard,metrics}.py` | `guard.py`: vigilante de memoria (10 GB) obligatorio para procesos pesados; `metrics.py`: SDR y medidas comunes |
| `Probes/P4-modelos/bs_roformer_sw/` | Separador elegido: Core ML publicado de gridshift, CPU+GPU, SDR, retención y comparativas (ADR-004). Resultados en `out/results/` |
| `Probes/P4-modelos/bsroformer_cpp/run.py` | Respaldo BSRoformer.cpp con GGUF q8 en Metal (ADR-004) |
| `Probes/P4-modelos/htdemucs/` | `separate.py` y `report.py`: HTDemucs 6s, solo comparación (ADR-004) |
| `Probes/P4-modelos/btc/run_all.py` | Acordes BTC: referencia PyTorch y Core ML FP16 (ADR-006). Comando: `Tools/py/.venv/bin/python Probes/P4-modelos/btc/run_all.py` |
| `Probes/P4-modelos/beat_this/run_all.py` | Pulso Beat This! con el `mlmodelc` comunitario; `--all` prueba todas las vías (ADR-006). Mismo comando que BTC con su ruta |
| `Probes/P4-modelos/adtof/run_all.py` | Batería ADTOF en Core ML FP32 con GRU nativa; `--convert` la primera vez (ADR-006). Mismo comando con su ruta |
| `Probes/P4-modelos/fixtures/make_fase2_fixtures.py` | Genera los fixtures de `Packages/StudyKit/Tests/StudyKitTests/Fixtures/` (12 s de T1 en WAV de 16 bits y referencias Python) (ADR-009) |
| `Probes/P7-fuentes/` | Sondas de fuentes externas (enlaces de YouTube y Spotify), en scripts numerados (ADR-008); `09-list.sh` a `13-parse-listas.py` son la prueba ampliada: candidatos de cinco temas con `tf-fetch`, descarga con tiempos, restricción de edad, y embeds de lista y álbum con su resumen (ADR-011) |
| `Probes/P6-timepitch/{run.sh,p6.py,AppleRender}` | Comparación ciega de `AVAudioUnitTimePitch` y Rubber Band: `run.sh Probes/testaudio/out/clips/*.wav` (ADR-005) |
| `Probes/P4-modelos/{guitar_models,basic_pitch,lead_rhythm}/` | Fase 4 (ADR-014): modelos de guitarra frente a BS-RoFormer SW (`run_torch.py`, `score.py`, `listen.py`), conversión y paridad de Basic Pitch y del lead/rhythm (`convert.py`, `compare.py`) |
| `Probes/P5b-guitarra/` | (ADR-017) Pruebas de la 5b: evaluación contra Songsterr (`eval_reference.py`) y `check-techniques.js` (46/46 adornos en alphaTab y `.gp`) |
| `Probes/P5c-voces/check-vocal.js` | (ADR-019) Comprobación de la pista de voz en alphaTab |
| `Probes/P5-alphatab/make-spike.js` | (ADR-016) Prueba inicial de alphaTab: partitura de guitarra, bajo y batería exportada a `.gp` |
| `Probes/P4-modelos/adtof/{package.py,make_fase5_fixture.py}` | (ADR-016) `package.py` empaqueta ADTOF para la app; `make_fase5_fixture.py` genera el fixture de `Tests/TabKitTests/Fixtures/drums/` (activaciones y golpes de Python) |
| `Probes/testaudio/prepare.py` | Prepara los temas y tramos de prueba (`out/` ignorado) |

Recursos: modelos y resultados en `Probes/P4-modelos/*/out/` (no versionados); entorno de Python en `Tools/py/.venv`, dependencias fijadas en `Tools/py/requirements.txt`.

## Tools

| Fichero | qué hace |
| --- | --- |
| `Tools/test.sh` | `swift test` de cada paquete + build de la app con salida resumida; escribe `Temp/last-run.txt` en la pasada completa (ADR-003) |
| `Tools/test.sh App` (Fase 6) | Solo el build de la app, unos 5 s en incremental; no escribe `Temp/last-run.txt` (ADR-015) |
| `Tools/win/build.sh` (Fase 7c) | Compila, instala y arranca en la VM de Windows (ADR-020); `--test [--filter X]` hace `swift test` del paquete en ARM64 y x64, sin instalar, con pasados, fallados y saltos (`[paso 7]` pendiente, `[windows]` permanente) y toma él mismo el cerrojo `Temp/win/vm.lock` (`TF_VM_LOCK_WAIT`, 20 min) |
| `Tools/win/remote/test.ps1`, `x64-runtime.ps1` (Fase 7c, paso 6) | `test.ps1` ejecuta `swift test` en la VM y resume su salida; `x64-runtime.ps1` extrae las DLL x64 de `Redistributables\6.4.2\rtl.shared.amd64.msm` a `C:\tf-rtl-x64` (se antepone al PATH solo en x64; `--clean` no lo borra) |
| `Tools/helpers/` | `fetch.sh` (baja y verifica yt-dlp y Deno), `build-ffmpeg.sh` (compila el ffmpeg mínimo) y `versions.env` (versiones y sumas); la salida va a `Vendor/helpers/`, sin versionar (ADR-011) |
| `Tools/make-icon.sh`, `Tools/make-icon.swift` | Generan los PNG del icono de la app a partir de `App/Resources/AppIcon.svg` (de Jorge) |
