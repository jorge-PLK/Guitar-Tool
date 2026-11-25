import 'package:toneforge/theme/fmt.dart';

/// Duración «m:ss» o «—» (`duration`, PI:253).
String playlistDuration(double? seconds) => seconds == null ? '—' : TfFmt.duration(seconds);
