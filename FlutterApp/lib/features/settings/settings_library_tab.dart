import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';

import 'widgets/language_group.dart';
import 'widgets/library_folder_group.dart';
import 'widgets/models_group.dart';
import 'widgets/tools_group.dart';

/// Pestaña Biblioteca de Ajustes (SettingsView.swift:83-193): carpeta, modelos, fuentes externas e idioma.
class SettingsLibraryTab extends StatelessWidget {
  const SettingsLibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      spacing: TfSpace.s20,
      children: <Widget>[
        LibraryFolderGroup(),
        ModelsGroup(),
        ToolsGroup(),
        LanguageGroup(),
      ],
    );
  }
}
