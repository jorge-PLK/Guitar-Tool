part of 'tab.dart';

/// Cuándo vale una regla del mapa de teclas de edición (`tab.keyMap`).
enum TabKeyWhen with TabWire {
  span('span'),
  edit('edit'),
  editDrums('editDrums'),
  editNotDrums('editNotDrums'),
  unknown('unknown');

  const TabKeyWhen(this.wire);
  @override
  final String wire;
}

/// Regla: `key` exacta (sensible a mayúsculas); `shift == null` = da igual.
final class TabKeyRule {
  const TabKeyRule({
    required this.key,
    required this.shift,
    required this.ctrl,
    required this.alt,
    required this.when,
  });

  factory TabKeyRule.fromJson(Json j) => TabKeyRule(
        key: _s(j['key']),
        shift: _bn(j['shift']),
        ctrl: _b(j['ctrl']),
        alt: _b(j['alt']),
        when: _enumOr(TabKeyWhen.values, j['when'], TabKeyWhen.unknown),
      );

  final String key;
  final bool? shift;
  final bool ctrl;
  final bool alt;
  final TabKeyWhen when;
}

/// Respuesta de `tab.keyMap {}`: estática, se pide una vez.
final class TabKeyMapResult {
  const TabKeyMapResult({required this.rules});

  factory TabKeyMapResult.fromJson(Json j) =>
      TabKeyMapResult(rules: _items(j['rules'], TabKeyRule.fromJson));

  final List<TabKeyRule> rules;
}
