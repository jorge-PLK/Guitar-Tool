// P9.4: pantalla de la sonda (solo package:flutter/widgets.dart).
import 'package:flutter/widgets.dart';

import 'ctx.dart';

const screenBackground = Color(0xFF202428);
const topBarHeight = 44.0;
const _white = Color(0xFFFFFFFF);
const _textStyle = TextStyle(color: _white, fontSize: 13);

class UiState extends ChangeNotifier {
  final boundaryKey = GlobalKey();
  final focusNode = FocusNode(debugLabel: 'campo-flutter');
  final keyNode = FocusNode(debugLabel: 'reenvio-flutter');
  final fieldController = TextEditingController();
  bool showWeb = false;
  String? hidden; // null | none | offstage | zero | offscreen
  bool overlay = false;
  bool keys = false;
  Size frac = const Size(1, 1);
  Size avail = Size.zero;
  String status = 'iniciando';
  void Function(String action)? onFocusAction;
  KeyEventResult Function(KeyEvent e)? onKey;

  void changed() => notifyListeners();
}

class ProbeApp extends StatelessWidget {
  const ProbeApp(this.c, {super.key});
  final Ctx c;

  @override
  Widget build(BuildContext context) => WidgetsApp(
        color: screenBackground,
        debugShowCheckedModeBanner: false,
        textStyle: _textStyle,
        builder: (context, _) => Screen(c),
      );
}

class Screen extends StatelessWidget {
  const Screen(this.c, {super.key});
  final Ctx c;

  Widget _button(String label, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: const Color(0xFF3A4150),
          child: Text(label),
        ),
      );

  Widget _topBar() {
    final st = c.st;
    return Container(
      height: topBarHeight,
      color: const Color(0xFF2A2F37),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Text('${c.args.get('--case')} | ${st.status}'),
        const Spacer(),
        if (st.keys) ...[
          Focus(focusNode: st.keyNode, onKeyEvent: (_, e) => st.onKey?.call(e) ?? KeyEventResult.ignored, child: const SizedBox.shrink()),
          _button('Foco: WebView', () => st.onFocusAction?.call('webview')),
          _button('Foco: campo', () => st.onFocusAction?.call('field')),
          const SizedBox(width: 8),
          Container(
            width: 220,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(border: Border.all(color: _white)),
            child: EditableText(
              controller: st.fieldController,
              focusNode: st.focusNode,
              style: _textStyle,
              cursorColor: _white,
              backgroundCursorColor: const Color(0xFF888888),
            ),
          ),
        ],
      ]),
    );
  }

  Widget? _web(Size avail) {
    final st = c.st;
    final hidden = st.hidden;
    // 'none' = visible: cae en la rama por defecto (tamano completo segun frac).
    if (hidden != null || st.showWeb) {
      final w = c.web.widget();
      return switch (hidden) {
        'offstage' => Positioned(left: 0, top: 0, width: 100, height: 100, child: Offstage(child: w)),
        'zero' => Positioned(left: 0, top: 0, width: 0, height: 0, child: w),
        'offscreen' => Positioned(left: -3000, top: 0, width: 400, height: 300, child: w),
        _ => Positioned(
            left: 0,
            top: 0,
            width: avail.width * st.frac.width,
            height: avail.height * st.frac.height,
            child: w,
          ),
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        key: c.st.boundaryKey,
        child: ListenableBuilder(
          listenable: c.st,
          builder: (context, _) => Container(
            color: screenBackground,
            child: Column(children: [
              _topBar(),
              Expanded(
                child: LayoutBuilder(builder: (context, cons) {
                  c.st.avail = cons.biggest;
                  final web = _web(cons.biggest);
                  return Stack(children: [
                    ?web,
                    if (c.st.overlay)
                      Positioned(
                        left: 40,
                        top: 40,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          color: const Color(0xCCFF6600),
                          child: const Text('OVERLAY de Flutter sobre el WebView', style: TextStyle(color: _white, fontSize: 20)),
                        ),
                      ),
                  ]);
                }),
              ),
            ]),
          ),
        ),
      );
}
