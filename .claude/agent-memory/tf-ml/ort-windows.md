---
name: ort-windows
description: ONNX Runtime en la VM Windows (Fase 7c) — de dónde sacar ORT, cómo enlazar la API C desde SwiftPM, trampas de DLL y de medición
metadata:
  type: project
---

- **github.com/microsoft/onnxruntime daba 404 (repo, API y assets de releases) el 2026-11-18.** Fuente oficial que sí va: NuGet `Microsoft.ML.OnnxRuntime` (api.nuget.org flatcontainer, 184 MB, SHA-512 en la cabecera `x-ms-meta-sha512` en base64). Trae `build/native/include` y `runtimes/win-arm64|win-x64/native` (onnxruntime.dll + import lib de 2 KB). Se extrae con `tar.exe -xf` (lee zip).
- SwiftPM sin unsafeFlags: target C con `#include "C:/ort/include/onnxruntime_c_api.h"` y `#pragma comment(lib, "C:/ort/<arch>/onnxruntime.lib")` según `_M_ARM64`/`_M_X64`; lld-link lo acepta. Los campos de OrtApi son punteros a función opcionales en Swift (`api.Run!(...)`, y `GetErrorMessage!(st)!`). ORTCHAR_T es wchar_t: convertir la ruta en C (MultiByteToWideChar). `String(format:"%@")` no es fiable fuera de Darwin: interpolar.
- **System32 trae su propia onnxruntime.dll** (stub de Windows ML) y va antes que el PATH: la DLL tiene que ir junto al exe. install.ps1 de build.sh borra C:\ToneForge\<arch> en cada instalación (también la de tf-engineer): ejecutar desde una carpeta propia (C:\ort\run\<arch>).
- La VM no tiene Python (solo el stub de WindowsApps): comparar tensores desde Swift (ort-smoke lee manifest.txt + .bin y calcula max/media/SNR).
- Tiempos de la VM: si tf-engineer compila a la vez (vm.lock cogido), salen 1,5-2 veces más lentos; medir con el cerrojo libre y sin carga pesada en el Mac.
- Export TorchScript de ONNX (torch 2.7, opset 17) de lr_common.make_core a T=301: 3,8 s, 339 MB, sin problemas.

**Why:** localizar ORT y enlazarlo costó varios turnos; la DLL de System32 puede cargarse en silencio.
**How to apply:** reutilizar Probes/P8-windows/ort-smoke (exe genérico) y ort-models/prepare.py (referencias en el Mac). Ver [[coreml-env-traps]], [[bs-roformer-contract]].
