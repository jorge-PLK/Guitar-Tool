// Anfitrión WebView2 (plan, «Fase 7c», paso 8, parte 8.0). Ver CWebView2Host.h.
#include "CWebView2Host.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <dwmapi.h>
#include <wrl.h>
#include <WebView2.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>

// Cabeceras y WebView2LoaderStatic.lib x64 vienen de Vendor/win/webview2 (Tools/win/fetch-webview2.sh); el
// /LIBPATH lo pone WinApp/Package.swift. El loader estático no pide WebView2Loader.dll.
#pragma comment(lib, "WebView2LoaderStatic.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "version.lib")
#pragma comment(lib, "runtimeobject.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "uuid.lib")

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

// Origen servido por SetVirtualHostNameToFolderMapping; fuera de él se bloquea toda navegación.
const wchar_t* const kAppHost = L"app.toneforge";
const wchar_t* const kAppOrigin = L"https://app.toneforge/";
const wchar_t* const kStartUrl = L"https://app.toneforge/index.html";
// Fondo mientras carga (evita el parpadeo blanco): mismo tono oscuro que el diseño.
const COLORREF kBackground = RGB(0x0E, 0x0E, 0x10);
const UINT WM_TF_POST = WM_APP + 1;
const UINT WM_TF_CAPTURE = WM_APP + 2;
const UINT WM_TF_QUIT = WM_APP + 3;
const UINT WM_TF_PICK = WM_APP + 4;
const UINT WM_TF_OPEN = WM_APP + 5;
const DWORD kCreateTimeoutMs = 60000;
const wchar_t* const kClassName = L"ToneForgeHostWindow";

const wchar_t* const kFallbackHtml =
    L"<!doctype html><meta charset=utf-8><title>ToneForge</title>"
    L"<body style=\"margin:0;background:#0e0e10;color:#e8e8ea;font:16px Segoe UI,sans-serif;display:flex;"
    L"flex-direction:column;align-items:center;justify-content:center;height:100vh;gap:12px\">"
    L"<h2 style=\"font-weight:500\">ToneForge &middot; falta Web/</h2>"
    L"<div style=\"opacity:.6\">No hay Web\\index.html junto al ejecutable.</div>"
    L"<button id=b style=\"padding:6px 14px\">enviar {&quot;ping&quot;:true}</button>"
    L"<pre id=log style=\"opacity:.8;max-width:80vw;white-space:pre-wrap\"></pre>"
    L"<script>const l=document.getElementById('log');"
    L"document.getElementById('b').onclick=()=>chrome.webview.postMessage('{\"ping\":true}');"
    L"chrome.webview.addEventListener('message',e=>{l.textContent+=e.data+'\\n'});</script>";

thread_local std::string g_lastError;
std::string g_lastErrorShared;   // lectura desde cualquier hilo tras un fallo de create

void setError(const std::string& s) {
    g_lastError = s;
    g_lastErrorShared = s;
}

std::string hrString(const char* what, HRESULT hr) {
    char buf[96];
    snprintf(buf, sizeof buf, "%s (HRESULT 0x%08lX)", what, static_cast<unsigned long>(hr));
    return buf;
}

std::wstring widen(const char* s) {
    if (!s || !*s) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    if (n <= 1) return std::wstring();
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    w.resize(static_cast<size_t>(n) - 1);
    return w;
}

std::string narrow(const wchar_t* w) {
    if (!w || !*w) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 1) return std::string();
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
    s.resize(static_cast<size_t>(n) - 1);
    return s;
}

// Ruta de Windows desde lo que da Swift: "/" -> "\" y sin la barra delante de la unidad ("/C:/x" -> "C:\x").
std::wstring widenPath(const char* s) {
    std::wstring w = widen(s);
    for (auto& c : w) if (c == L'/') c = L'\\';
    if (w.size() >= 3 && w[0] == L'\\' && w[2] == L':') w.erase(0, 1);
    return w;
}

bool startsWith(const std::wstring& s, const wchar_t* prefix) {
    return s.compare(0, wcslen(prefix), prefix) == 0;
}

