#pragma once
// Shim C/COM de Windows (CWebView2Host): ventana Win32 con un WebView2 a pantalla completa (plan, «Fase 7c», paso 8,
// parte 8.0; ADR-020). Solo existe en Windows; en el resto de plataformas el objetivo compila vacío.
//
// Hilos: tfhost_create y tfhost_run van en el mismo hilo (el de UI, que queda en STA).
// tfhost_map_folder, tfhost_post, tfhost_capture_png y tfhost_quit pueden llamarse desde cualquier hilo (se reenvían al de UI);
// los callbacks (on_ready, on_message, on_close, done) corren siempre en el hilo de UI.
// La página envía con chrome.webview.postMessage(string) y recibe con chrome.webview.addEventListener('message', e => e.data).
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
typedef struct tfhost tfhost;

typedef struct {
    const char* title_utf8;
    int width, height;                  // tamaño del área de cliente en píxeles lógicos (a 96 ppp)
    const char* web_dir_utf8;           // se sirve como https://app.toneforge/
    const char* user_data_dir_utf8;     // carpeta de datos de WebView2
    void (*on_ready)(void* ctx);                     // navegación inicial terminada
    void (*on_message)(const char* utf8, void* ctx); // mensaje string de la página
    void (*on_close)(void* ctx);
    // Ficheros soltados sobre la página (host.dropFiles con objetos adicionales): rutas UTF-8 separadas por "\n". Hilo de UI.
    void (*on_files_dropped)(const char* paths_utf8, void* ctx);
    void* ctx;
} tfhost_config;

/// Crea la ventana y el WebView2 (espera, bombeando mensajes, a que el controlador esté listo; tope 60 s).
/// NULL y tfhost_last_error() si falla.
tfhost* tfhost_create(const tfhost_config* config);
/// Mapea https://<host>/ a una carpeta (acceso ALLOW); p. ej. media.toneforge. 0 bien, distinto de 0 HRESULT.
int tfhost_map_folder(tfhost* host, const char* host_utf8, const char* folder_utf8);
/// PostWebMessageAsString, seguro desde cualquier hilo.
void tfhost_post(tfhost* host, const char* utf8);
/// CapturePreview a un PNG; done(ok, ctx) en el hilo de UI. Seguro desde cualquier hilo.
void tfhost_capture_png(tfhost* host, const char* path_utf8, void (*done)(int ok, void* ctx), void* ctx);
/// Navega a la página inicial y corre el bucle de mensajes; vuelve al cerrar. 0 bien, 1 si falló la carga inicial.
int tfhost_run(tfhost* host);
/// Cierra la ventana (y con ello vuelve tfhost_run). Seguro desde cualquier hilo.
void tfhost_quit(tfhost* host);
const char* tfhost_last_error(void);

/// Selector de fichero modal sobre la ventana (IFileOpenDialog). `filter_spec_utf8`: extensiones sin punto separadas
/// por ";" ("wav;flac;mp3"), NULL o "" para todos. Escribe la ruta en `out_utf8` (UTF-8, terminada en 0, `cap` bytes).
/// Devuelve 1 si se eligió algo, 0 si se canceló, -1 si falló. Seguro desde cualquier hilo: el diálogo corre en el de UI
/// (SendMessage); quien llama espera. No llamar con el hilo de UI bloqueado esperando a quien llama.
int tfhost_pick_file(tfhost* host, const char* title_utf8, const char* filter_spec_utf8, char* out_utf8, int cap);
/// Como tfhost_pick_file con selección múltiple: escribe las rutas separadas por "\n" (UTF-8, terminada en 0) y devuelve
/// cuántas son; 0 si se canceló; -1 si falló; si `cap` no basta devuelve -N (N >= 2 = bytes necesarios, con el 0 final) tras
/// haber mostrado el diálogo (no reintentar: reabriría el selector; usar un búfer generoso). Mismas reglas de hilo.
int tfhost_pick_files(tfhost* host, const char* title_utf8, const char* filter_spec_utf8, char* out_utf8, int cap);
/// Abre una URL con la aplicación registrada para su esquema (ShellExecuteEx "open", sin diálogos). 1 si se lanzó, 0 si no
/// (esquema sin aplicación, URL vacía o ventana cerrada). Seguro desde cualquier hilo (corre en el de UI; quien llama espera).
int tfhost_open_url(tfhost* host, const char* url_utf8);
/// Igual para carpetas.
int tfhost_pick_folder(tfhost* host, const char* title_utf8, char* out_utf8, int cap);
/// Como tfhost_pick_folder, abriendo en `initial_utf8` (vacío o inexistente: la carpeta que elija Windows).
int tfhost_pick_folder_at(tfhost* host, const char* title_utf8, const char* initial_utf8, char* out_utf8, int cap);

