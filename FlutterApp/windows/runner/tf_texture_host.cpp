#include "tf_texture_host.h"

#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>

// Usa la API C de texturas del motor (flutter_texture_registrar.h): flutter::FlutterEngine no expone el registro.
// Las tres funciones del registro son seguras desde cualquier hilo.
namespace tf {
namespace {

// Firmas de la ABI de AppCoreFFI.dll (tf_core.h).
struct HostTable {
  int64_t (*register_texture)(int32_t channel);
  void (*frame_available)(int64_t id);
  void (*unregister_texture)(int64_t id);
};
using SetHostFn = void (*)(const HostTable *);
using FrameCopyFn = void *(*)(int32_t channel);

// Estado de una textura registrada. Los callbacks del motor corren en su hilo de raster.
struct Entry {
  int32_t channel = 0;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
};

std::mutex g_mutex;  // protege g_registrar y g_entries
FlutterDesktopTextureRegistrarRef g_registrar = nullptr;
std::map<int64_t, std::shared_ptr<Entry>> g_entries;
HostTable g_table{};
FrameCopyFn g_frame_copy = nullptr;

// tf_frame_copy devuelve el HANDLE DXGI compartido de la textura publicada del anillo.
const FlutterDesktopGpuSurfaceDescriptor *ObtainGpu(size_t width, size_t height, void *user) {
  Entry *e = static_cast<Entry *>(user);
  void *handle = g_frame_copy ? g_frame_copy(e->channel) : nullptr;
  if (handle == nullptr) return nullptr;
  e->descriptor = {};
  e->descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  e->descriptor.handle = handle;
  e->descriptor.width = e->descriptor.visible_width = width;
  e->descriptor.height = e->descriptor.visible_height = height;
  e->descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
  return &e->descriptor;
}

int64_t RegisterTexture(int32_t channel) {
  auto entry = std::make_shared<Entry>();
  entry->channel = channel;
  FlutterDesktopTextureInfo info{};
  info.type = kFlutterDesktopGpuSurfaceTexture;
  info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
  info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
  info.gpu_surface_config.callback = ObtainGpu;
  info.gpu_surface_config.user_data = entry.get();
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_registrar == nullptr) return -1;
  const int64_t id = FlutterDesktopTextureRegistrarRegisterExternalTexture(g_registrar, &info);
  if (id >= 0) g_entries[id] = entry;
  return id;
}

// Desde el hilo del generador: se puede llamar desde cualquier hilo.
void FrameAvailable(int64_t id) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_registrar != nullptr) FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(g_registrar, id);
}

struct UnregisterCtx {
  int64_t id;
  std::shared_ptr<Entry> keep;
};

void UnregisterTexture(int64_t id) {
  FlutterDesktopTextureRegistrarRef registrar = nullptr;
  std::shared_ptr<Entry> keep;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    registrar = g_registrar;
    auto it = g_entries.find(id);
    if (it != g_entries.end()) keep = it->second;
  }
  if (registrar == nullptr) return;
  // El Entry se conserva hasta que el motor confirma (puede tener un raster en curso con el callback). Sin el lock
  // tomado: el callback podría ejecutarse en línea.
  auto *ctx = new UnregisterCtx{id, keep};
  FlutterDesktopTextureRegistrarUnregisterExternalTexture(
      registrar, id,
      [](void *user) {
        std::unique_ptr<UnregisterCtx> c(static_cast<UnregisterCtx *>(user));
        std::lock_guard<std::mutex> lock(g_mutex);
        g_entries.erase(c->id);
      },
      ctx);
}

}  // namespace

void InstallTextureHost(FlutterDesktopTextureRegistrarRef registrar) {
  HMODULE dll = ::GetModuleHandleW(L"AppCoreFFI.dll");
  if (dll == nullptr) dll = ::LoadLibraryW(L"AppCoreFFI.dll");  // misma imagen que abrirá Dart por nombre
  if (dll == nullptr) return;                                    // sin núcleo: sin texturas
  auto set_host = reinterpret_cast<SetHostFn>(::GetProcAddress(dll, "tf_core_set_texture_host"));
  g_frame_copy = reinterpret_cast<FrameCopyFn>(::GetProcAddress(dll, "tf_frame_copy"));
  if (set_host == nullptr || g_frame_copy == nullptr) {
    std::fprintf(stderr, "tf: faltan simbolos de texturas en AppCoreFFI.dll\n");
    return;
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_registrar = registrar;
  }
  g_table = {RegisterTexture, FrameAvailable, UnregisterTexture};
  set_host(&g_table);
}

void ShutdownTextureHost() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_registrar = nullptr;
  g_entries.clear();
}

}  // namespace tf