struct PickRequest {
    bool folder;
    bool multi = false;    // selección múltiple: `result` lleva las rutas separadas por "\n" y `count` cuántas
    int count = 0;
    std::wstring title;
    std::wstring filter;   // "wav;flac" -> "*.wav;*.flac"
    std::wstring result;
    int rc;                // 1 elegido, 0 cancelado, -1 error
};

// Diálogo IFileOpenDialog modal sobre `owner`; en el hilo de UI.
void runPick(HWND owner, PickRequest* r) {
    r->rc = -1;
    ComPtr<IFileOpenDialog> dlg;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dlg)))) return;
    DWORD opts = 0;
    dlg->GetOptions(&opts);
    opts |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
    if (r->folder) opts |= FOS_PICKFOLDERS; else opts |= FOS_FILEMUSTEXIST;
    if (r->multi && !r->folder) opts |= FOS_ALLOWMULTISELECT;
    dlg->SetOptions(opts);
    if (!r->title.empty()) dlg->SetTitle(r->title.c_str());
    COMDLG_FILTERSPEC specs[2];
    std::wstring audio = L"Archivos admitidos";
    if (!r->folder && !r->filter.empty()) {
        specs[0] = {audio.c_str(), r->filter.c_str()};
        specs[1] = {L"Todos los archivos", L"*.*"};
        dlg->SetFileTypes(2, specs);
    }
    HRESULT hr = dlg->Show(owner);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { r->rc = 0; return; }
    if (FAILED(hr)) return;
    if (r->multi && !r->folder) {
        ComPtr<IShellItemArray> items;
        DWORD n = 0;
        if (FAILED(dlg->GetResults(&items)) || FAILED(items->GetCount(&n))) return;
        std::wstring all;
        int got = 0;
        for (DWORD i = 0; i < n; i++) {
            ComPtr<IShellItem> it;
            PWSTR p = nullptr;
            if (FAILED(items->GetItemAt(i, &it)) || FAILED(it->GetDisplayName(SIGDN_FILESYSPATH, &p)) || !p) continue;
            if (got > 0) all += L'\n';
            all += p;
            CoTaskMemFree(p);
            got++;
        }
        if (got == 0) return;
        r->result = all;
        r->count = got;
        r->rc = 1;
        return;
    }
    ComPtr<IShellItem> item;
    if (FAILED(dlg->GetResult(&item))) return;
    PWSTR path = nullptr;
    if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) || !path) return;
    r->result = path;
    CoTaskMemFree(path);
    r->rc = 1;
}

int copyOut(const std::wstring& w, char* out, int cap) {
    std::string u = narrow(w.c_str());
    if (!out || cap <= 0 || static_cast<int>(u.size()) + 1 > cap) return -1;
    memcpy(out, u.c_str(), u.size() + 1);
    return 1;
}

struct OpenRequest {
    std::wstring url;
    int rc;   // 1 lanzado, 0 no
};

// ShellExecuteEx sin interfaz (SEE_MASK_FLAG_NO_UI: sin el aviso «no hay aplicación» si el esquema no está registrado);
// en el hilo de UI (STA). Éxito = TRUE y hInstApp > 32.
void runOpen(OpenRequest* r) {
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof sei;
    sei.fMask = SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC;
    sei.lpVerb = L"open";
    sei.lpFile = r->url.c_str();
    sei.nShow = SW_SHOWNORMAL;
    r->rc = (ShellExecuteExW(&sei) && reinterpret_cast<INT_PTR>(sei.hInstApp) > 32) ? 1 : 0;
}

// Rutas de los ficheros que la página soltó (ICoreWebView2File::Path), separadas por "\n"; vacío si no hay.
std::string droppedPaths(ICoreWebView2WebMessageReceivedEventArgs* args) {
    ComPtr<ICoreWebView2WebMessageReceivedEventArgs2> a2;
    if (FAILED(args->QueryInterface(IID_PPV_ARGS(&a2)))) return std::string();
    ComPtr<ICoreWebView2ObjectCollectionView> objs;
    if (FAILED(a2->get_AdditionalObjects(&objs)) || !objs) return std::string();
    UINT32 n = 0;
    if (FAILED(objs->get_Count(&n))) return std::string();
    std::string all;
    for (UINT32 i = 0; i < n; i++) {
        ComPtr<IUnknown> obj;
        ComPtr<ICoreWebView2File> file;
        LPWSTR path = nullptr;
        if (FAILED(objs->GetValueAtIndex(i, &obj)) || !obj || FAILED(obj.As(&file))) continue;
        if (FAILED(file->get_Path(&path)) || !path) continue;
        if (!all.empty()) all += '\n';
        all += narrow(path);
        CoTaskMemFree(path);
    }
    return all;
}

