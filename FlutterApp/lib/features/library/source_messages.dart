import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';

/// Título y detalle de un error de fuente (`SourceError`, LinkImportSheet.swift:405-437).
/// Provisional: lo rellena la parte E1b (claves `library_src*`).
({String title, String detail}) sourceErrorTexts(AppLocalizations l, LinkImportError error) =>
    (title: error.message, detail: '');
