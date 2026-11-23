#ifndef RUNNER_TF_TEXTURE_HOST_H_
#define RUNNER_TF_TEXTURE_HOST_H_

#include <flutter_texture_registrar.h>

// P9.7f-A: host de texturas externas. El runner no enlaza AppCoreFFI: resuelve por GetProcAddress sobre la DLL ya
// cargada y le da una tabla de tres punteros (mismo diseño que `tf_texture_host` de tf_core.h).
// `--texture-kind gpu|pixel` (por defecto gpu) se lee de la línea de comandos del proceso.
namespace tf {

// Desde FlutterWindow::OnCreate, antes de que Dart arranque el núcleo. Sin AppCoreFFI.dll no hace nada.
void InstallTextureHost(FlutterDesktopTextureRegistrarRef registrar);

// Desde FlutterWindow::OnDestroy, antes de destruir el motor.
void ShutdownTextureHost();

}  // namespace tf

#endif  // RUNNER_TF_TEXTURE_HOST_H_
