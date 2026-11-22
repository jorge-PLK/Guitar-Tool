# Fase 0 · Pruebas de riesgo

Siete pruebas cortas e independientes, en scripts sueltos (Python o Swift), que deciden el resto del plan. Para la Etapa 1 solo hacen falta P2, P4 y P6; P1, P3 y P5 se dejan para el comienzo de la Etapa 2. P7 se añadió el 15/11/2026 para la Fase 2b (ADR-008).

- [ ] P1 Remote Editor: capturar el tráfico navegador ↔ pedalera y documentar cómo listar rigs, leer un rig, cambiar un parámetro, cargar un rig y subir un NAM o un IR. Anotar la versión de firmware. *Etapa 2.*
- [x] P2 Audio USB: qué canales de entrada y salida expone la Flex Prime, si da el DI seco, si acepta reamp, a qué frecuencia de muestreo trabaja y si el retorno procesado incluye lo que se le envía por USB (el backing). *Superada, sin plan B; ver `docs/probes/P2-audio-usb.md`.*
- [ ] P3 TONE3000: obtener clave, iniciar sesión, buscar en el catálogo por marca y modelo y descargar un .nam y un IR. Anotar límites de uso. *Etapa 2.*
- [x] P4 Modelos: convertir BS-RoFormer SW y BTC a Core ML y comprobar que dan el mismo resultado que el original y a buena velocidad; el que no funcione bien pasa a ONNX Runtime como respaldo. Comparar la separación con HTDemucs 6 stems en 3 temas y medir tiempos. Elegir el modelo de pulso y el de transcripción de batería. *Elegidos BS-RoFormer SW (Core ML publicado, CPU+GPU), BTC, Beat This! y ADTOF; ver `docs/probes/P4-modelos.md`.*
- [ ] P5 Velocidad del bucle: medir cuánto tarda la pedalera en aplicar un cambio de parámetro, en cambiar de bloque y en cargar un NAM, para estimar cuánto dura un igualado. *Etapa 2.*
- [x] P6 Velocidad: comparar la calidad al 50 % de AVAudioUnitTimePitch y de Rubber Band. *Gana `AVAudioUnitTimePitch` con overlap 8; Rubber Band no hace falta; ver `docs/probes/P6-timepitch.md`.*
- [x] P7 Fuentes externas: de un enlace de Spotify a un fichero de audio local sin credenciales, con yt-dlp. *Superada con un tema (18-24 s) y ampliada a 7 temas, con 5 de 7 aciertos en el candidato; Opus → WAV, y Jorge dio por bueno Opus de oído el 15/11/2026; ver `docs/probes/P7-fuentes.md`, ADR-008 y ADR-011. Sin oír los WAV de la prueba ampliada ni cubrir temas sin subida oficial.*

Condición de paso: para la Etapa 1, audio grabado por USB y un tema separado en local; para la Etapa 2, un parámetro cambiado desde script y un reamp grabado. *Etapa 1 cumplida (audio grabado por USB en P2; tema separado en local en `Probes/P4-modelos/bs_roformer_sw/out/stems/T1/`), confirmada por Jorge el 15/11/2026. Etapa 2 pendiente.*

Si falla: P1 → el igualado termina en una guía visual y el rig se carga a mano o por USB Transfer. P2 → interfaz de audio externa. P4 → HTDemucs como separador.
