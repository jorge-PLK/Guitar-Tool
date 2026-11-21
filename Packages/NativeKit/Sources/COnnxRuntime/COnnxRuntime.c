#include "COnnxRuntime.h"
typedef int COnnxRuntime_empty_translation_unit;

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

// onnxruntime.dll se carga en ejecucion (LoadLibrary + GetProcAddress), sin import lib: asi nada se enlaza
// contra ORT, el paquete compila sin tenerlo y se elige que DLL se usa. System32 trae otra onnxruntime.dll
// (la de Windows ML, mas antigua) que el cargador prefiere al PATH y a la carpeta del .dll de tests, asi que
// se carga por ruta completa la que esta junto a este modulo (la deja ahi Tools/win/remote, Copy-OrtDlls, desde
// C:\tf-ort\<arch>, rellenada por Tools/win/build.sh desde Vendor/win/ort); si no esta, la del sistema.
typedef const OrtApiBase *(ORT_API_CALL *tf_get_api_base_fn)(void);

static BOOL CALLBACK init(PINIT_ONCE o, PVOID p, PVOID *c);

static const OrtApiBase *tf_ort_base(void) {
    static const OrtApiBase *base = NULL;
    static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
    InitOnceExecuteOnce(&once, init, &base, NULL);
    return base;
}

static BOOL CALLBACK init(PINIT_ONCE o, PVOID p, PVOID *c) {
    (void)o; (void)c;
    const OrtApiBase **out = (const OrtApiBase **)p;
    HMODULE dll = NULL;
    HMODULE self = NULL;
    wchar_t path[MAX_PATH + 32];
    // TF_ORT_DLL: ruta completa de otra compilacion de ORT (un "sabor": p. ej. la de DirectML, parte 7.8). Se elige
    // antes de la primera carga y vale para todo el proceso; LOAD_WITH_ALTERED_SEARCH_PATH busca sus dependencias
    // (DirectML.dll) en su misma carpeta.
    {
        wchar_t forced[MAX_PATH + 32];
        DWORD m = GetEnvironmentVariableW(L"TF_ORT_DLL", forced, MAX_PATH);
        if (m > 0 && m < MAX_PATH) dll = LoadLibraryExW(forced, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    }
    if (!dll && GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCWSTR)&tf_ort_base, &self)) {
        DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
        if (n > 0 && n < MAX_PATH) {
            while (n > 0 && path[n - 1] != L'\\' && path[n - 1] != L'/') n--;
            wcscpy(path + n, L"onnxruntime.dll");
            if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES) dll = LoadLibraryW(path);
        }
    }
    if (!dll) dll = LoadLibraryW(L"onnxruntime.dll");
    if (dll) {
        tf_get_api_base_fn fn = (tf_get_api_base_fn)(void *)GetProcAddress(dll, "OrtGetApiBase");
        if (fn) *out = fn();
    }
    return TRUE;
}

// Version de API pedida: la de las cabeceras o, con una DLL mas antigua (DirectML acaba en 1.24), la mas alta que
// admita desde la 17. Solo se usan funciones que existen desde entonces.
static const OrtApi *g_api = NULL;
static uint32_t g_api_version = 0;
static INIT_ONCE g_api_once = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK api_init(PINIT_ONCE o, PVOID p, PVOID *c) {
    (void)o; (void)p; (void)c;
    const OrtApiBase *b = tf_ort_base();
    if (!b) return TRUE;
    for (uint32_t v = ORT_API_VERSION; v >= 17 && !g_api; v--) {
        g_api = b->GetApi(v);
        if (g_api) g_api_version = v;
    }
    return TRUE;
}

const OrtApi *tf_ort_api(void) {
    InitOnceExecuteOnce(&g_api_once, api_init, NULL, NULL);
    return g_api;
}

uint32_t tf_ort_api_version(void) {
    tf_ort_api();
    return g_api_version;
}

const char *tf_ort_version(void) {
    const OrtApiBase *b = tf_ort_base();
    return b ? b->GetVersionString() : NULL;
}

OrtStatus *tf_create_session(const OrtApi *api, OrtEnv *env, const char *utf8_path,
                             OrtSessionOptions *options, OrtSession **out) {
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, NULL, 0);
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
    MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, w, n);
    OrtStatus *st = api->CreateSession(env, w, options, out);
    free(w);
    return st;
}

