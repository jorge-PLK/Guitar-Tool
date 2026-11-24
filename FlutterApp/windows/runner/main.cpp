#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Vía 1 de hilos (docs/flutter/arquitectura.md): si AppCoreFFI.dll está junto al .exe, el hilo principal queda en
// tf_core_run_main() (= dispatchMain(), como WinApp) y la ventana, el motor de Flutter y su bucle de mensajes viven en
// un hilo propio STA. Sin la DLL (o sin ese símbolo) el runner funciona como la plantilla de Flutter, sin núcleo.

namespace {

using RunMainFn = void (*)();

// Crea la ventana y ejecuta el bucle de mensajes. Devuelve el código de salida.
// El hilo que la llame debe haber hecho CoInitializeEx.
int RunWindowGetMessageLoop(const std::vector<std::string> &args) {
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(args);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1440, 900);
  if (!window.Create(L"ToneForge", origin, size)) {
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

  const std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  // Se carga ANTES de crear el motor; Dart la abrirá después por el mismo nombre y obtendrá el mismo módulo.
  HMODULE dll = ::LoadLibraryW(L"AppCoreFFI.dll");
  RunMainFn run_main =
      dll == nullptr ? nullptr : reinterpret_cast<RunMainFn>(::GetProcAddress(dll, "tf_core_run_main"));

  if (run_main != nullptr) {
    // El hilo principal NO inicializa COM: lo hace el hilo de UI (STA).
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

  if (dll != nullptr) {
    std::fprintf(stderr, "tf: no se encuentra tf_core_run_main en AppCoreFFI.dll; arranque sin núcleo\n");
  }

  // Sin núcleo: plantilla de Flutter.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const int code = RunWindowGetMessageLoop(command_line_arguments);
  ::CoUninitialize();
  return code;
}