/// Códigos de resultado de tfhost_hidden_load (primer argumento de `done`).
enum {
    TFHOST_HIDDEN_OK = 0,           // `status` = HTTP del documento principal (200 si no se pudo leer), `html` = outerHTML
    TFHOST_HIDDEN_OFFLINE = 1,      // fallo de navegación (sin red, DNS...) o tope agotado antes de terminar de cargar
    TFHOST_HIDDEN_READY_TIMEOUT = 2,// cargó pero `ready_script` no dio true en `timeout_ms`
    TFHOST_HIDDEN_HTTP = 3,         // documento principal con estado >= 400; `status` lleva el código
    TFHOST_HIDDEN_CANCELLED = 4,    // tfhost_hidden_cancel con ese id
    TFHOST_HIDDEN_UNAVAILABLE = 5   // sin ventana, no se pudo crear el navegador, o ya había otra carga en curso
};

/// Navegador oculto (W2-H): segundo WebView2 sin pantalla (ventana propia sin mostrar, perfil InPrivate = almacén no
/// persistente), creado en la primera carga. Una carga a la vez (serializar es cosa de quien llama; con otra en curso `done`
/// recibe UNAVAILABLE). Navega a `url_utf8`, evalúa `ready_script_utf8` (expresión JS con resultado booleano; NULL o "" = no
/// esperar) cada 250 ms tras cargar y devuelve `document.documentElement.outerHTML`. `timeout_ms` cuenta desde el inicio de
/// la navegación. El user agent es el propio de WebView2. `id` lo elige quien llama (distinto de 0) para tfhost_hidden_cancel.
/// `done(result, status, html_utf8, ctx)` se llama una sola vez, en el hilo de UI; `html_utf8` solo vale durante la llamada
/// (NULL salvo con OK). Seguro desde cualquier hilo (se reenvía al de UI).
void tfhost_hidden_load(tfhost* host, uint64_t id, const char* url_utf8, const char* ready_script_utf8, int timeout_ms,
                        void (*done)(int result, int status, const char* html_utf8, void* ctx), void* ctx);
/// Cancela la carga `id` si es la que corre (done recibe CANCELLED); si no, no hace nada. Seguro desde cualquier hilo.
void tfhost_hidden_cancel(tfhost* host, uint64_t id);

/// Vista previa visible (W2-H): tercer WebView2 (perfil normal, el mismo de la app: cookies persistentes) como hijo de la
/// ventana, encima de la página. `x,y,w,h` en píxeles CSS de la página (origen = esquina superior izquierda del área de
/// cliente); se multiplican por la escala del monitor. Con otra `url` navega; con la misma solo recoloca. Solo https.
/// Seguro desde cualquier hilo (se reenvía al de UI; el orden de llamadas del mismo hilo se conserva).
void tfhost_preview_show(tfhost* host, const char* url_utf8, double x, double y, double w, double h);
/// Oculta el panel y navega a about:blank (detiene el audio). Idempotente; sin panel no hace nada. Cualquier hilo.
void tfhost_preview_hide(tfhost* host);

/// Instancia única (mutex Local\ToneForge.SingleInstance, vive hasta que acaba el proceso). Devuelve 1 si esta es la
/// primera; si ya hay otra ToneForge abierta le trae la ventana al frente (la restaura si está minimizada) y devuelve 0.
/// Llamar antes de tfhost_create.
int tfhost_single_instance(void);

/// Deja el hilo que llama en STA (CoInitializeEx APARTMENTTHREADED, sin CoUninitialize). Llamar lo primero en el hilo de UI,
/// antes de crear el Bridge o tocar Media Foundation/WASAPI: esas piezas piden MTA y, si llegan antes, WebView2 ya no puede
/// crearse (RPC_E_CHANGED_MODE). Con STA ya puesto, su CoInitializeEx MTA devuelve RPC_E_CHANGED_MODE y siguen sin él.
/// 0 si el hilo queda en STA; si no, el HRESULT (p. ej. 0x80010106 si ya estaba en MTA).
int tfhost_init_ui_thread(void);
#endif

#ifdef __cplusplus
}
#endif
