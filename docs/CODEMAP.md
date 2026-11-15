# ToneForge · Mapa del código

Última actualización: 2026-11-15 · Fase 3 · Audio con el dispositivo (ADR-012, ADR-013).

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
| `Sources/tf-audio/` | Ejecutable de desarrollo, no embebido (`TFAudio`, `Commands`, `Options`, `Rig`): `devices`, `latency` (`--restarts`), `verify`, `record`; `--simulated`; salidas en `Temp/tf-audio/` (incluye `verify-hal.csv`) |
| `Tests/AudioKitTests/` | 90 tests (`AudioImporterTests`, `StudyPlayerTests` en render offline; Fase 3: `AudioRoutingTests`, `AudioSessionTests`, `LatencyCalibratorTests`, `TakeAlignmentTests`, `PlayerHostingTests`, `HostTimingTests`, `FeedbackLoopTests`, `LoudnessMatchTests`, `AppLogicTests`, `TFAudioToolTests`). Fixtures en `Fixtures/` (unos 300 KB), con un README de los comandos ffmpeg |

## Packages/ModelKit

Descarga, verificación y compilación de modelos (paquete añadido en la Fase 1, ADR-007).

| Fichero | qué hace (ADR-007): APIs públicas |
| --- | --- |
| `Sources/ModelKit/ModelDescriptor.swift` | `ModelDescriptor`, `ModelRole`, `ModelArchiveKind` (`zippedCompiledModel`: zip con `.mlmodelc`, no se compila; `bundledZippedMLPackage`: zip de `.mlpackage` dentro de la app, se compila la primera vez) y `ModelCatalog` (`separatorBSRoformerSW`, `beatsBeatThis` (HF `jessengatai/supracut-beat-this`, commit `33fe1a5`), `chordsBTC` (embebido), `all` con los tres): URL, SHA-256 y tamaño (ADR-007, ADR-009) |
| `Sources/ModelKit/ModelStore.swift` | `actor ModelStore`: `ensureInstalled`, `install(_:fromArchive:)`, `delete`, `state`, `states`, `updates`, `diskUsage`; `ModelState`, `ModelError`. El inicializador admite `bundleResourceDirectory` (la app pasa el bundle, los tests un directorio). Descarga, SHA-256, `ditto`, compila y guarda solo el `.mlmodelc` (351 MB) con su `manifest.json` en `Application Support/ToneForge/Models/<id>/` |
| `Sources/ModelKit/Downloading.swift` | Protocolos `ModelDownloading` y `ModelCompiling`; `URLSessionDownloader`; `ModelDownloadError` |
| `Sources/ModelKit/CoreMLCompiler.swift` | `CoreMLCompiler`: `compileModel` (1,7 s; la especialización para la GPU ocurre en la primera carga) |
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
| `Sources/tf-separate/` | Ejecutable `tf-separate` (producto): un proceso por tema, vigilado por `MemoryGuard` |
| `Sources/tf-memhog/` | Ejecutable `tf-memhog`, solo para tests del vigilante |
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

Transcripción y tablatura. Sin código (solo test de humo).

## Packages/VideoKit

Captura y montaje de vídeo. Sin código (solo test de humo).

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
| `Tests/StoreTests/` | 78 tests (`AudioSettingsTests`: ajustes de audio y caducidad de la calibración; `StudyQueueTests`: cola, stems vacíos, v1 → v2; `OriginTests`: origen, duplicados, importación con metadatos; `TrashTests`: Papelera, borrado y edición; `RecoveryTests`: re-encolado al arrancar) |

Carpeta de proyecto: `project.json`, `source/original.<ext>`, `audio/song.wav` (regenerable), `stems/<stem>.wav` (regenerable), `stems/.partial`, `takes/` (`takes/<id>/processed.wav`, ADR-013), `video/`, `rigs/`, `cache/` (regenerable; `cache/analysis.json` es el análisis automático con huella). Perfil e índice en `~/Library/Application Support/ToneForge/` (`profile.json`, `Library.store`). Límite conocido: en la reconversión la sustitución es atómica por fichero, no entre ficheros; `project.json` se actualiza al final y, si falla a mitad, se reintenta al abrir.

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
| `Probes/testaudio/prepare.py` | Prepara los temas y tramos de prueba (`out/` ignorado) |

Recursos: modelos y resultados en `Probes/P4-modelos/*/out/` (no versionados); entorno de Python en `Tools/py/.venv`, dependencias fijadas en `Tools/py/requirements.txt`.

## Tools

| Fichero | qué hace |
| --- | --- |
| `Tools/test.sh` | `swift test` de cada paquete + build de la app con salida resumida; escribe `Temp/last-run.txt` en la pasada completa (ADR-003) |
| `Tools/helpers/` | `fetch.sh` (baja y verifica yt-dlp y Deno), `build-ffmpeg.sh` (compila el ffmpeg mínimo) y `versions.env` (versiones y sumas); la salida va a `Vendor/helpers/`, sin versionar (ADR-011) |
| `Tools/make-icon.sh`, `Tools/make-icon.swift` | Generan los PNG del icono de la app a partir de `App/Resources/AppIcon.svg` (de Jorge) |
