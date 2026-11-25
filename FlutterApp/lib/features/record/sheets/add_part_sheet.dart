import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contract/record_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/tf_buttons.dart';
import '../../../widgets/tf_dropdown.dart';
import '../../../widgets/tf_sheet.dart';
import '../../../widgets/tf_text_field.dart';
import '../record_store.dart';

/// «Añadir parte» (RV:332-356): nombre y guitarra que sustituye. Intro no hace nada; Esc cierra.
Future<void> showAddPartSheet(BuildContext context) =>
    showTfSheet<void>(context: context, builder: (BuildContext ctx) => const AddPartSheet());

class AddPartSheet extends ConsumerStatefulWidget {
  const AddPartSheet({super.key});

  @override
  ConsumerState<AddPartSheet> createState() => _AddPartSheetState();
}

class _AddPartSheetState extends ConsumerState<AddPartSheet> {
  final TextEditingController _name = TextEditingController();
  String? _replaces;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _add() {
    unawaited(ref.read(recordStoreProvider.notifier).addPart(_name.text.trim(), replaces: _replaces));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<RecordGuitarRole> roles = ref.watch(recordStoreProvider.select((s) => s.snapshot?.guitarRoles)) ?? const <RecordGuitarRole>[];
    return TfSheetScaffold(
      width: TfSize.sheetWidthNarrow,
      title: l.record_addPartTitle,
      titleSize: 20,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: TfSpace.s14,
        children: <Widget>[
          TfTextField(key: const ValueKey<String>('addpart-name'), controller: _name, hint: l.record_addPartName),
          Text(l.record_addPartReplaces, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
          TfDropdown<String?>(
            key: const ValueKey<String>('addpart-replaces'),
            value: _replaces,
            items: <TfDropdownItem<String?>>[
              TfDropdownItem<String?>(value: null, label: l.record_addPartNone),
              for (final RecordGuitarRole r in roles) TfDropdownItem<String?>(value: r.role, label: r.name),
            ],
            onChanged: (String? v) => setState(() => _replaces = v),
          ),
        ],
      ),
      actions: <Widget>[
        TfSecondaryButton(label: l.record_cancel, onPressed: () => Navigator.of(context).maybePop()),
        TfPrimaryButton(key: const ValueKey<String>('addpart-add'), label: l.record_addPartAdd, onPressed: _valid ? _add : null),
      ],
    );
  }
}
