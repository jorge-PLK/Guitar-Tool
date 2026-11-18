#include "COnnxRuntime.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#include <stdlib.h>

// Import lib por arquitectura, sin unsafeFlags en Package.swift: la directiva viaja en el objeto.
#if defined(_M_ARM64)
#pragma comment(lib, "C:/ort/arm64/onnxruntime.lib")
#elif defined(_M_X64)
#pragma comment(lib, "C:/ort/x64/onnxruntime.lib")
#else
#error "arquitectura no soportada"
#endif

const OrtApi *tf_ort_api(void) { return OrtGetApiBase()->GetApi(ORT_API_VERSION); }

const char *tf_ort_version(void) { return OrtGetApiBase()->GetVersionString(); }

OrtStatus *tf_create_session(const OrtApi *api, OrtEnv *env, const char *utf8_path,
                             OrtSessionOptions *options, OrtSession **out) {
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, NULL, 0);
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
    MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, w, n);
    OrtStatus *st = api->CreateSession(env, w, options, out);
    free(w);
    return st;
}

size_t tf_peak_working_set(void) {
    PROCESS_MEMORY_COUNTERS pmc;
    pmc.cb = sizeof(pmc);
    if (!K32GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) return 0;
    return pmc.PeakWorkingSetSize;
}

const char *tf_loaded_ort_path(void) {
    static char buf[1024];
    wchar_t w[512];
    HMODULE h = GetModuleHandleW(L"onnxruntime.dll");
    if (!h) return "(no cargada)";
    DWORD n = GetModuleFileNameW(h, w, 512);
    if (n == 0) return "(desconocida)";
    WideCharToMultiByte(CP_UTF8, 0, w, (int)n + 1, buf, sizeof(buf), NULL, NULL);
    return buf;
}
