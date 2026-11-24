import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regla 4 de docs/flutter/arquitectura.md: ningún color, fuente, radio ni
/// espaciado literal fuera de lib/theme/ (y lib/l10n/ es generado).
/// Excepción por línea: `// tf-literal-ok: <motivo>` al final de la línea.

final _exempt = RegExp(r'// tf-literal-ok: \S');

/// Reglas que se evalúan sobre la línea completa.
final _lineRules = <RegExp>[
  RegExp(r'\bColor\(0x'),
  RegExp(r'\bColor\.(?:fromARGB|fromRGBO)\('),
  RegExp(r'\bColors\.(?!transparent\b)[A-Za-z]'),
  RegExp(r'\bfontSize:'),
];

/// Llamadas que pueden llevar literales numéricos; se evalúan sobre la
/// llamada completa (puede abarcar varias líneas).
final _radiusCall = RegExp(r'\b(?:BorderRadius|Radius)\.circular\(');
final _radiusLiteralArg = RegExp(r'^\(\s*-?\d');
final _insetsCall = RegExp(r'\bEdgeInsets\.(?:all|symmetric|only|fromLTRB)\(');
final _insetsLiteralArg = RegExp(r'[(,:]\s*-?\d');

class ScanResult {
  ScanResult(this.violations, this.exemptions);

  final List<String> violations;
  final int exemptions;
}

/// Escanea las líneas de un fichero en memoria. Devuelve `ruta:línea: texto`.
ScanResult scanLines(String path, List<String> lines) {
  final violations = <String>[];
  var exemptions = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_exempt.hasMatch(line)) {
      exemptions++;
      continue;
    }
    if (line.trimLeft().startsWith('//')) continue;

    var bad = _lineRules.any((r) => r.hasMatch(line));
    for (final m in _radiusCall.allMatches(line)) {
      if (_radiusLiteralArg.hasMatch(_args(_callText(lines, i, m.start)))) {
        bad = true;
      }
    }
    for (final m in _insetsCall.allMatches(line)) {
      if (_insetsLiteralArg.hasMatch(_args(_callText(lines, i, m.start)))) {
        bad = true;
      }
    }
    if (bad) violations.add('$path:${i + 1}: ${line.trim()}');
  }
  return ScanResult(violations, exemptions);
}

/// Texto de la llamada que empieza en (row, col) hasta el paréntesis que la
/// cierra, uniendo hasta 15 líneas. Sin tener en cuenta cadenas.
String _callText(List<String> lines, int row, int col) {
  final buf = StringBuffer();
  var depth = 0;
  for (var j = row; j < lines.length && j < row + 15; j++) {
    final text = j == row ? lines[j].substring(col) : lines[j];
    for (final ch in text.split('')) {
      buf.write(ch);
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) return buf.toString();
      }
    }
    buf.write(' ');
  }
  return buf.toString();
}

/// Desde el primer paréntesis de la llamada, para mirar solo los argumentos.
String _args(String call) {
  final i = call.indexOf('(');
  return i < 0 ? '' : call.substring(i);
}

void main() {
  group('no_literals', () {
    test('lib/ sin literales fuera de theme/ y l10n/', () {
      final files =
          Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map((f) => f.path.replaceAll('\\', '/'))
              .where(
                (p) =>
                    !p.startsWith('lib/theme/') && !p.startsWith('lib/l10n/'),
              )
              .toList()
            ..sort();

      final violations = <String>[];
      var exemptions = 0;
      for (final p in files) {
        final r = scanLines(p, File(p).readAsLinesSync());
        violations.addAll(r.violations);
        exemptions += r.exemptions;
      }
      // ignore: avoid_print
      print(
        'no_literals: ${files.length} ficheros, $exemptions exenciones tf-literal-ok',
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    group('expresiones regulares', () {
      bool flags(String line) =>
          scanLines('mem.dart', [line]).violations.isNotEmpty;

      test('marca literales de color, fuente, radio y espaciado', () {
        const positives = [
          'final c = Color(0xFF0F1113);',
          'Color.fromARGB(255, 0, 0, 0)',
          'Color.fromRGBO(0, 0, 0, 1)',
          'color: Colors.red,',
          'style: TextStyle(fontSize: 12)',
          'style: TextStyle(fontSize: TfText.body)',
          'BorderRadius.circular(8)',
          'Radius.circular(4)',
          'EdgeInsets.all(8)',
          'EdgeInsets.symmetric(horizontal: 8)',
          'EdgeInsets.only(left: 4)',
          'EdgeInsets.fromLTRB(1, 2, 3, 4)',
          'final c = Color(0xFF000000); // tf-literal-ok:',
        ];
        for (final l in positives) {
          expect(flags(l), isTrue, reason: l);
        }
      });

      test('no marca tokens, EdgeInsets.zero, transparent ni comentarios', () {
        const negatives = [
          'color: Colors.transparent,',
          'padding: EdgeInsets.zero,',
          'padding: EdgeInsets.all(TfSpace.md)',
          'borderRadius: BorderRadius.circular(TfRadius.sm)',
          'Radius.circular(TfRadius.sm)',
          'EdgeInsets.symmetric(horizontal: TfSpace.md, vertical: TfSpace.sm)',
          'final x = myColor(0xFF)',
          'final s = fontSizeScale: 2',
          '// Color(0xFF000000)',
          '  /// fontSize: 12',
          '  // EdgeInsets.all(8)',
          'final c = Color(0xFF000000); // tf-literal-ok: marca de prueba',
          'final t = Colors.grey; // tf-literal-ok: prueba',
        ];
        for (final l in negatives) {
          expect(flags(l), isFalse, reason: l);
        }
      });

      test('detecta literales en llamadas de varias líneas', () {
        final bad = scanLines('mem.dart', [
          'padding: EdgeInsets.symmetric(',
          '  horizontal: TfSpace.md,',
          '  vertical: 4,',
          ')',
        ]);
        expect(bad.violations, ['mem.dart:1: padding: EdgeInsets.symmetric(']);

        final ok = scanLines('mem.dart', [
          'padding: EdgeInsets.symmetric(',
          '  horizontal: TfSpace.md,',
          '  vertical: TfSpace.sm,',
          ')',
        ]);
        expect(ok.violations, isEmpty);
      });

      test('cuenta exenciones y numera líneas desde 1', () {
        final r = scanLines('mem.dart', [
          'final a = Colors.red;',
          'final b = Color(0xFF) // tf-literal-ok: prueba',
          'final c = Colors.blue;',
        ]);
        expect(r.exemptions, 1);
        expect(r.violations, [
          'mem.dart:1: final a = Colors.red;',
          'mem.dart:3: final c = Colors.blue;',
        ]);
      });
    });
  });
}
