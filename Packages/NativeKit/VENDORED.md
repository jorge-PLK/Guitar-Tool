# Código y binarios de terceros de NativeKit

Fuentes en git (con su licencia, versión fijada); los binarios de Windows no van en git. SHA-256 = del fichero bajado.

## Fuentes vendorizadas (parte 7.0 del paso 7)

| Nombre | Versión / commit | URL | SHA-256 | Licencia | Dónde |
| --- | --- | --- | --- | --- | --- |
| r8brain-free-src | 7.7, commit `5792291ad66b04e87fd61a3d92606214632c6cfc` | https://codeload.github.com/avaneev/r8brain-free-src/tar.gz/5792291ad66b04e87fd61a3d92606214632c6cfc | `8a4d6be59e0b896e1f1486cb05222014d9f5df82fafc8f505c0b5037f407b6d7` | MIT | `Sources/CResampler/r8brain/` (solo cabeceras y `fft4g.h`; sin pffft) |
| Signalsmith Stretch | 1.3.2, commit `88061fd4eda56a2353c5d65c74aa3f4ccf76f9da` | https://codeload.github.com/Signalsmith-Audio/signalsmith-stretch/tar.gz/88061fd4eda56a2353c5d65c74aa3f4ccf76f9da | `4dc468e46f208415ca66567cacfd8fb22b01d321fcdb4c2452278fee2426b09d` | MIT | `Sources/CSignalsmith/third_party/signalsmith-stretch/` |
| signalsmith-linear (dependencia de Stretch) | 0.6.6, commit `7bb1c8f36794d6980080ce817c91f8da8fe56a66` | https://codeload.github.com/Signalsmith-Audio/linear/tar.gz/refs/tags/0.6.6 | `e6d6a914189894fd728111b2a3209445ecd065aa9a5c1958f41b64ac3cef8b32` | MIT | `Sources/CSignalsmith/third_party/signalsmith-linear/` (sin backends xsimd/cmsis/ipp activos) |
| TinySoundFont (`tsf.h`, `tml.h`) | v0.9, commit `a3621a19c6504885cd9583e6e26c35bc954fc8ec` | https://codeload.github.com/schellingb/TinySoundFont/tar.gz/a3621a19c6504885cd9583e6e26c35bc954fc8ec | `50a8155445e1e06e1b26f8cc5280e914fe0f17b9d9ff87f39e7f18d0d5ff8ff4` | MIT | `Sources/CTinySoundFont/include/` |
| Cabeceras de la API C de ONNX Runtime | 1.32.0 (NuGet `Microsoft.ML.OnnxRuntime`, `build/native/include`) | https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.32.0/microsoft.ml.onnxruntime.1.32.0.nupkg | `a9150bc2992cbbb6722070da9910e1ffa989a8bfc67bdd5bb8e745ca755641db` | MIT | `Sources/COnnxRuntime/include/` (solo las de la API C) |

Cambio local sobre lo vendorizado: `r8bbase.h` incluye `<arm_neon.h>` en lugar de `<arm64_neon.h>` cuando el compilador es clang (clang en Windows define `_MSC_VER` pero no trae las funciones `neon_*` de MSVC). Marcado con un comentario «ToneForge». r8brain 7.x recorta su latencia entera por dentro (`getLatency()` = 0).

Los shims `CWASAPI`, `CMediaFoundation` y `CDirect2D` son código propio (solo Windows).

## Binarios de Windows (fuera de git)

`Tools/win/fetch-ort.sh` los baja a `Vendor/win/ort/<arm64|x64>/` (`Vendor/win/` está en `.gitignore`) y comprueba el SHA-256.

| Nombre | Versión | URL | SHA-256 | Licencia |
| --- | --- | --- | --- | --- |
| Microsoft.ML.OnnxRuntime (`onnxruntime.dll`, `.lib`, `onnxruntime_providers_shared.dll`) | 1.32.0 | https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.32.0/microsoft.ml.onnxruntime.1.32.0.nupkg | `a9150bc2992cbbb6722070da9910e1ffa989a8bfc67bdd5bb8e745ca755641db` | MIT |
| Microsoft.AI.DirectML (`DirectML.dll`) | 1.15.4 (última estable) | https://api.nuget.org/v3-flatcontainer/microsoft.ai.directml/1.15.4/microsoft.ai.directml.1.15.4.nupkg | `4e7cb7ddce8cf837a7a75dc029209b520ca0101470fcdf275c1f49736a3615b9` | Microsoft (`LICENSE.txt` del paquete: redistribuible con la app) |

En la VM viven en `C:\tf-ort\<arch>` (carpeta persistente, `--clean` no la borra); `Tools/win/build.sh` la rellena por `scp` cuando cambia `Vendor/win/ort/VERSION`.