struct CaptureRequest {
    std::wstring path;
    void (*done)(int, void*);
    void* ctx;
};

}  // namespace

struct tfhost {
    tfhost_config cfg{};
    std::string title, webDir, userData;
    std::atomic<HWND> hwnd{nullptr};
    ComPtr<ICoreWebView2Environment> env;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> view;
    bool controllerReady = false;
    bool failed = false;
    bool devtools = false;
    bool allowData = false;       // página de reserva (NavigateToString)
    bool readyFired = false;
    bool loadFailed = false;
    HRESULT hr = S_OK;
    std::string failure;
};

namespace {

bool g_classRegistered = false;

void fail(tfhost* h, const char* what, HRESULT hr) {
    h->failed = true;
    h->hr = hr;
    h->failure = hrString(what, hr);
}

void resizeToClient(tfhost* h) {
    HWND w = h->hwnd.load();
    if (!h->controller || !w) return;
    RECT rc;
    GetClientRect(w, &rc);
    h->controller->put_Bounds(rc);
}

// Configura ajustes, manejadores y el mapeo de app.toneforge cuando el controlador existe.
void controllerReady(tfhost* h) {
    h->controller->get_CoreWebView2(&h->view);
    resizeToClient(h);

    ComPtr<ICoreWebView2Controller2> c2;
    if (SUCCEEDED(h->controller.As(&c2))) {
        COREWEBVIEW2_COLOR bg = {255, GetRValue(kBackground), GetGValue(kBackground), GetBValue(kBackground)};
        c2->put_DefaultBackgroundColor(bg);
    }

    ComPtr<ICoreWebView2Settings> s;
    if (SUCCEEDED(h->view->get_Settings(&s))) {
        s->put_IsScriptEnabled(TRUE);
        s->put_IsWebMessageEnabled(TRUE);
        s->put_AreDefaultScriptDialogsEnabled(TRUE);
        s->put_IsStatusBarEnabled(FALSE);
        s->put_IsZoomControlEnabled(FALSE);
        s->put_AreHostObjectsAllowed(FALSE);
        s->put_AreDefaultContextMenusEnabled(h->devtools ? TRUE : FALSE);
        s->put_AreDevToolsEnabled(h->devtools ? TRUE : FALSE);
        ComPtr<ICoreWebView2Settings3> s3;
        if (SUCCEEDED(s.As(&s3))) s3->put_AreBrowserAcceleratorKeysEnabled(h->devtools ? TRUE : FALSE);
    }

    EventRegistrationToken tok;
    h->view->add_WebMessageReceived(
        Callback<ICoreWebView2WebMessageReceivedEventHandler>(
            [h](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                LPWSTR msg = nullptr;
                if (SUCCEEDED(args->TryGetWebMessageAsString(&msg)) && msg) {
                    std::string u = narrow(msg);
                    CoTaskMemFree(msg);
                    // Soltar ficheros: la página manda host.dropFiles con los ficheros como objetos adicionales; el
                    // mensaje no sigue al puente, las rutas van por on_files_dropped (hilo de UI).
                    std::string dropped = droppedPaths(args);
                    if (!dropped.empty()) {
                        if (h->cfg.on_files_dropped) h->cfg.on_files_dropped(dropped.c_str(), h->cfg.ctx);
                        return S_OK;
                    }
                    if (h->cfg.on_message) h->cfg.on_message(u.c_str(), h->cfg.ctx);
                }
                return S_OK;
            }).Get(), &tok);

    h->view->add_NavigationStarting(
        Callback<ICoreWebView2NavigationStartingEventHandler>(
            [h](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                LPWSTR uri = nullptr;
                args->get_Uri(&uri);
                std::wstring u = uri ? uri : L"";
                if (uri) CoTaskMemFree(uri);
                bool ok = startsWith(u, kAppOrigin) || u == L"about:blank" || (h->allowData && startsWith(u, L"data:"));
                if (!ok) args->put_Cancel(TRUE);
                return S_OK;
            }).Get(), &tok);

    h->view->add_NewWindowRequested(
        Callback<ICoreWebView2NewWindowRequestedEventHandler>(
            [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
                args->put_Handled(TRUE);
                return S_OK;
            }).Get(), &tok);

    h->view->add_NavigationCompleted(
        Callback<ICoreWebView2NavigationCompletedEventHandler>(
            [h](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                if (h->readyFired) return S_OK;
                BOOL ok = FALSE;
                args->get_IsSuccess(&ok);
                if (!ok) {
                    COREWEBVIEW2_WEB_ERROR_STATUS st = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
                    args->get_WebErrorStatus(&st);
                    h->loadFailed = true;
                    setError(hrString("la navegacion inicial fallo (WebErrorStatus)", static_cast<HRESULT>(st)));
                    HWND w = h->hwnd.load();
                    if (w) PostMessageW(w, WM_TF_QUIT, 0, 0);
                    return S_OK;
                }
                h->readyFired = true;
                if (h->cfg.on_ready) h->cfg.on_ready(h->cfg.ctx);
                return S_OK;
            }).Get(), &tok);

    // La carpeta Web se sirve como https://app.toneforge/ (solo lectura de ficheros: ALLOW).
    ComPtr<ICoreWebView2_3> v3;
    if (SUCCEEDED(h->view.As(&v3)) && !h->webDir.empty()) {
        std::wstring dir = widenPath(h->webDir.c_str());
        HRESULT hr = v3->SetVirtualHostNameToFolderMapping(kAppHost, dir.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
        if (FAILED(hr)) { fail(h, "SetVirtualHostNameToFolderMapping(app.toneforge)", hr); return; }
    }
    h->controllerReady = true;
}

LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
        return DefWindowProcW(hwnd, msg, wp, lp);
    }
    auto* h = reinterpret_cast<tfhost*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (msg) {
    case WM_ERASEBKGND: {
        RECT rc;
        GetClientRect(hwnd, &rc);
        HBRUSH b = CreateSolidBrush(kBackground);
        FillRect(reinterpret_cast<HDC>(wp), &rc, b);
        DeleteObject(b);
        return 1;
    }
    case WM_SIZE:
        if (h && wp != SIZE_MINIMIZED) resizeToClient(h);
        return 0;
    case WM_MOVE:
        if (h && h->controller) h->controller->NotifyParentWindowPositionChanged();
        return 0;
    case WM_DPICHANGED: {
        const RECT* r = reinterpret_cast<const RECT*>(lp);
        SetWindowPos(hwnd, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top, SWP_NOZORDER | SWP_NOACTIVATE);
        return 0;
    }
    case WM_GETMINMAXINFO: {
        UINT dpi = GetDpiForWindow(hwnd);
        auto* mm = reinterpret_cast<MINMAXINFO*>(lp);
        mm->ptMinTrackSize.x = MulDiv(640, static_cast<int>(dpi), 96);
        mm->ptMinTrackSize.y = MulDiv(420, static_cast<int>(dpi), 96);
        return 0;
    }
    case WM_SETFOCUS:
        if (h && h->controller) h->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
        return 0;
    case WM_TF_POST: {
        std::wstring* s = reinterpret_cast<std::wstring*>(lp);
        if (h && h->view) h->view->PostWebMessageAsString(s->c_str());
        delete s;
        return 0;
    }
    case WM_TF_CAPTURE: {
        CaptureRequest* r = reinterpret_cast<CaptureRequest*>(lp);
        if (!h || !h->view) {
            if (r->done) r->done(0, r->ctx);
            delete r;
            return 0;
        }
        IStream* stream = nullptr;
        HRESULT hr = SHCreateStreamOnFileEx(r->path.c_str(), STGM_CREATE | STGM_WRITE | STGM_SHARE_EXCLUSIVE,
                                            FILE_ATTRIBUTE_NORMAL, TRUE, nullptr, &stream);
        if (SUCCEEDED(hr)) {
            auto done = r->done;
            auto ctx = r->ctx;
            hr = h->view->CapturePreview(
                COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream,
                Callback<ICoreWebView2CapturePreviewCompletedHandler>([stream, done, ctx](HRESULT result) -> HRESULT {
                    stream->Commit(STGC_DEFAULT);
                    stream->Release();   // cierra el fichero
                    if (done) done(SUCCEEDED(result) ? 1 : 0, ctx);
                    return S_OK;
                }).Get());
            if (FAILED(hr)) {
                stream->Release();
                if (done) done(0, ctx);
            }
        } else if (r->done) {
            r->done(0, r->ctx);
        }
        delete r;
        return 0;
    }
    case WM_TF_PICK:
        runPick(hwnd, reinterpret_cast<PickRequest*>(lp));
        return 0;
    case WM_TF_OPEN:
        runOpen(reinterpret_cast<OpenRequest*>(lp));
        return 0;
    case WM_TF_QUIT:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        if (h) {
            h->hwnd.store(nullptr);
            if (h->controller) h->controller->Close();
            h->view.Reset();
            h->controller.Reset();
            if (h->cfg.on_close) h->cfg.on_close(h->cfg.ctx);
        }
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

}  // namespace

extern "C" {

tfhost* tfhost_create(const tfhost_config* config) {
    if (!config) { setError("config nula"); return nullptr; }
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) { setError(hrString("CoInitializeEx", hr)); return nullptr; }

    auto* h = new tfhost();
    h->cfg = *config;
    h->title = config->title_utf8 ? config->title_utf8 : "ToneForge";
    h->webDir = config->web_dir_utf8 ? config->web_dir_utf8 : "";
    h->userData = config->user_data_dir_utf8 ? config->user_data_dir_utf8 : "";
    h->cfg.title_utf8 = h->title.c_str();
    h->cfg.web_dir_utf8 = h->webDir.c_str();
    h->cfg.user_data_dir_utf8 = h->userData.c_str();
    wchar_t dev[8] = {0};
    h->devtools = GetEnvironmentVariableW(L"TF_WEB_DEVTOOLS", dev, 8) > 0 && wcscmp(dev, L"1") == 0;

    HINSTANCE inst = GetModuleHandleW(nullptr);
    if (!g_classRegistered) {
        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof wc;
        wc.lpfnWndProc = wndProc;
        wc.hInstance = inst;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(1));
        if (!wc.hIcon) wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
        wc.hbrBackground = nullptr;   // lo pinta WM_ERASEBKGND
        wc.lpszClassName = kClassName;
        if (!RegisterClassExW(&wc)) { setError(hrString("RegisterClassEx", HRESULT_FROM_WIN32(GetLastError()))); delete h; return nullptr; }
        g_classRegistered = true;
    }