// --- Sesion (parte 7.8) ----------------------------------------------------------------------------------
#include <stdio.h>
#include <string.h>

// DirectML: la API del proveedor (dml_provider_factory.h) se pide con GetExecutionProviderApi("DML"); solo se usa
// su primera entrada, asi que se declara aqui en vez de vendorizar la cabecera.
typedef struct tf_ort_dml_api {
    OrtStatus *(ORT_API_CALL *SessionOptionsAppendExecutionProvider_DML)(OrtSessionOptions *options, int device_id);
} tf_ort_dml_api;

struct tf_ort_session {
    OrtSession *session;
    OrtRunOptions *run_options;   // compartidas por todas las llamadas: tf_ort_session_terminate corta las que corren
    size_t n_in, n_out;
    char **in_names, **out_names;
};

static OrtEnv *g_env = NULL;
static OrtStatus *g_env_status = NULL;
static INIT_ONCE g_env_once = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK env_init(PINIT_ONCE o, PVOID p, PVOID *c) {
    (void)o; (void)p; (void)c;
    const OrtApi *api = tf_ort_api();
    if (api) g_env_status = api->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "toneforge", &g_env);
    return TRUE;
}

static int fail(const OrtApi *api, OrtStatus *st, const char *where, char *err, size_t err_len) {
    if (err && err_len) {
        if (api && st) snprintf(err, err_len, "%s: %s", where, api->GetErrorMessage(st));
        else snprintf(err, err_len, "%s", where);
    }
    if (api && st) api->ReleaseStatus(st);
    return 1;
}

#define TRY(call, where) do { OrtStatus *st_ = (call); if (st_) { rc = fail(api, st_, where, err, err_len); goto done; } } while (0)

static char *dup_name(const OrtApi *api, OrtAllocator *alloc, char *name) {
    char *copy = _strdup(name);
    (void)api->AllocatorFree(alloc, name);
    return copy;
}

