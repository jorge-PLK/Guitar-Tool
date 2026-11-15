# ToneForge · Mapa del código

Última actualización: 2026-11-15 · Fase 2 · Herramienta de estudio (ADR-009).

Una sección por paquete (nombres de `docs/plan.md`, «Forma de trabajo»), más la app, las pruebas y las herramientas. Fila por fichero: `| Fichero | qué hace (ADR-NNN): APIs públicas |`. Se lee por secciones: `grep -n '^## ' docs/CODEMAP.md`.

## Packages/AudioKit

E/S de audio y reproducción: importación (ADR-007) y reproductor de estudio (ADR-009).

| Fichero | qué hace (ADR-007, ADR-009): APIs públicas |
| --- | --- |
| `Sources/AudioKit/AudioImporter.swift` | Convierte WAV, FLAC o MP3 a WAV estéreo float32 a 44100 o 48000 Hz con `AVAudioConverter` en calidad máxima y por bloques. `AudioImporter.importAudio(from:to:sampleRate:progress:)`, `resample(_:to:sampleRate:)`, `metadata(of:)`; `ImportedAudio`, `AudioImportError`. AVFoundation no lee los Vorbis comments de FLAC: el título sale del nombre («Artista - Título.ext») |
| `Sources/AudioKit/StudyPlayer.swift` | `StudyPlayer` sobre `AVAudioEngine` (ADR-009): un `AVAudioPlayerNode` por stem, `AVAudioUnitVarispeed` delante de un `AVAudioUnitTimePitch` (overlap 8) que se reinicia en play, seek y cambios de velocidad o transposición. `load(tracks:)`, `play`, `pause`, `seek(to:)`, `currentTime`, `setGain`, `setMute`, `setSolo`, `masterGainDB`, `meters`, `rate` 0,5…2,0, `pitchCents`, `loop`, `metronome`, `outputDeviceName`; el metrónomo va después del TimePitch |
| `Sources/AudioKit/StudyPlayerTypes.swift` | `Track`, `Click`, `Metronome`, `ChannelMeter`, `StudyPlayerError` |
| `Sources/AudioKit/StemScheduler.swift` | Programa los stems y el bucle encadenado con precisión de muestra y fundidos de 5 ms |
| `Sources/AudioKit/PlaybackTimeline.swift` | Conversión entre tiempo de canción y de salida según `rate` |
| `Sources/AudioKit/ClickRenderer.swift` | Genera los clics del metrónomo en tiempo de salida |
| `Sources/AudioKit/OutputDevices.swift` | Salida Flex Prime (ADR-006): `AudioOutputDevice`, `AudioDeviceProviding`, `OutputRouting.route` (Flex Prime por canales 1/2 si está conectada, si no la salida por defecto), `OutputRoute`, `CoreAudioDeviceProvider`, `SimulatedDeviceProvider` para tests |
| `Tests/AudioKitTests/` | 32 tests (`AudioImporterTests`, `StudyPlayerTests` en render offline). Fixtures en `Fixtures/` (unos 300 KB), con un README de los comandos ffmpeg |

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

Archivo de proyecto (JSON por carpeta), índice en SwiftData y orquestación de la biblioteca (ADR-007, ADR-009).

| Fichero | qué hace (ADR-007, ADR-009): APIs públicas |
| --- | --- |
| `Sources/Store/Models.swift` | `Project` (`schemaVersion` 2, `study`; un v1 se lee como v2), `StudyState`, `ChordOverride`, `Loop`, `StemMix`, `PlayerSettings`, `Song`, `SeparationState`, `SeparationStatus`, `StemKind`, `Stem` (`isEmpty`, `levelMeasured`), `Guitar`, `Section`, `Rig`, `Take`, `Video` |
| `Sources/Store/Files.swift` | `ProjectFile.load/save` (escritura atómica), `ProjectLayout` (rutas de la carpeta, `analysisCache`), `FolderNaming`, `ProjectCleaner.plan/execute` (`CleanupPlan`), `DiskSize.allocatedBytes` |
| `Sources/Store/EquipmentProfile.swift` | `EquipmentProfile` (`masterGainDB`, `projectsFolder` opcional, `workingSampleRate` 44100 o 48000, guitarras `OwnedGuitar`, `PickupType`) y `ProfileStore` (`load`, `save`) |
| `Sources/Store/LibraryIndex.swift` | `LibraryEntry` (@Model) y `actor LibraryIndex` (`make`, `rebuild`, `upsert`, `remove`, `entries`) que devuelve `LibraryEntryInfo` Sendable; `ProjectScanner`, `RebuildReport` |
| `Sources/Store/Library.swift` | `actor Library`: `importSong`, cola FIFO de separación de uno en uno (`separate`, `cancelSeparation`), `recoverInterrupted`, `open` (reconversión de frecuencia en segundo plano), `cleanup`, `cleanupAll`, `diskUsage`, `relocate(to:mode:)` (`.pointOnly`/`.move`), `events`. `saveStudy`, `ensureAnalysis` (→ `AnalysisState`), `needsReseparation`; mide los stems tras separar y al abrir, y analiza tras la separación. Protocolos `AudioImporting`, `StemSeparating`, `StemLevelMeasuring` y `StudyAnalyzing`, que implementa la app |
| `Tests/StoreTests/` | 44 tests (`StudyQueueTests`: cola, stems vacíos, v1 → v2) |

