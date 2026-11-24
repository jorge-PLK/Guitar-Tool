// Enlaces dart:ffi a la ABI congelada de AppCoreFFI (`tf_core.h`, 10 funciones).
// Sin paquete `ffi`: malloc/free de la libc (proceso en Mac, ucrtbase.dll en Windows), como en P9.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

typedef _InitC = IntPtr Function(Pointer<Void>);
typedef _StartC = Int32 Function(Pointer<Uint8>, Int64);
typedef _SendC = Void Function(Pointer<Uint8>, Int32);
typedef _FreeC = Void Function(Pointer<Uint8>);
typedef _ShutdownC = Void Function(Int32);
typedef _VoidC = Void Function();
typedef _SetHostC = Void Function(Pointer<Void>);
typedef _TexCreateC = Int64 Function(Int32);
typedef _TexDisposeC = Void Function(Int32);
typedef _FrameCopyC = Pointer<Void> Function(Int32);

class TfBindings {
  TfBindings._(DynamicLibrary lib, DynamicLibrary libc)
      : initDartApi = lib.lookupFunction<_InitC, int Function(Pointer<Void>)>(
            'tf_core_init_dart_api'),
        _start = lib.lookupFunction<_StartC, int Function(Pointer<Uint8>, int)>(
            'tf_core_start'),
        _send = lib.lookupFunction<_SendC, void Function(Pointer<Uint8>, int)>(
            'tf_core_send'),
        free = lib.lookupFunction<_FreeC, void Function(Pointer<Uint8>)>(
            'tf_core_free'),
        shutdown = lib.lookupFunction<_ShutdownC, void Function(int)>(
            'tf_core_shutdown'),
        runMain = lib.lookupFunction<_VoidC, void Function()>('tf_core_run_main'),
        setTextureHost = lib.lookupFunction<_SetHostC,
            void Function(Pointer<Void>)>('tf_core_set_texture_host'),
        textureCreate = lib.lookupFunction<_TexCreateC, int Function(int)>(
            'tf_texture_create'),
        textureDispose = lib.lookupFunction<_TexDisposeC, void Function(int)>(
            'tf_texture_dispose'),
        frameCopy = lib.lookupFunction<_FrameCopyC, Pointer<Void> Function(int)>(
            'tf_frame_copy'),
        _malloc = libc.lookupFunction<Pointer<Uint8> Function(IntPtr),
            Pointer<Uint8> Function(int)>('malloc'),
        _cfree = libc.lookupFunction<Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)>('free');

  /// Mac: `coreLib` (`--core-lib`) o, sin él, los símbolos del proceso. Windows: `AppCoreFFI.dll`.
  factory TfBindings.open({String? coreLib}) {
    if (Platform.isWindows) {
      return TfBindings._(DynamicLibrary.open(coreLib ?? 'AppCoreFFI.dll'),
          DynamicLibrary.open('ucrtbase.dll'));
    }
    final proc = DynamicLibrary.process();
    return TfBindings._(
        coreLib != null ? DynamicLibrary.open(coreLib) : proc, proc);
  }

  /// 0 = bien. Una vez, antes de [start].
  final int Function(Pointer<Void>) initDartApi;
  final int Function(Pointer<Uint8>, int) _start;
  final void Function(Pointer<Uint8>, int) _send;

  /// Libera un búfer del núcleo (`tf_core_free`).
  final void Function(Pointer<Uint8>) free;

  /// Asíncrono: el final llega como evento `core.shutdown`.
  final void Function(int) shutdown;

  /// Solo el runner de Windows; no vuelve.
  final void Function() runMain;

  /// Solo el runner, antes de que arranque Dart.
  final void Function(Pointer<Void>) setTextureHost;

  /// Id de textura del canal; −1 sin texturas.
  final int Function(int) textureCreate;
  final void Function(int) textureDispose;

  /// Último fotograma del canal (lo llama la textura del runner, no Dart).
  final Pointer<Void> Function(int) frameCopy;
  final Pointer<Uint8> Function(int) _malloc;
  final void Function(Pointer<Uint8>) _cfree;

  /// 0 ok; 1 ya arrancado; 2 opciones inválidas; 3 falló Bridge.init.
  int start(String optionsJson, int port) {
    final p = _cString(utf8.encode(optionsJson), terminate: true);
    try {
      return _start(p, port);
    } finally {
      _cfree(p);
    }
  }

  /// El núcleo copia los bytes antes de volver.
  void send(List<int> utf8Bytes) {
    final p = _cString(utf8Bytes);
    try {
      _send(p, utf8Bytes.length);
    } finally {
      _cfree(p);
    }
  }

  Pointer<Uint8> _cString(List<int> b, {bool terminate = false}) {
    final n = b.length + (terminate ? 1 : 0);
    final p = _malloc(n == 0 ? 1 : n);
    final view = p.asTypedList(n);
    view.setAll(0, b);
    if (terminate) view[b.length] = 0;
    return p;
  }
}