    UINT dpi = GetDpiForSystem();
    int cw = MulDiv(config->width > 0 ? config->width : 1440, static_cast<int>(dpi), 96);
    int ch = MulDiv(config->height > 0 ? config->height : 900, static_cast<int>(dpi), 96);
    RECT frame = {0, 0, cw, ch};
    AdjustWindowRectExForDpi(&frame, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi);
    int fw = frame.right - frame.left, fh = frame.bottom - frame.top;
    // Limita el tamaño inicial al área de trabajo del monitor principal (sin barra de tareas) y centra la ventana.
    RECT work = {0, 0, fw, fh};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    POINT origin = {0, 0};
    HMONITOR mon = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi = {};
    mi.cbSize = sizeof mi;
    if (GetMonitorInfoW(mon, &mi)) work = mi.rcWork;
    int ww = work.right - work.left, wh = work.bottom - work.top;
    if (fw > ww) fw = ww;
    if (fh > wh) fh = wh;
    int x = work.left + (ww - fw) / 2, y = work.top + (wh - fh) / 2;
    std::wstring title = widen(h->title.c_str());
    HWND hwnd = CreateWindowExW(0, kClassName, title.c_str(), WS_OVERLAPPEDWINDOW, x, y, fw, fh, nullptr, nullptr, inst, h);
    if (!hwnd) { setError(hrString("CreateWindowEx", HRESULT_FROM_WIN32(GetLastError()))); delete h; return nullptr; }
    // Barra de título oscura (DWMWA_USE_IMMERSIVE_DARK_MODE = 20).
    BOOL dark = TRUE;
    DwmSetWindowAttribute(hwnd, 20, &dark, sizeof dark);
    h->hwnd.store(hwnd);
    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);

    std::wstring userData = widenPath(h->userData.c_str());
    hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, userData.empty() ? nullptr : userData.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [h, hwnd](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                if (FAILED(result) || !env) { fail(h, "CreateCoreWebView2Environment", FAILED(result) ? result : E_FAIL); return S_OK; }
                h->env = env;
                HRESULT r2 = env->CreateCoreWebView2Controller(
                    hwnd, Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [h](HRESULT result2, ICoreWebView2Controller* controller) -> HRESULT {
                            if (FAILED(result2) || !controller) { fail(h, "CreateCoreWebView2Controller", FAILED(result2) ? result2 : E_FAIL); return S_OK; }
                            h->controller = controller;
                            controllerReady(h);
                            return S_OK;
                        }).Get());
                if (FAILED(r2)) fail(h, "CreateCoreWebView2Controller (llamada)", r2);
                return S_OK;
            }).Get());
    if (FAILED(hr)) {
        std::string m = hrString("CreateCoreWebView2EnvironmentWithOptions", hr);
        if (hr == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)) m += " - falta el runtime WebView2 de Evergreen";
        setError(m);
        DestroyWindow(hwnd);
        return nullptr;
    }

    // Bombea mensajes hasta que el controlador esté listo (los callbacks llegan por la cola de la ventana).
    DWORD t0 = GetTickCount();
    while (!h->controllerReady && !h->failed) {
        MSG m;
        while (PeekMessageW(&m, nullptr, 0, 0, PM_REMOVE)) {
            if (m.message == WM_QUIT) { h->failed = true; h->failure = "ventana cerrada durante la creacion"; break; }
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        if (h->failed || h->controllerReady) break;
        if (GetTickCount() - t0 > kCreateTimeoutMs) { h->failed = true; h->failure = "WebView2 no estuvo listo en 60 s"; break; }
        MsgWaitForMultipleObjects(0, nullptr, FALSE, 50, QS_ALLINPUT);
    }
    if (h->failed) {
        setError(h->failure);
        if (h->hwnd.load()) DestroyWindow(hwnd);
        return nullptr;
    }
    return h;
}

