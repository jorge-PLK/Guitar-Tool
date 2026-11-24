// Puente C: API DL de Dart y envío por puerto nativo. El resto de la ABI está en Swift (@_cdecl).
#include "tf_core.h"
#include "dart_api_dl.h"

intptr_t tf_core_init_dart_api(void *data) { return Dart_InitializeApiDL(data); }

/// Finalizador de Dart: mismo efecto que tf_core_free.
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
