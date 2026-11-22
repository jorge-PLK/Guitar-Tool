#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// P9 prueba 7 (Fase 7f): `--threads none|via1|via2` (por defecto none = plantilla de Flutter sin cambios).
// Contexto: AppCore (Swift) depende de DispatchQueue.main / @MainActor y en Windows nadie las drena si el hilo
// principal está ocupado por el bucle Win32 del runner. El argumento se sigue pasando también a Dart.
//
//  none: plantilla. Cola principal de Swift sin drenar (referencia para ver el fallo).
//  via1: el hilo principal queda en tf_core_run_main() (= dispatchMain(), como WinApp) y la ventana, el motor de
//        Flutter y su bucle de mensajes viven en un hilo propio STA.
//  via2: el runner sigue en el hilo principal y su bucle espera además el HANDLE de la cola principal de Swift
//        (MsgWaitForMultipleObjects) y llama a tf_core_pump() cuando se señala (símbolos privados _4CF).

namespace {

enum class ThreadsMode { kNone, kVia1, kVia2 };

// Lee `--threads <valor>` o `--threads=<valor>` de los argumentos ya convertidos a UTF-8.
ThreadsMode ParseThreadsMode(const std::vector<std::string> &args) {
  std::string value;
  for (size_t i = 0; i < args.size(); ++i) {
    if (args[i] == "--threads" && i + 1 < args.size()) {
      value = args[i + 1];
    } else if (args[i].rfind("--threads=", 0) == 0) {
      value = args[i].substr(10);
    }
  }
  if (value == "via1") return ThreadsMode::kVia1;
  if (value == "via2") return ThreadsMode::kVia2;
  return ThreadsMode::kNone;
}

// Firmas de la ABI de AppCoreFFI.dll (no se incluye tf_core.h: se resuelven por GetProcAddress).
using RunMainFn = void (*)();
using QueueHandleFn = void *(*)();
using PumpFn = void (*)();

// Carga la DLL del núcleo junto al .exe. Nombre esperado: AppCoreFFI.dll (si SwiftPM generase otro, aquí falla).
// Se carga ANTES de crear el motor de Flutter; Dart la abrirá después por el mismo nombre y obtendrá el mismo módulo.
HMODULE LoadCore() {
  HMODULE dll = ::LoadLibraryW(L"AppCoreFFI.dll");
  if (dll == nullptr) {
    std::fprintf(stderr, "tf: LoadLibraryW(AppCoreFFI.dll) fallo, error %lu\n", ::GetLastError());
  }
  return dll;
}

// Crea la ventana y ejecuta el bucle de mensajes de la plantilla (GetMessage). Devuelve el código de salida.
// El hilo que la llame debe haber hecho CoInitializeEx.
int RunWindowGetMessageLoop(const std::vector<std::string> &args) {
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(args);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"tf_probe", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  return EXIT_SUCCESS;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const ThreadsMode mode = ParseThreadsMode(command_line_arguments);

  if (mode == ThreadsMode::kVia1) {
    // Vía 1. El hilo principal NO inicializa COM: lo hace el hilo de UI (STA).
    HMODULE dll = LoadCore();
    if (dll == nullptr) return EXIT_FAILURE;
    auto run_main = reinterpret_cast<RunMainFn>(::GetProcAddress(dll, "tf_core_run_main"));
    if (run_main == nullptr) {
      std::fprintf(stderr, "tf: no se encuentra tf_core_run_main en AppCoreFFI.dll\n");
      return EXIT_FAILURE;
    }

    std::thread ui_thread([command_line_arguments]() {
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
      const int code = RunWindowGetMessageLoop(command_line_arguments);
      ::CoUninitialize();
      // El hilo principal está dentro de dispatchMain() y no vuelve nunca: se termina el proceso desde aquí.
      ::ExitProcess(static_cast<UINT>(code));
    });
    ui_thread.detach();

    run_main();  // no vuelve
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  if (mode == ThreadsMode::kVia2) {
    // Vía 2. Bucle propio que además bombea la cola principal de Swift.
    HMODULE dll = LoadCore();
    if (dll == nullptr) return EXIT_FAILURE;
    auto queue_handle = reinterpret_cast<QueueHandleFn>(::GetProcAddress(dll, "tf_core_main_queue_handle"));
    auto pump = reinterpret_cast<PumpFn>(::GetProcAddress(dll, "tf_core_pump"));
    if (queue_handle == nullptr || pump == nullptr) {
      std::fprintf(stderr, "tf: faltan tf_core_main_queue_handle / tf_core_pump en AppCoreFFI.dll\n");
      return EXIT_FAILURE;
    }
    HANDLE handle = static_cast<HANDLE>(queue_handle());
    if (handle == nullptr) {
      std::fprintf(stderr, "tf: tf_core_main_queue_handle devolvio NULL\n");
      return EXIT_FAILURE;
    }

    flutter::DartProject project(L"data");
    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    if (!window.Create(L"tf_probe", origin, size)) {
      return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);

    bool quit = false;
    while (!quit) {
      const DWORD r = ::MsgWaitForMultipleObjects(1, &handle, FALSE, INFINITE, QS_ALLINPUT);
      if (r == WAIT_OBJECT_0) {
        pump();  // drena DispatchQueue.main / @MainActor de Swift
      } else if (r == WAIT_OBJECT_0 + 1) {
        ::MSG msg;
        while (::PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
          if (msg.message == WM_QUIT) {
            quit = true;
            break;
          }
          ::TranslateMessage(&msg);
          ::DispatchMessage(&msg);
        }
      } else {
        break;  // WAIT_FAILED
      }
    }

    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  // none: plantilla tal cual.
  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"tf_probe", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
