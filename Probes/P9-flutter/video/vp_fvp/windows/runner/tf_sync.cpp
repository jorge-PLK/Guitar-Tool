// Shim de reloj externo para mdk onSync en Windows (equivalente a vp_onsync_clock de macOS).
// mdk invoca tf_sync_cb desde un hilo propio, de forma síncrona; Dart no puede atenderlo
// (NativeCallable.isolateGroupBound exige --experimental-shared-data), así que Dart solo publica el
// reloj con tf_sync_set (30 Hz, por FFI) y el cálculo seconds + (now-at)*rate vive aquí.
// Reloj común: QueryPerformanceCounter en ns (tf_sync_now_ns), que Dart usa también para medir.
// Los símbolos se exportan desde el .exe y Dart los busca con DynamicLibrary.process().
#include <windows.h>

#include <atomic>
#include <cstdint>

#define TF_EXPORT extern "C" __declspec(dllexport)

namespace {
std::atomic<uint32_t> g_seq{0};  // seqlock: impar = escritura en curso (un solo escritor: hilo de Dart)
std::atomic<double> g_seconds{0}, g_rate{1};
std::atomic<int64_t> g_at_ns{0};
std::atomic<int32_t> g_playing{0};
std::atomic<int64_t> g_epoch{0};
// Estadísticas del callback, mismo diseño que la memoria compartida de macOS:
// 6 nCalls, 7 tPrimera(s), 8 tÚltima(s), 9 maxGap(s), 10 hiloPrimero, 11 llamadasEnOtroHilo, 13 primeraRespuesta, 14 última
std::atomic<double> g_stats[16];

int64_t now_ns() {
  static const int64_t freq = [] {
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    return static_cast<int64_t>(f.QuadPart);
  }();
  LARGE_INTEGER c;
  QueryPerformanceCounter(&c);
  const int64_t sec = c.QuadPart / freq, rem = c.QuadPart % freq;
  return sec * 1000000000LL + rem * 1000000000LL / freq;
}
}  // namespace

TF_EXPORT int64_t tf_sync_now_ns() { return now_ns(); }

TF_EXPORT uint32_t tf_thread_id() { return GetCurrentThreadId(); }

// CPU de proceso acumulada (kernel + usuario), en segundos.
TF_EXPORT double tf_cpu_s() {
  FILETIME c, e, k, u;
  if (!GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u)) return 0;
  auto v = [](FILETIME f) { return static_cast<double>((static_cast<uint64_t>(f.dwHighDateTime) << 32) | f.dwLowDateTime) * 1e-7; };
  return v(k) + v(u);
}

// Publica un takeview.position: seconds en `at_ns` (reloj de tf_sync_now_ns).
TF_EXPORT void tf_sync_set(double seconds, int32_t playing, int64_t at_ns, double rate, int64_t epoch) {
  const uint32_t s = g_seq.load(std::memory_order_relaxed);
  g_seq.store(s + 1, std::memory_order_release);
  g_seconds.store(seconds, std::memory_order_relaxed);
  g_playing.store(playing, std::memory_order_relaxed);
  g_at_ns.store(at_ns, std::memory_order_relaxed);
  g_rate.store(rate, std::memory_order_relaxed);
  g_epoch.store(epoch, std::memory_order_relaxed);
  g_seq.store(s + 2, std::memory_order_release);
}

// Copia las estadísticas (16 doubles) a `out` (memoria de Dart).
TF_EXPORT void tf_sync_stats(double* out) {
  for (int i = 0; i < 16; i++) out[i] = g_stats[i].load(std::memory_order_relaxed);
}

// Firma de mdkSyncCallback.cb: double (*)(void* opaque) -> segundos de reproducción deseados.
TF_EXPORT double tf_sync_cb(void*) {
  const int64_t now = now_ns();
  const double nowS = static_cast<double>(now) * 1e-9;
  const double tid = static_cast<double>(GetCurrentThreadId());
  const double n = g_stats[6].load(std::memory_order_relaxed);
  if (n == 0) {
    g_stats[7].store(nowS, std::memory_order_relaxed);
    g_stats[10].store(tid, std::memory_order_relaxed);
  } else {
    const double gap = nowS - g_stats[8].load(std::memory_order_relaxed);
    if (gap > g_stats[9].load(std::memory_order_relaxed)) g_stats[9].store(gap, std::memory_order_relaxed);
    if (tid != g_stats[10].load(std::memory_order_relaxed))
      g_stats[11].store(g_stats[11].load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
  }
  g_stats[8].store(nowS, std::memory_order_relaxed);
  g_stats[6].store(n + 1, std::memory_order_relaxed);

  double sec = 0, rate = 1, at = 0;
  int32_t playing = 0;
  int64_t at_ns = 0;
  for (int i = 0; i < 8; i++) {
    const uint32_t s1 = g_seq.load(std::memory_order_acquire);
    sec = g_seconds.load(std::memory_order_relaxed);
    playing = g_playing.load(std::memory_order_relaxed);
    at_ns = g_at_ns.load(std::memory_order_relaxed);
    rate = g_rate.load(std::memory_order_relaxed);
    if (s1 == g_seq.load(std::memory_order_acquire) && (s1 & 1) == 0) break;
  }
  (void)at;
  const double r = playing ? sec + static_cast<double>(now - at_ns) * 1e-9 * rate : sec;
  if (n == 0) g_stats[13].store(r, std::memory_order_relaxed);
  g_stats[14].store(r, std::memory_order_relaxed);
  return r;
}
