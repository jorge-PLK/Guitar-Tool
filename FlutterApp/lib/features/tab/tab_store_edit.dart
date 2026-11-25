import 'package:toneforge/contract/tab.dart';

/// Intenciones de edición y selección de `tab.*`. Cada una devuelve el `TabState` aplicado (o `null` si falló).
/// La clase que la mezcla implementa [callTab] con su llamada al núcleo.
mixin TabStoreEdit {
  /// Llama [method] con [params] y aplica el `TabState` devuelto (`null` si falló).
  Future<TabState?> callTab(String method, Object? params);

  Future<TabState?> beatClick(TabClickParams p) => callTab('tab.beatClick', p.toJson());
  Future<TabState?> beatDrag(TabClickParams p) => callTab('tab.beatDrag', p.toJson());
  Future<TabState?> noteClick(TabClickParams p) => callTab('tab.noteClick', p.toJson());
  Future<TabState?> select(TabSelectParams p) => callTab('tab.select', p.toJson());

  Future<TabState?> span(TabSpanAction action, {bool? keepAnchor}) =>
      callTab('tab.span', TabSpanParams(action: action, keepAnchor: keepAnchor).toJson());

  Future<TabState?> toggleMute(String track) =>
      callTab('tab.toggleMute', TabTrackParams(track: track).toJson());

  Future<TabState?> toggleSolo(String track) =>
      callTab('tab.toggleSolo', TabTrackParams(track: track).toJson());

  Future<TabState?> setListening(String track, {required bool on}) =>
      callTab('tab.setListening', TabListeningParams(track: track, on: on).toJson());

  Future<TabState?> setAllListening({required bool on}) =>
      callTab('tab.setAllListening', TabListeningParams(on: on).toJson());

  /// `tab.edit {op,...}`; con `op:"key"` el `handled` de la respuesta dice si el núcleo usó la tecla.
  Future<TabState?> edit(TabEditParams p) => callTab('tab.edit', p.toJson());

  /// `tab.edit {op:key}`: `true` si el núcleo usó la tecla (`TabState.handled`). Falla = `false`.
  Future<bool> key(String key, {bool shift = false, bool ctrl = false, bool alt = false}) async {
    final t = await edit(TabEditParams.key(key: key, shift: shift, ctrl: ctrl, alt: alt));
    return t?.handled ?? false;
  }

  /// `tab.edit {op:redo}` directo (Ctrl+Y en Windows).
  Future<TabState?> redo() => edit(TabEditParams.redo());

  Future<TabState?> setEditMode({required bool on}) => edit(TabEditParams.editMode(on: on));
}
