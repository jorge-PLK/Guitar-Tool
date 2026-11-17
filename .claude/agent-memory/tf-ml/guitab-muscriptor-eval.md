---
name: guitab-muscriptor-eval
description: Fase 5b, transcripción de guitarra — Guitab corre en el venv sin instalar nada; MuScriptor restringido en HF; trampas de las métricas proxy y del entorno
metadata:
  type: project
---

- **Guitab** (danmor/guitab): no hace falta instalar su requirements (pide torch 2.10/py3.11). Basta con 6 ficheros de
  `guitab/` (__init__, audio, guitar, inference, model, paths) en un commit fijo + pesos en `<raíz>/weights/` (paths.WEIGHTS =
  parents[1]/weights; si el fichero existe, `fetch` no descarga). Corre con torch 2.7 / librosa 1.0 del venv.
  `load_model(...).decoding` trae la decodificación propia del checkpoint (E25 onset 0,45). Ver Probes/P5b-guitarra/fetch.py.
- Guitab solo emite MIDI 40–83 (EADGBE, trastes 0–19): el % de registro sale 100 % por construcción; no sirve como
  criterio de puerta frente a Basic Pitch.
- En eléctrica distorsionada, la mayoría de notas de Guitab duran 1 trama (cabeza de cuerda activa < frame 0,6): mirar
  la distribución de duraciones antes de fiarse de métricas ponderadas por duración.
- **MuScriptor** (HF MuScriptor/*): gated «auto», 401 sin token. Aceptar la licencia exige la cuenta de HF de Jorge y
  condiciones legales: no lo aceptes tú; pídeselo (HF_TOKEN). No hay token en la máquina (2026-11-16).
- **RemFX** (quitar distorsión): no instalar el paquete (pide tensorflow, wandb…). El modelo de distorsión es
  `torchaudio.models.HDemucs(sources=["mixture"], audio_channels=1, nfft=4096, channels=48)` a 48 kHz; claves
  `model.model.*` del ckpt de Zenodo (carga con weights_only=True). Ver Probes/P5b-guitarra/remfx_clean.py.
- Basic Pitch saca notas basura de hasta minutos sobre silencio digital exacto (stems guitar_lead con ceros):
  filtrar por actividad antes de medir polifonía o registro.
- Trampas de herramienta: el venv está en el repo principal (`/Volumes/SSD Mac/Personales/Guitar Tool/Tools/py/.venv`),
  no en el worktree. Un script de scratch llamado `inspect.py` tapa el módulo de la stdlib (numpy lo importa):
  nombres únicos. El sandbox rechaza `python -c` con varias líneas y pipes con `|` hacia python: usar ficheros.
  Los subagentes no pueden escribir informes .md (la herramienta lo bloquea): el informe va en la respuesta.

**Why:** costó varios turnos ver que el venv y la puerta de registro no eran lo que parecían.
**How to apply:** reutilizar Probes/P5b-guitarra/run.py (`--song`, `--models`, variantes `guitab_e25_fNN`). Ver
[[basic-pitch-contract]], [[coreml-env-traps]].