int tfhost_map_folder(tfhost* h, const char* host_utf8, const char* folder_utf8) {
    if (!h || !h->view || !host_utf8 || !folder_utf8) return static_cast<int>(E_INVALIDARG);
    ComPtr<ICoreWebView2_3> v3;
    HRESULT hr = h->view.As(&v3);
    if (SUCCEEDED(hr)) {
        std::wstring host = widen(host_utf8), folder = widenPath(folder_utf8);
        hr = v3->SetVirtualHostNameToFolderMapping(host.c_str(), folder.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
    }
    if (FAILED(hr)) setError(hrString("SetVirtualHostNameToFolderMapping", hr));
    return static_cast<int>(hr);
}

void tfhost_post(tfhost* h, const char* utf8) {
    if (!h || !utf8) return;
    HWND w = h->hwnd.load();
    if (!w) return;
    auto* s = new std::wstring(widen(utf8));
    if (!PostMessageW(w, WM_TF_POST, 0, reinterpret_cast<LPARAM>(s))) delete s;
}

void tfhost_capture_png(tfhost* h, const char* path_utf8, void (*done)(int, void*), void* ctx) {
    HWND w = h ? h->hwnd.load() : nullptr;
    auto* r = new CaptureRequest{widenPath(path_utf8), done, ctx};
    if (!w || !PostMessageW(w, WM_TF_CAPTURE, 0, reinterpret_cast<LPARAM>(r))) {
        delete r;
        if (done) done(0, ctx);
    }
}

int tfhost_run(tfhost* h) {
    if (!h || !h->view) return 1;
    std::wstring index = widenPath(h->webDir.c_str());
    if (!index.empty() && index.back() != L'\\') index += L'\\';
    index += L"index.html";
    if (!h->webDir.empty() && GetFileAttributesW(index.c_str()) != INVALID_FILE_ATTRIBUTES) {
        h->view->Navigate(kStartUrl);
    } else {
        h->allowData = true;
        h->view->NavigateToString(kFallbackHtml);
    }
    MSG m;
    while (GetMessageW(&m, nullptr, 0, 0) > 0) {
        TranslateMessage(&m);
        DispatchMessageW(&m);
    }
    return h->loadFailed ? 1 : 0;
}

void tfhost_quit(tfhost* h) {
    HWND w = h ? h->hwnd.load() : nullptr;
    if (w) PostMessageW(w, WM_TF_QUIT, 0, 0);
}

static int pick(tfhost* h, bool folder, bool multi, const char* title, const char* filter, char* out, int cap) {
    HWND w = h ? h->hwnd.load() : nullptr;
    if (!w) return -1;
    PickRequest r;
    r.folder = folder;
    r.multi = multi;
    r.title = widen(title);
    if (filter && *filter) {
        std::wstring f = widen(filter), spec;
        size_t i = 0;
        while (i <= f.size()) {
            size_t j = f.find(L';', i);
            if (j == std::wstring::npos) j = f.size();
            if (j > i) { if (!spec.empty()) spec += L';'; spec += L"*."; spec += f.substr(i, j - i); }
            i = j + 1;
        }
        r.filter = spec;
    }
    r.rc = -1;
    if (GetWindowThreadProcessId(w, nullptr) == GetCurrentThreadId()) runPick(w, &r);
    else SendMessageW(w, WM_TF_PICK, 0, reinterpret_cast<LPARAM>(&r));
    if (r.rc != 1) return r.rc;
    if (multi) {
        std::string u = narrow(r.result.c_str());
        int needed = static_cast<int>(u.size()) + 1;
        if (!out || cap < needed) return -needed;   // >= 2: -1 queda para «falló»
        memcpy(out, u.c_str(), static_cast<size_t>(needed));
        return r.count;
    }
    return copyOut(r.result, out, cap) == 1 ? 1 : -1;
}

int tfhost_pick_file(tfhost* h, const char* title, const char* filter, char* out, int cap) {
    return pick(h, false, false, title, filter, out, cap);
}

int tfhost_pick_folder(tfhost* h, const char* title, char* out, int cap) {
    return pick(h, true, false, title, nullptr, out, cap);
}

int tfhost_pick_files(tfhost* h, const char* title, const char* filter, char* out, int cap) {
    return pick(h, false, true, title, filter, out, cap);
}

int tfhost_open_url(tfhost* h, const char* url_utf8) {
    HWND w = h ? h->hwnd.load() : nullptr;
    if (!w || !url_utf8 || !*url_utf8) return 0;
    OpenRequest r;
    r.url = widen(url_utf8);
    r.rc = 0;
    if (GetWindowThreadProcessId(w, nullptr) == GetCurrentThreadId()) runOpen(&r);
    else SendMessageW(w, WM_TF_OPEN, 0, reinterpret_cast<LPARAM>(&r));
    return r.rc;
}

int tfhost_single_instance(void) {
    HANDLE m = CreateMutexW(nullptr, FALSE, L"Local\\ToneForge.SingleInstance");   // se queda abierto a propósito
    if (m && GetLastError() == ERROR_ALREADY_EXISTS) {
        HWND other = FindWindowW(kClassName, nullptr);
        if (other) {
            if (IsIconic(other)) ShowWindow(other, SW_RESTORE);
            SetForegroundWindow(other);
        }
        return 0;
    }
    return 1;
}

const char* tfhost_last_error(void) {
    return g_lastError.empty() ? g_lastErrorShared.c_str() : g_lastError.c_str();
}

}  // extern "C"
#endif