Carpeta de proyecto: `project.json`, `source/original.<ext>`, `audio/song.wav` (regenerable), `stems/<stem>.wav` (regenerable), `stems/.partial`, `takes/`, `video/`, `rigs/`, `cache/` (regenerable; `cache/analysis.json` es el análisis automático con huella). Perfil e índice en `~/Library/Application Support/ToneForge/` (`profile.json`, `Library.store`). Límite conocido: en la reconversión la sustitución es atómica por fichero, no entre ficheros; `project.json` se actualiza al final y, si falla a mitad, se reintenta al abrir.

## App

Proyecto Xcode generado con XcodeGen (`App/project.yml`; el `.xcodeproj` también está versionado). macOS 15+, arm64, Swift 6, bundle id `local.toneforge.ToneForge`, firma automática con el equipo personal, sin sandbox (ADR-007).

| Fichero | qué hace (ADR-007) |
| --- | --- |
| `App/project.yml` | Definición XcodeGen, esquema `ToneForge`, Info.plist con permisos de cámara, micrófono y red local, y fase de script que compila `tf-separate` en release, lo copia a `Contents/MacOS/` y lo firma |
| `App/Sources/Adapters.swift` | `AppAudioImporter` (sobre `AudioImporter`) y `AppStemSeparator` (sobre `SeparationRunner`, `SeparationFailure`); `AppStemLevelMeter` (sobre `StemLevelMeter`) y `AppStudyAnalyzer` (BeatAnalyzer + ChordRecognizer + KeyDetector sobre `ModelStore`) (ADR-009) |
| `App/Sources/AppModel.swift` | `AppModel` (`@Observable @MainActor`); `LaunchOptions` solo en DEBUG: `--support-dir`, `--projects-folder`, `--install-model-from` (repetible), `--import`, `--screen`, `--project`, `--seek`, `--loop`, `--rate`, `--mute`, `--transpose`, `--capo`, `--analysis-state`, `--snapshot`, `--snapshot-delay`, `--chords-expanded`, `--chords-edit`, `--grid-hit-selftest` |
| `App/Sources/RootView.swift` | `RootView`, `Sidebar`, `FirstRunSheet` (pregunta la carpeta de proyectos; propone `~/Music/ToneForge`) |
| `App/Sources/LibraryView.swift` | Pantalla de biblioteca y `ProjectDetailView` |
| `App/Sources/SettingsView.swift` | Ajustes: `LibrarySettings`, `GuitarEditor`, frecuencia de trabajo en Audio |
| `App/Sources/BackingView.swift` | `BackingView` y `BackingContent`: pantalla Backing (ADR-009); `SpanishNotes`, `SectionKinds` |
| `App/Sources/BackingController.swift` | `BackingController` (`@Observable`): une `StudyPlayer` y `StudySession`; aplica mezcla, ajustes del reproductor, metrónomo y master (`masterGainDB`, `setMaster`, `onMasterChange`) |
| `App/Sources/BackingTimeline.swift` | `BackingTimelineCard`: secciones (`SectionsLane`, `SectionEditor`), tira de acordes con `ChordEditor` y `ProgressBarView` (slider de posición) |
| `App/Sources/BackingMixer.swift` | `BackingMixer`: canales (`MixerChannel`), master (`MasterChannel`), `MixerToggle`, `Fader`; versión compacta con la rejilla expandida |
| `App/Sources/ChordGrid.swift` | `ChordGridView` (rejilla por compases), `ChordGridLayout`, `ChordGridGeometry` |
| `App/Sources/ChordDiagram.swift` | `ChordDiagram`: diagrama de guitarra de un `ChordShape` |
| `App/Sources/StudySession.swift` | `StudySession` (`@Observable`): estudio del proyecto abierto: `analysis`, `analysisState`, `effectiveChords` (`ChordTimeline` con los overrides), `effectiveKey`, `beats`, `audibleStems`, `emptyStems`; ediciones (overrides, tonalidad, secciones, bucles, mezcla, `updatePlayer`) guardadas en `project.json` con rebote de 0,5 s; `flush()` |
| `App/Sources/StudyBridge.swift` | `StudyBridge`: conversión entre Store y StudyKit (`ChordOverride` choca de nombre y el enum `StudyKit` tapa el módulo, por eso importa solo StudyKit) y a AudioKit (`clicks`); `nearestBeat`, `snap` |
| `App/Sources/FlexPrimeMonitor.swift` | `FlexPrimeMonitor` (`AppModel.flexPrime`): estado de conexión de la Flex Prime en la barra lateral, con `CoreAudioDeviceProvider` y `OutputRouting.isFlexPrime`, actualizado por la notificación de cambios de CoreAudio |
| `App/Resources/Models/BTC_large_voca_fp16.mlpackage.zip` | Recurso: BTC embebido (5,4 MB, ADR-009) |
| `App/Sources/Theme.swift` | `TF`: colores y medidas |
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
| `Probes/P7-fuentes/` | Sondas de fuentes externas (enlaces de YouTube y Spotify), en scripts numerados (ADR-008) |
| `Probes/P6-timepitch/{run.sh,p6.py,AppleRender}` | Comparación ciega de `AVAudioUnitTimePitch` y Rubber Band: `run.sh Probes/testaudio/out/clips/*.wav` (ADR-005) |
| `Probes/testaudio/prepare.py` | Prepara los temas y tramos de prueba (`out/` ignorado) |

Recursos: modelos y resultados en `Probes/P4-modelos/*/out/` (no versionados); entorno de Python en `Tools/py/.venv`, dependencias fijadas en `Tools/py/requirements.txt`.

## Tools

| Fichero | qué hace |
| --- | --- |
| `Tools/test.sh` | `swift test` de cada paquete + build de la app con salida resumida; escribe `Temp/last-run.txt` en la pasada completa (ADR-003) |