int tf_ort_session_create(const char *utf8_path, const tf_ort_options *o, tf_ort_session **out,
                          char *err, size_t err_len) {
    *out = NULL;
    const OrtApi *api = tf_ort_api();
    if (!api) return fail(NULL, NULL, "sin onnxruntime.dll (o mas antigua que las cabeceras)", err, err_len);
    InitOnceExecuteOnce(&g_env_once, env_init, NULL, NULL);
    if (!g_env) return fail(NULL, NULL, "CreateEnv fallo", err, err_len);

    int rc = 0;
    OrtSessionOptions *opt = NULL;
    OrtSession *session = NULL;
    OrtCUDAProviderOptionsV2 *cuda = NULL;
    OrtAllocator *alloc = NULL;
    tf_ort_session *s = NULL;

    TRY(api->CreateSessionOptions(&opt), "CreateSessionOptions");
    TRY(api->SetSessionGraphOptimizationLevel(opt, ORT_ENABLE_ALL), "SetSessionGraphOptimizationLevel");
    if (o->intra_threads > 0) TRY(api->SetIntraOpNumThreads(opt, o->intra_threads), "SetIntraOpNumThreads");
    TRY(o->mem_arena ? api->EnableCpuMemArena(opt) : api->DisableCpuMemArena(opt), "CpuMemArena");
    // DirectML no admite el patron de memoria ni la ejecucion en paralelo (documentacion del proveedor).
    int pattern = o->provider == TF_ORT_DIRECTML ? 0 : o->mem_pattern;
    TRY(pattern ? api->EnableMemPattern(opt) : api->DisableMemPattern(opt), "MemPattern");
    TRY(api->SetSessionExecutionMode(opt, ORT_SEQUENTIAL), "SetSessionExecutionMode");

    switch (o->provider) {
    case TF_ORT_DIRECTML: {
        const void *p = NULL;
        TRY(api->GetExecutionProviderApi("DML", ORT_API_VERSION, &p), "DirectML (GetExecutionProviderApi)");
        if (!p) { rc = fail(NULL, NULL, "DirectML: la DLL no trae el proveedor", err, err_len); goto done; }
        TRY(((const tf_ort_dml_api *)p)->SessionOptionsAppendExecutionProvider_DML(opt, o->device_id), "DirectML");
        break;
    }
    case TF_ORT_CUDA: {
        char dev[16];
        snprintf(dev, sizeof dev, "%d", o->device_id);
        const char *keys[] = { "device_id" };
        const char *vals[] = { dev };
        TRY(api->CreateCUDAProviderOptions(&cuda), "CUDA (CreateCUDAProviderOptions)");
        TRY(api->UpdateCUDAProviderOptions(cuda, keys, vals, 1), "CUDA (UpdateCUDAProviderOptions)");
        TRY(api->SessionOptionsAppendExecutionProvider_CUDA_V2(opt, cuda), "CUDA");
        break;
    }
    case TF_ORT_QNN: {
        const char *keys[] = { "backend_path" };
        const char *vals[] = { "QnnHtp.dll" };   // NPU Hexagon de Snapdragon
        TRY(api->SessionOptionsAppendExecutionProvider(opt, "QNN", keys, vals, 1), "QNN");
        break;
    }
    default: break;
    }

    TRY(tf_create_session(api, g_env, utf8_path, opt, &session), "CreateSession");
    TRY(api->GetAllocatorWithDefaultOptions(&alloc), "GetAllocatorWithDefaultOptions");
    s = (tf_ort_session *)calloc(1, sizeof *s);
    s->session = session;
    session = NULL;
    TRY(api->CreateRunOptions(&s->run_options), "CreateRunOptions");
    TRY(api->SessionGetInputCount(s->session, &s->n_in), "SessionGetInputCount");
    TRY(api->SessionGetOutputCount(s->session, &s->n_out), "SessionGetOutputCount");
    s->in_names = (char **)calloc(s->n_in ? s->n_in : 1, sizeof(char *));
    s->out_names = (char **)calloc(s->n_out ? s->n_out : 1, sizeof(char *));
    for (size_t i = 0; i < s->n_in; i++) {
        char *name = NULL;
        TRY(api->SessionGetInputName(s->session, i, alloc, &name), "SessionGetInputName");
        s->in_names[i] = dup_name(api, alloc, name);
    }
    for (size_t i = 0; i < s->n_out; i++) {
        char *name = NULL;
        TRY(api->SessionGetOutputName(s->session, i, alloc, &name), "SessionGetOutputName");
        s->out_names[i] = dup_name(api, alloc, name);
    }
    *out = s;
    s = NULL;
done:
    if (s) tf_ort_session_release(s);
    if (session) api->ReleaseSession(session);
    if (cuda) api->ReleaseCUDAProviderOptions(cuda);
    if (opt) api->ReleaseSessionOptions(opt);
    return rc;
}

void tf_ort_session_release(tf_ort_session *s) {
    if (!s) return;
    const OrtApi *api = tf_ort_api();
    if (s->session && api) api->ReleaseSession(s->session);
    if (s->run_options && api) api->ReleaseRunOptions(s->run_options);
    for (size_t i = 0; s->in_names && i < s->n_in; i++) free(s->in_names[i]);
    for (size_t i = 0; s->out_names && i < s->n_out; i++) free(s->out_names[i]);
    free(s->in_names);
    free(s->out_names);
    free(s);
}

size_t tf_ort_session_input_count(const tf_ort_session *s) { return s->n_in; }
size_t tf_ort_session_output_count(const tf_ort_session *s) { return s->n_out; }
const char *tf_ort_session_input_name(const tf_ort_session *s, size_t i) { return i < s->n_in ? s->in_names[i] : NULL; }
const char *tf_ort_session_output_name(const tf_ort_session *s, size_t i) { return i < s->n_out ? s->out_names[i] : NULL; }

size_t tf_ort_session_input_shape(const tf_ort_session *s, size_t i, int64_t *dims, size_t cap) {
    const OrtApi *api = tf_ort_api();
    OrtTypeInfo *type = NULL;
    const OrtTensorTypeAndShapeInfo *info = NULL;
    size_t rank = 0;
    OrtStatus *st = api->SessionGetInputTypeInfo(s->session, i, &type);
    if (!st) st = api->CastTypeInfoToTensorInfo(type, &info);
    if (!st && info) st = api->GetDimensionsCount(info, &rank);
    if (!st && info && rank <= cap) st = api->GetDimensions(info, dims, rank);
    if (st) { api->ReleaseStatus(st); rank = 0; }
    if (type) api->ReleaseTypeInfo(type);
    return rank;
}

