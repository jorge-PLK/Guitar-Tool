---
name: lead-rhythm-contract
description: Mel-Band RoFormer Lead_Rhythm_Guitar anónimo (HF RandomFilteredStuff): carga segura, trampas (MPS, YAML), cómo se convirtió a Core ML sin scatter_add complejo y contrato del recurso embebido para Swift
metadata:
  type: project
---

- Pesos: `model_mel_band_roformer_ep_72_sdr_3.2232.ckpt` (sha256 b3c47bca…7eef) del commit c3ac4e45 de RandomFilteredStuff/RVC_V2_Stuff. OrderedDict FP32 puro: **`torch.load(weights_only=True)`** y casa estricto (636/636) con `config_mel_band_roformer_Lead_Rhythm_Guitar.yaml` del mismo commit (la config karaoke NO casa). 84 M parámetros.
- El YAML lleva `!!python/tuple` → SafeLoader con un único constructor de tupla. Construir `MelBandRoformer(**cfg["model"])` a mano (no get_model_from_config de MSST).
- **MPS no sirve en torch 2.7** (`scatter_add_` sobre complejos). Referencia PyTorch en CPU.
- Conversión (2026-11-15, salió a la primera, torch 2.7.0 + ct 9.0): núcleo sin STFT en `Probes/P4-modelos/lead_rhythm/lr_common.py` (`make_core`). El scatter_add complejo se cambia por K=2 `index_select` con índices fijos (cada frecuencia cae en 1 o 2 bandas) + suma + división por `num_bands_per_freq`: exacto. Rotary con tablas cos/sin fijas, como BS-RoFormer. Ops MIL limpias (gather, sdpa, linear…). `convert.py fp16|fp32 [--install]`, `compare.py fp16|fp32|fixture`, siempre bajo guard.py. Una reconversión cambia el sha del zip: actualizar ModelCatalog.

**Contrato del recurso embebido** `App/Resources/Models/LeadRhythmMelRoformer_fp16.mlpackage.zip` (ModelCatalog `leadRhythmMelRoformer`, id `lead-rhythm-guitar`, rol `.leadGuitarSeparation`):
- Entrada `spec` [1, 2050, 301, 2] float32; fila 2·f + canal (L=0, R=1), (re, im) en el último eje. Mismo layout que la entrada del BS-RoFormer gridshift.
- Salida `mask` [1, 1, 2050, 301, 2] float32 (FP16 por dentro): máscara compleja ya promediada de la solista, mismo layout.
- Swift: 44,1 kHz estéreo; STFT n_fft 2048, **hop 441** (no 512), Hann periódica, center=True reflect, sin normalizar; producto complejo spec·mask; bin 0 a cero (zero_dc); iSTFT con Σw². Trozo 132300 muestras (3 s, 301 tramas), **num_overlap 1** (paso = trozo, borde 0 → sin relleno de la canción), fundido 13230 (casi no actúa: muestras con peso 0 en los cortes → salida 0, como MSST), último trozo con reflect si > medio trozo, si no ceros. Es `ChunkPlan(chunk: 132300, overlaps: 1)` + ChunkProcessor con 1 stem y hop 441. Rítmica = entrada − solista.
- Fixture: `Packages/StemKit/Tests/StemKitTests/Fixtures/LeadRhythm/` (input_2s_pcm16.wav, lead_torch_2s_f32.wav de PyTorch, reference.json con sondas de spec/máscara y el SDR que logra el Core ML en Python).
- ANE no probado (regla de [[coreml-env-traps]]).

**Why:** origen anónimo; la vía de máscara compleja era la parte delicada; el ingeniero de Swift parte de este contrato.
**How to apply:** para otro Mel-Band RoFormer de MSST, reutilizar lr_common.make_core cambiando constantes. Ver [[bs-roformer-contract]], [[guitar-models-contract]].
