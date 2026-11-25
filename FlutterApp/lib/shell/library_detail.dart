import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Proyecto con la página de detalle abierta en la Biblioteca (RootView `detail`); null = lista.
/// La abre la tarjeta «tema seleccionado» de la barra lateral; la cierran «‹ Biblioteca» y la fila
/// «Biblioteca» de la barra (RV:58).
final libraryDetailProvider = NotifierProvider<LibraryDetailNotifier, String?>(LibraryDetailNotifier.new);

class LibraryDetailNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String projectId) => state = projectId;

  void close() => state = null;
}
