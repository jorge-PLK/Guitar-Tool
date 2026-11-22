# Packages/SourceKit

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
