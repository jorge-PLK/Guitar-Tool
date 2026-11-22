// Puente C: API DL de Dart, envío por puerto nativo y reloj. El resto de la ABI está en Swift (@_cdecl).
#include "tf_core.h"
#include "dart_api_dl.h"
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#include <objbase.h>
// CoGetApartmentType vive en ole32.
#pragma comment(lib, "ole32.lib")
#elif defined(__APPLE__)
#include <pthread.h>
#endif

#ifdef _WIN32
// SÍMBOLOS PRIVADOS de swift-corelibs-libdispatch (private/private.h), exportados por dispatch.dll. No son API
// pública y pueden cambiar con la versión del toolchain. En Windows el "handle" de la cola principal es un HANDLE
// señalizable (para MsgWaitForMultipleObjects) y el callback drena los bloques pendientes de la cola principal.
// Si falla el enlace con dispatch.lib: resolverlos con GetProcAddress(GetModuleHandleW(L"dispatch.dll"), ...).
extern HANDLE _dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *msg);
#endif

intptr_t tf_core_init_dart_api(void *data) { return Dart_InitializeApiDL(data); }

int64_t tf_debug_now_ns(void) {
#ifdef _WIN32
  LARGE_INTEGER freq, now;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&now);
  // Evita desbordar: segundos enteros + resto.
  int64_t sec = now.QuadPart / freq.QuadPart;
  int64_t rem = now.QuadPart % freq.QuadPart;
  return sec * 1000000000LL + rem * 1000000000LL / freq.QuadPart;
#elif defined(__APPLE__)
  return (int64_t)clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

// ---- Hilo principal ----
// Windows no tiene un "pthread_main_np". Referencia usada: el id del hilo que cargó la DLL (DllMain,
// DLL_PROCESS_ATTACH; en el runner es el hilo principal porque es quien hace LoadLibrary) o el del hilo que llamó a
// tf_core_run_main (que se documenta como solo-principal), el que ocurra último. Límite: si la DLL la carga otro
// hilo (p. ej. Dart FFI desde un hilo que no es el principal) y nadie llama a tf_core_run_main, la referencia sería
// ese hilo, no el principal.
#ifdef _WIN32
static volatile LONG tf_main_thread_id = 0;

void tf_internal_mark_main_thread(void) { InterlockedExchange(&tf_main_thread_id, (LONG)GetCurrentThreadId()); }

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
  (void)inst; (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) tf_internal_mark_main_thread();
  return TRUE;
}

int32_t tf_debug_is_main_thread(void) { return GetCurrentThreadId() == (DWORD)tf_main_thread_id ? 1 : 0; }

void *tf_core_main_queue_handle(void) { return (void *)_dispatch_get_main_queue_handle_4CF(); }
void tf_core_pump(void) { _dispatch_main_queue_callback_4CF(NULL); }

int32_t tf_debug_apartment(void) {
  APTTYPE type;
  APTTYPEQUALIFIER qualifier;
  if (FAILED(CoGetApartmentType(&type, &qualifier))) return -1;
  return (int32_t)type;
}
#else
void tf_internal_mark_main_thread(void) {}
#ifdef __APPLE__
int32_t tf_debug_is_main_thread(void) { return pthread_main_np() ? 1 : 0; }
#else
int32_t tf_debug_is_main_thread(void) { return 0; }
#endif
void *tf_core_main_queue_handle(void) { return NULL; }
void tf_core_pump(void) {}
int32_t tf_debug_apartment(void) { return -2; }
#endif

/// Finalizador de Dart: mismo efecto que tf_core_free (free + decremento del contador).
static void tf_external_finalizer(void *isolate_callback_data, void *peer) {
  (void)isolate_callback_data;
  tf_core_free((const uint8_t *)peer);
}

bool tf_post_external(int64_t port, uint8_t *ptr, intptr_t len) {
  if (Dart_PostCObject_DL == NULL) return false;
  Dart_CObject obj;
  obj.type = Dart_CObject_kExternalTypedData;
  obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
  obj.value.as_external_typed_data.length = len;
  obj.value.as_external_typed_data.data = ptr;
  obj.value.as_external_typed_data.peer = ptr;
  obj.value.as_external_typed_data.callback = tf_external_finalizer;
  return Dart_PostCObject_DL(port, &obj);
}
