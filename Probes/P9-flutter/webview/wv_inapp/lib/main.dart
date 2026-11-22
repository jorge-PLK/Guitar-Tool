// P9.7e: humo de compilacion de flutter_inappwebview. Sin Material. Uso: wv_inapp.exe [--exit-after <s>]
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main(List<String> args) {
  final i = args.indexOf('--exit-after');
  if (i >= 0 && i + 1 < args.length) {
    final s = int.tryParse(args[i + 1]) ?? 5;
    Timer(Duration(seconds: s), () => exit(0));
  }
  runApp(const _Probe());
}

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(data: '<h1>ok</h1>'),
        ),
      );
}
