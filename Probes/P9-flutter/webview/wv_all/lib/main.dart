// P9.7e: humo de compilacion de webview_all. Sin Material. Uso: wv_all.exe [--exit-after <s>]
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_all/webview_all.dart';

void main(List<String> args) {
  final i = args.indexOf('--exit-after');
  if (i >= 0 && i + 1 < args.length) {
    final s = int.tryParse(args[i + 1]) ?? 5;
    Timer(Duration(seconds: s), () => exit(0));
  }
  runApp(const _Probe());
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final WebViewController _c = WebViewController()
    ..loadHtmlString('<h1>ok</h1>');

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: WebViewWidget(controller: _c),
      );
}
