import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

const _sample = 'Wxilmg 0123 Afinador';

String? _opt(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProbeApp(args: args));
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key, required this.args});
  final List<String> args;

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  @override
  void initState() {
    super.initState();
    final exitAfter = double.tryParse(_opt(widget.args, '--exit-after') ?? '');
    if (exitAfter != null) {
      Future<void>.delayed(
        Duration(milliseconds: (exitAfter * 1000).round()),
        () => exit(0),
      );
    }
    // Estado de foco en el momento del primer fotograma.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final focused =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      final lifecycle = WidgetsBinding.instance.lifecycleState?.name;
      final path = _opt(widget.args, '--report');
      if (path == null) return;
      final report = {
        'args': widget.args,
        'screen': _opt(widget.args, '--screen'),
        'fonts': {
          'inter': await _fontLoads('Inter', 'assets/fonts/inter-latin-400.ttf'),
          'spaceGrotesk': await _fontLoads(
            'Space Grotesk',
            'assets/fonts/space-grotesk-latin-500.ttf',
          ),
        },
        'dartVersion': Platform.version,
        'focusedAtStart': focused,
        'lifecycleAtStart': lifecycle,
      };
      await File(path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
    });
  }

  double _width(String? family) {
    final p = TextPainter(
      text: TextSpan(
        text: _sample,
        style: TextStyle(fontFamily: family, fontSize: 24),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return p.width;
  }

  Future<bool> _fontLoads(String family, String asset) async {
    try {
      await rootBundle.load(asset);
    } catch (_) {
      return false;
    }
    return _width(family) != _width('TfNoSuchFamily');
  }

  @override
  Widget build(BuildContext context) {
    const light = TextStyle(color: Color(0xFFFFFFFF), fontSize: 16);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF14161A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefaultTextStyle(
            style: light,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('args: ${widget.args}'),
                Text('screen: ${_opt(widget.args, '--screen')}'),
                const SizedBox(height: 16),
                const Text(
                  _sample,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 24),
                ),
                const Text(
                  _sample,
                  style: TextStyle(fontFamily: 'Space Grotesk', fontSize: 24),
                ),
                const SizedBox(height: 16),
                Text('Dart: ${Platform.version}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
