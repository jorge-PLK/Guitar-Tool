#include "COnnxRuntime.h"
typedef int COnnxRuntimeDXGI_empty_translation_unit;

#if defined(_WIN32)
// Enumeracion de GPU por DXGI para elegir proveedor de ONNX Runtime (plan, Mini-spec del port, "Modelos y
// aceleracion"; parte 7.8). dxgi.dll se carga en ejecucion: sin import lib ni dxguid.lib.
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define CINTERFACE
#include <windows.h>
#include <dxgi.h>
#include <string.h>

typedef HRESULT (WINAPI *tf_create_factory1_fn)(REFIID riid, void **factory);

// IID_IDXGIFactory1 {770aae78-f26f-4dba-a829-253c83d1b387}
static const GUID tf_iid_factory1 = { 0x770aae78, 0xf26f, 0x4dba, { 0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87 } };

int tf_dxgi_adapters(tf_gpu_info *out, int cap) {
    HMODULE dll = LoadLibraryW(L"dxgi.dll");
    if (!dll) return -1;
    tf_create_factory1_fn create = (tf_create_factory1_fn)(void *)GetProcAddress(dll, "CreateDXGIFactory1");
    if (!create) return -1;
    IDXGIFactory1 *factory = NULL;
    if (FAILED(create(&tf_iid_factory1, (void **)&factory)) || !factory) return -1;
    int n = 0;
    for (UINT i = 0;; i++) {
        IDXGIAdapter1 *adapter = NULL;
        if (IDXGIFactory1_EnumAdapters1(factory, i, &adapter) == DXGI_ERROR_NOT_FOUND) break;
        if (!adapter) break;
        DXGI_ADAPTER_DESC1 d;
        if (SUCCEEDED(IDXGIAdapter1_GetDesc1(adapter, &d)) && n < cap) {
            tf_gpu_info *g = &out[n];
            memset(g, 0, sizeof *g);
            WideCharToMultiByte(CP_UTF8, 0, d.Description, -1, g->name, (int)sizeof g->name - 1, NULL, NULL);
            g->vendor_id = d.VendorId;
            g->device_id = d.DeviceId;
            g->dedicated_video_memory = (uint64_t)d.DedicatedVideoMemory;
            g->shared_system_memory = (uint64_t)d.SharedSystemMemory;
            // Microsoft (0x1414) es WARP o la pantalla basica aunque no lleve la marca: en la VM el adaptador 0
            // "Microsoft Basic Render Driver" sale sin DXGI_ADAPTER_FLAG_SOFTWARE (medido en la parte 7.8).
            g->is_software = ((d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) || d.VendorId == 0x1414) ? 1 : 0;
            g->adapter_index = (int)i;
        }
        n++;
        IDXGIAdapter1_Release(adapter);
    }
    IDXGIFactory1_Release(factory);
    return n;
}
#endif