int tf_ort_session_run(tf_ort_session *s,
                       size_t n_in, const char *const *in_names, float *const *in_data,
                       const int64_t *const *in_shapes, const size_t *in_ranks,
                       size_t n_out, const char *const *out_names, float *const *out_buffers,
                       const int64_t *const *out_shapes, const size_t *out_ranks,
                       OrtValue **out_values, char *err, size_t err_len) {
    const OrtApi *api = tf_ort_api();
    int rc = 0;
    OrtMemoryInfo *mem = NULL;
    OrtValue **ins = (OrtValue **)calloc(n_in ? n_in : 1, sizeof(OrtValue *));
    for (size_t i = 0; i < n_out; i++) out_values[i] = NULL;

    TRY(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem), "CreateCpuMemoryInfo");
    for (size_t i = 0; i < n_in; i++) {
        size_t count = 1;
        for (size_t d = 0; d < in_ranks[i]; d++) count *= (size_t)in_shapes[i][d];
        TRY(api->CreateTensorWithDataAsOrtValue(mem, in_data[i], count * sizeof(float), in_shapes[i], in_ranks[i],
                                                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &ins[i]), "tensor de entrada");
    }
    for (size_t i = 0; i < n_out; i++) {
        if (!out_buffers[i]) continue;
        size_t count = 1;
        for (size_t d = 0; d < out_ranks[i]; d++) count *= (size_t)out_shapes[i][d];
        TRY(api->CreateTensorWithDataAsOrtValue(mem, out_buffers[i], count * sizeof(float), out_shapes[i], out_ranks[i],
                                                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &out_values[i]), "tensor de salida");
    }
    TRY(api->Run(s->session, s->run_options, in_names, (const OrtValue *const *)ins, n_in, out_names, n_out, out_values), "Run");
done:
    for (size_t i = 0; i < n_in; i++) if (ins[i]) api->ReleaseValue(ins[i]);
    free(ins);
    if (mem) api->ReleaseMemoryInfo(mem);
    if (rc) {
        for (size_t i = 0; i < n_out; i++) if (out_values[i]) { api->ReleaseValue(out_values[i]); out_values[i] = NULL; }
    } else {
        // Las salidas sobre memoria del llamante ya estan escritas: se sueltan aqui y el llamante solo ve NULL.
        for (size_t i = 0; i < n_out; i++)
            if (out_buffers[i] && out_values[i]) { api->ReleaseValue(out_values[i]); out_values[i] = NULL; }
    }
    return rc;
}

void tf_ort_session_terminate(tf_ort_session *s) {
    const OrtApi *api = tf_ort_api();
    if (!api || !s->run_options) return;
    OrtStatus *st = api->RunOptionsSetTerminate(s->run_options);
    if (st) api->ReleaseStatus(st);
}

size_t tf_ort_value_shape(const OrtValue *v, int64_t *dims, size_t cap) {
    const OrtApi *api = tf_ort_api();
    OrtTensorTypeAndShapeInfo *info = NULL;
    size_t rank = 0;
    OrtStatus *st = api->GetTensorTypeAndShape(v, &info);
    if (!st) st = api->GetDimensionsCount(info, &rank);
    if (!st && rank <= cap) st = api->GetDimensions(info, dims, rank);
    if (st) { api->ReleaseStatus(st); rank = 0; }
    if (info) api->ReleaseTensorTypeAndShapeInfo(info);
    return rank;
}

float *tf_ort_value_data(OrtValue *v) {
    const OrtApi *api = tf_ort_api();
    void *p = NULL;
    OrtStatus *st = api->GetTensorMutableData(v, &p);
    if (st) { api->ReleaseStatus(st); return NULL; }
    return (float *)p;
}

void tf_ort_value_release(OrtValue *v) {
    const OrtApi *api = tf_ort_api();
    if (v && api) api->ReleaseValue(v);
}
#endif
