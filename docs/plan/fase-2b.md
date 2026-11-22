# Fase 2b · Fuentes externas (ADR-008)

Importar temas desde un enlace de YouTube o de Spotify. El audio sale de YouTube con yt-dlp; de Spotify solo se leen metadatos. Probado en P7 (`docs/probes/P7-fuentes.md`) con un solo tema.

- [x] Lectura de metadatos de Spotify (página embed, sin credenciales) *(`SourceKitTests`, 63 tests; embed grabado en P7)*
- [x] Búsqueda en YouTube y selector de candidatos con la diferencia de duración *(`SourceKitTests`; capturas en `Temp/p9/`; prueba ampliada de P7: 5 de 7 aciertan)*
- [x] Descarga Opus → WAV e importación a la biblioteca *(`SourceKitTests`, `StoreTests` 69 tests; prueba ampliada de P7: 5 descargas en Opus, WAV de 48 kHz y 24 bit)*
- [x] Helpers embebidos (yt-dlp, Deno, ffmpeg) y su actualización *(`SourceKitTests` (`HelperLocator`, `YtDlpUpdater`); capturas de Ajustes en `Temp/p9/`)*
- [x] Listas de Spotify y de YouTube y álbumes de Spotify: marcar temas, revisión en lote y cola «Descargar y procesar» *(`SourceKitTests` (`PlaylistTests`); capturas en `Temp/p9/`; embeds de lista y álbum en la prueba ampliada)*
- [x] Repetidos: bloqueo por identificador de Spotify y `videoID`, y aviso suave por título y artista *(`StoreTests` (`OriginTests`); capturas en `Temp/p9/`)*
- [x] Eliminar un tema, editar título y artista, y re-encolar al arrancar las separaciones interrumpidas *(`StoreTests` (`TrashTests`, `RecoveryTests`); capturas en `Temp/p9/`)*

Condición de paso: pegar un enlace de YouTube y otro de Spotify deja cada tema en la biblioteca listo para separar, sin más paso manual que elegir candidato; pegar una lista o un álbum, marcar parte de sus temas y pulsar «Descargar y procesar» los deja importados y separados; y la prueba ampliada con al menos cinco temas (uno sin subida oficial, uno con el directo dominante y uno largo) queda anotada en `docs/probes/P7-fuentes.md` con cuántos aciertan el candidato correcto. *Cumplida el 15/11/2026, confirmada por Jorge en la app (ADR-011). La prueba ampliada (7 temas, 5 aciertos) no cubrió el tema sin subida oficial ni el directo dominante claro.*
