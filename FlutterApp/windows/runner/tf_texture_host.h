#ifndef RUNNER_TF_TEXTURE_HOST_H_
#define RUNNER_TF_TEXTURE_HOST_H_

#include <flutter_texture_registrar.h>

// Host de texturas externas. El runner no enlaza AppCoreFFI: resuelve por GetProcAddress sobre la DLL y le da una
// tabla de tres punteros (mismo diseño que `tf_texture_host` de tf_core.h). Texturas D3D11 compartidas (GPU surface).
namespace tf {

// Desde FlutterWindow::OnCreate, antes de que Dart arranque el núcleo. Sin AppCoreFFI.dll o sin sus símbolos no
// hace nada: la app arranca sin texturas.
void InstallTextureHost(FlutterDesktopTextureRegistrarRef registrar);

// Desde FlutterWindow::OnDestroy, antes de destruir el motor.
void ShutdownTextureHost();

}  // namespace tf

#endif  // RUNNER_TF_TEXTURE_HOST_H_
