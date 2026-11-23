#include "tf_texture_host.h"

#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "utils.h"

// Usa la API C de texturas del motor (flutter_texture_registrar.h): flutter::FlutterEngine no expone el registro.
// Las tres funciones del registro son seguras desde cualquier hilo (flutter_texture_registrar.h:160,166,176).
namespace tf {
namespace {

// Firmas de la ABI de AppCoreFFI.dll.
struct HostTable {
  int64_t (*register_texture)(int32_t channel);
  void (*frame_available)(int64_t id);
  void (*unregister_texture)(int64_t id);
};
using SetHostFn = void (*)(const HostTable *);
using FrameCopyFn = void *(*)(int32_t channel);
using FrameBgraFn = int32_t (*)(int32_t, uint8_t *, int32_t, int32_t *, int32_t *, int64_t *);
using D3dSizeFn = int32_t (*)(int32_t, int32_t *, int32_t *);

// Tamaño máximo del camino pixel (1080p); coincide con --size 1080 de la prueba.
constexpr size_t kMaxPixelBytes = 1920u * 1080u * 4u;

// Estado de una textura registrada. Los callbacks del motor corren en su hilo de raster.
struct Entry {
  int32_t channel = 0;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
  FlutterDesktopPixelBuffer pixel{};
  std::vector<uint8_t> bgra;
  std::vector<uint8_t> rgba;
  int64_t seq = 0;
  bool have_pixels = false;
};

std::mutex g_mutex;  // protege g_registrar y g_entries
FlutterDesktopTextureRegistrarRef g_registrar = nullptr;
std::map<int64_t, std::shared_ptr<Entry>> g_entries;
bool g_gpu = true;
HostTable g_table{};
FrameCopyFn g_frame_copy = nullptr;
FrameBgraFn g_frame_bgra = nullptr;
D3dSizeFn g_d3d_size = nullptr;

bool ParseKindGpu() {
  const std::vector<std::string> args = GetCommandLineArguments();
  std::string value;
  for (size_t i = 0; i < args.size(); ++i) {
    if (args[i] == "--texture-kind" && i + 1 < args.size()) {
      value = args[i + 1];
    } else if (args[i].rfind("--texture-kind=", 0) == 0) {
      value = args[i].substr(15);
    }
  }
  return value != "pixel";
}

// Camino gpu: tf_frame_copy devuelve el HANDLE compartido de D3D11 (IDXGIResource::GetSharedHandle).
const FlutterDesktopGpuSurfaceDescriptor *ObtainGpu(size_t width, size_t height, void *user) {
  Entry *e = static_cast<Entry *>(user);
  void *handle = g_frame_copy ? g_frame_copy(e->channel) : nullptr;
  if (handle == nullptr) return nullptr;
  int32_t w = static_cast<int32_t>(width), h = static_cast<int32_t>(height);
  if (g_d3d_size) g_d3d_size(e->channel, &w, &h);  // tamaño real de la textura, no el pedido
  e->descriptor = {};
  e->descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  e->descriptor.handle = handle;
  e->descriptor.width = e->descriptor.visible_width = static_cast<size_t>(w);
  e->descriptor.height = e->descriptor.visible_height = static_cast<size_t>(h);
  e->descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
  return &e->descriptor;
}

// Camino pixel: el motor espera RGBA (FlutterDesktopPixelBuffer no tiene campo de formato), el núcleo da BGRA:
// se intercambian R y B al copiar.
const FlutterDesktopPixelBuffer *ObtainPixels(size_t, size_t, void *user) {
  Entry *e = static_cast<Entry *>(user);
  if (g_frame_bgra == nullptr) return nullptr;
  if (e->bgra.empty()) {
    e->bgra.resize(kMaxPixelBytes);
    e->rgba.resize(kMaxPixelBytes);
  }
  int32_t w = 0, h = 0;
  const int32_t n = g_frame_bgra(e->channel, e->bgra.data(), static_cast<int32_t>(e->bgra.size()), &w, &h, &e->seq);
  if (n > 0) {
    const uint8_t *s = e->bgra.data();
    uint8_t *d = e->rgba.data();
    for (int32_t i = 0; i < n; i += 4) {
      d[i] = s[i + 2];
      d[i + 1] = s[i + 1];
      d[i + 2] = s[i];
      d[i + 3] = s[i + 3];
    }
    e->pixel = {};
    e->pixel.buffer = e->rgba.data();
    e->pixel.width = static_cast<size_t>(w);
    e->pixel.height = static_cast<size_t>(h);
    e->have_pixels = true;
  }
  return e->have_pixels ? &e->pixel : nullptr;  // sin fotograma nuevo: el anterior
}

int64_t RegisterTexture(int32_t channel) {
  auto entry = std::make_shared<Entry>();
  entry->channel = channel;
  FlutterDesktopTextureInfo info{};
  if (g_gpu) {
    info.type = kFlutterDesktopGpuSurfaceTexture;
    info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
    info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
    info.gpu_surface_config.callback = ObtainGpu;
    info.gpu_surface_config.user_data = entry.get();
  } else {
    info.type = kFlutterDesktopPixelBufferTexture;
    info.pixel_buffer_config.callback = ObtainPixels;
    info.pixel_buffer_config.user_data = entry.get();
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_registrar == nullptr) return -1;
  const int64_t id = FlutterDesktopTextureRegistrarRegisterExternalTexture(g_registrar, &info);
  if (id >= 0) g_entries[id] = entry;
  return id;
}

// Desde el hilo del generador: se puede llamar desde cualquier hilo (flutter_texture_registrar.h:177).
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
  if (dll == nullptr) dll = ::LoadLibraryW(L"AppCoreFFI.dll");  // misma imagen que abrirá Dart por ruta
  if (dll == nullptr) return;
  auto set_host = reinterpret_cast<SetHostFn>(::GetProcAddress(dll, "tf_core_set_texture_host"));
  g_frame_copy = reinterpret_cast<FrameCopyFn>(::GetProcAddress(dll, "tf_frame_copy"));
  g_frame_bgra = reinterpret_cast<FrameBgraFn>(::GetProcAddress(dll, "tf_debug_frame_bgra"));
  g_d3d_size = reinterpret_cast<D3dSizeFn>(::GetProcAddress(dll, "tf_d3d_size"));
  if (set_host == nullptr || g_frame_copy == nullptr || g_frame_bgra == nullptr) {
    std::fprintf(stderr, "tf: faltan simbolos de texturas en AppCoreFFI.dll\n");
    return;
  }
  g_gpu = ParseKindGpu();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_registrar = registrar;
  }
  g_table = {RegisterTexture, FrameAvailable, UnregisterTexture};
  set_host(&g_table);
  std::fprintf(stderr, "tf: texture host instalado, kind=%s\n", g_gpu ? "gpu" : "pixel");
}

void ShutdownTextureHost() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_registrar = nullptr;
  g_entries.clear();
}

}  // namespace tf
