import 'package:flutter/painting.dart';

/// Tokens de diseño transcritos de App/Sources/Theme.swift y de docs/flutter/tokens-componentes.md.
/// Valores literales: no se redondean ni se funden casi iguales (decisión de Jorge, 24/11).

/// Colores. Hex de Theme.swift (TF.*) y de tokens-componentes.md §2.1.
abstract final class TfColors {
  // §1.1 TF.*
  static const Color bg = Color(0xFF0F1113);
  static const Color sidebar = Color(0xFF15181B);
  static const Color card = Color(0xFF171A1D);
  static const Color field = Color(0xFF1C2024);
  static const Color line = Color(0xFF252A2F);
  static const Color fieldLine = Color(0xFF2A3036);
  static const Color text = Color(0xFFE8EAED);
  static const Color text2 = Color(0xFFC9CED4);
  static const Color muted = Color(0xFF9AA3AD);
  static const Color accent = Color(0xFFF2A33A);
  static const Color accentBg = Color(0xFF2A2116);
  static const Color accentInk = Color(0xFF1A1206);
  static const Color ok = Color(0xFF6FD99E);
  static const Color okBg = Color(0xFF16301F);
  static const Color neutralBg = Color(0xFF1F242A);
  static const Color danger = Color(0xFFF07178);
  static const Color dangerBg = Color(0xFF331A1C);

  // Controles nativos de macOS medidos con cuentagotas sobre la captura de referencia (ventana inactiva).
  static const Color nativeControl = Color(0xFF45474A);
  static const Color nativeSegmentBg = Color(0xFF2D2E30);
  static const Color nativeSegmentText = Color(0xFFC5C5C5);
  static const Color nativeFieldBg = Color(0xFF171717);
  static const Color nativeFieldLine = Color(0xFF26282A);
  static const Color nativeStepperBg = Color(0xFF2D2E30);
  static const Color nativeStepperLine = Color(0xFF494A4C);

  // §1.1 TF.sectionPalette, en el orden de SectionEditor.paletteCount.
  static const Color sectionBlue = Color(0xFF6C9BD2);
  static const Color sectionGreen = Color(0xFF6FB58A);
  static const Color sectionViolet = Color(0xFF9C86C9);
  static const Color sectionRose = Color(0xFFC97F9E);
  static const Color sectionTurquoise = Color(0xFF5DB5B5);
  static const Color sectionLime = Color(0xFFA6B85C);
  static const Color sectionCoral = Color(0xFFC8706A);
  static const List<Color> sectionPalette = [
    sectionBlue,
    sectionGreen,
    sectionViolet,
    sectionRose,
    sectionTurquoise,
    sectionLime,
    sectionCoral,
  ];

  // §2.1 literales de las vistas.
  static const Color recordButton = Color(0xFFC8433A);
  static const Color recordLive = Color(0xFFE5534B);
  static const Color okBorder = Color(0xFF2F6B45);
  static const Color previewDeep = Color(0xFF121417);
  static const Color videoBg = Color(0xFF0B0C0E);
  static const Color tileGrey = Color(0xFF5A636C);
  static const Color timelineBlue = Color(0xFF5BC0EB);
  static const Color soloViolet = Color(0xFFB79CFF);
  static const Color deviceOk = Color(0xFF4CC38A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  /// Carriles de montaje: timelineBlue, accent, ok, sectionRose, sectionTurquoise.
  static const List<Color> laneColors = [
    timelineBlue,
    accent,
    ok,
    sectionRose,
    sectionTurquoise,
  ];

  /// Barras de color de prueba (VideoSettingsView.swift:388), sistema en modo oscuro de macOS.
  /// Confirmar con captura de referencia: los sRGB son aproximaciones de systemYellow, systemCyan,
  /// systemGreen, systemPink, systemRed y systemBlue en oscuro.
  static const List<Color> colorBars = [
    Color(0xFFFFFFFF), // white
    Color(0xFFFFD60A), // yellow (systemYellow oscuro) // confirmar con captura de referencia
    Color(0xFF64D2FF), // cyan (systemCyan oscuro) // confirmar con captura de referencia
    Color(0xFF30D158), // green (systemGreen oscuro) // confirmar con captura de referencia
    Color(0xFFFF375F), // pink (systemPink oscuro) // confirmar con captura de referencia
    Color(0xFFFF453A), // red (systemRed oscuro) // confirmar con captura de referencia
    Color(0xFF0A84FF), // blue (systemBlue oscuro) // confirmar con captura de referencia
    Color(0xFF000000), // black
  ];
}

/// Radios de esquina (cornerRadius), valor literal de SwiftUI.
abstract final class TfRadius {
  static const double control = 10;
  static const double field = 8;
  static const double tile = 12;
  static const double small = 6;
  static const double xs = 4;
  static const double card = 14;
  static const double r3 = 3;
  static const double r2 = 2;
  static const double hero = 16;
  static const double r9 = 9;
  static const double r7 = 7;

  /// Controles nativos de macOS (desplegable, segmentado, stepper) medidos en la captura.
  static const double native = 5;

  /// Capsule() de SwiftUI: radio = alto/2. Valor grande que se clampa a alto/2 en Flutter.
  static const double pill = 999;
}

/// Espaciado y padding (escala mínima de §2.7).
abstract final class TfSpace {
  static const double s1 = 1;
  static const double s2 = 2;
  static const double s3 = 3;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s36 = 36;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;
}

/// Grosores de trazo (§2.3).
abstract final class TfStroke {
  static const double hairline = 1;
  static const double thick = 2;

  /// Trazo discontinuo `dash: [3]` (TabScreen.swift:238): 3 pt de trazo y 3 de hueco.
  static const double dash = 3;

  /// Marco de edición de acordes (BackingTrackView.swift:172).
  static const double editFrame = 1.5;
}

/// Opacidades literales de SwiftUI (§2.4). Sin fundir valores casi iguales.
abstract final class TfOpacity {
  static const double disabled = 0.6;
  static const double borderAccent = 0.6;
  static const double half = 0.5;
  static const double dim = 0.4;
  static const double muted = 0.55;
  static const double pressedSecondary = 0.7;
  static const double pressedPrimary = 0.8;
  static const double bars = 0.85;
  static const double scrim75 = 0.75;
  static const double disabledSoft = 0.45;
  static const double whiteSoft = 0.9;
  static const double tint35 = 0.35;
  static const double tint30 = 0.30;
  static const double tint28 = 0.28;
  static const double tint22 = 0.22;
  static const double tint20 = 0.20;
  static const double tint18 = 0.18;
  static const double tint16 = 0.16;
  static const double tint12 = 0.12;
  static const double tint07 = 0.07;

  /// `muted@0.7` (BackingTrackView.swift:268). Mismo valor que [pressedSecondary], otro uso.
  static const double mutedChip = 0.7;
}

/// Sombras (§2.5), todas negras. SwiftUI `radius` se transcribe como `blurRadius`.
abstract final class TfShadow {
  /// @0.6, r10, y4: cuenta atrás.
  static const BoxShadow countdown = BoxShadow(
    color: Color(0x99000000), // 0.6
    blurRadius: 10,
    offset: Offset(0, 4),
  );

  /// @0.4, r2, y1: cabezal de la línea de tiempo.
  static const BoxShadow playhead = BoxShadow(
    color: Color(0x66000000), // 0.4
    blurRadius: 2,
    offset: Offset(0, 1),
  );

  /// @0.5, r3, y2: pomo del fader.
  static const BoxShadow knob = BoxShadow(
    color: Color(0x80000000), // 0.5 redondeado a 0x80 (0.502)
    blurRadius: 3,
    offset: Offset(0, 2),
  );

  /// @0.5, r2, y0: caja de sección.
  static const BoxShadow sectionBox = BoxShadow(
    color: Color(0x80000000), // 0.5 redondeado a 0x80 (0.502)
    blurRadius: 2,
    offset: Offset.zero,
  );
}

/// Tamaños fijos de control (§2.8). Ancho de barra lateral: de tokens.css de la web (240).
abstract final class TfSize {
  static const double controlLg = 44;
  static const double controlMd = 36;
  static const double controlSm = 28;
  static const double sidebarWidth = 240;

  // K5: barra lateral, filas y avisos.
  static const double navIcon = 18; // RootView.swift:108, VideoSettingsView.swift:312
  static const double noticeIcon = 16; // sin medida en SwiftUI: confirmar con captura de referencia
  static const double noticeClose = 12; // sin medida en SwiftUI: confirmar con captura de referencia
  static const double statusDot = 8; // RootView.swift:95
  static const double marqueeSpeed = 30; // px/s, MarqueeText.swift:10
  static const double trackingTableHeader = 0.7; // LibraryView.swift:156-159

  // K1 (botones, chip, barras, spinner, carátula).
  static const double font12 = 12;
  static const double font13 = 13;
  static const double font14 = 14;
  // Escala de letra completa (Jorge, 25/11/2026): ningún tamaño numérico fuera de theme/.
  static const double font15 = 15;
  static const double font16 = 16;
  static const double font18 = 18;
  static const double font22 = 22;
  static const double font26 = 26;
  static const double font30 = 30;
  static const double font32 = 32;
  static const double iconButtonIcon = 14;
  static const double nudgeWidth = 30;
  static const double nudgeHeight = 24;
  static const double nudgeIcon = 11;
  static const double accentBarHeight = 6;
  static const double progressHeight = 4;
  static const double spinnerSmall = 16;
  static const double spinnerMini = 10;
  static const double coverSide = 44;
  static const double coverIcon = 18;
  static const double coverThumbPixels = 88;
  static const double dividerVerticalHeight = 28;

  // K4 (capas): medidas propias del kit, sin origen literal en SwiftUI (menú/alerta/barra dibujados en Flutter).
  static const double menuMinWidth = 180;
  static const double alertWidth = 320;
  static const double tooltipMaxWidth = 280;

  // K2: controles nativos redibujados (§3.2). Los marcados "confirmar" no están medidos.
  static const double linkFieldHeight = 32;
  static const double searchFieldWidth = 240;
  static const double numberFieldHeight = 24;
  static const double numberFieldWidth = 70;
  static const double dropdownHeight = 22;
  static const double dropdownPadH = 11;
  static const double dropdownGap = 8;
  static const double segmentedHeight = 24;
  static const double segmentedPadH = 12;
  static const double segmentedInset = 1;
  static const double switchWidth = 38;
  static const double switchHeight = 22;
  static const double switchSmallWidth = 32;
  static const double switchSmallHeight = 18;
  static const double checkboxBox = 16;
  static const double checkboxMark = 12;
  static const double sliderTrack = 4; // confirmar con captura de referencia
  static const double sliderKnob = 16;
  static const double sliderHit = 20;
  static const double sliderWidth = 120;
  static const double stepperWidth = 18;
  static const double stepperHeight = 24;
  static const double stepperIcon = 8;
  static const double fieldIcon = 14;
  static const double dropdownChevron = 9;
  static const double dropdownMenuItem = 28;
  static const double dropdownMenuMaxHeight = 280;
  static const double focusHalo = 3;

  // K3: pastilla de pista, fader, medidores y canal de mezclador (BackingMixer.swift, TabScreen.swift).
  static const double font11 = 11;
  static const double pillHeight = 34;
  static const double faderWidth = 28;
  static const double faderTrackWidth = 6;
  static const double faderKnobHeight = 18;
  static const double faderBaseHeight = 150;
  static const double faderMinHeight = 40;
  static const double levelBarWidth = 8;
  static const double inputMeterWidth = 8;
  static const double inputMeterHeight = 28;
  static const double mixerChannelWidth = 96;
  static const double mixerChannelHeight = 276;
  static const double mixerChannelMinHeight = 166;
  static const double mixerTitleHeight = 22;
  static const double mixerTogglesHeight = 40;

  // Backing y Tab: transporte, información y escenario (BackingView/TabScreen).
  static const double transportPlay = 52; // botón de play redondo, Backing y Tab
  static const double transportPlayIcon = 20;
  static const double transportRewindIcon = 15;
  static const double transportMarkHeight = 30; // «Inicio»/«Fin» de bucle
  static const double transportTempoSlider = 120;
  static const double transportTempoValue = 54;
  static const double transportFlowSpacing = 14;
  static const double infoPickerWidth = 112;
  static const double infoFineSliderWidth = 70;
  static const double infoCentsWidth = 56;
  static const double tabStageMinHeight = 320; // alto mínimo del escenario
  static const double tabFooterHeight = 18;
  static const double tabListenOptionHeight = 30;
  static const double tabTuningWidth = 170;
  static const double tabNameWidth = 150; // nombre de pista (pairing y fases)
  static const double tabPhaseBarWidth = 220;
  // Ola 3 · Grabar y Ajustes
  static const double settingsCameraWidth = 280; // VS:244-284
  static const double settingsResFpsWidth = 160; // VS:244-284
  static const double settingsPreviewWidth = 240; // VS:244-284
  static const double previewAspect = 16 / 9; // RV:386, VS:286-321
  static const double exportCodecWidth = 160; // VS:354-383
  static const double exportResolutionWidth = 100; // VS:354-383
  static const double sheetWidthWide = 720; // TV:282, OS
  static const double sheetWidthNarrow = 420; // RV:332-356
  static const double viewerCloseIcon = 13; // TV: botón cerrar
  static const double viewerPlayIcon = 15; // TV: icono de reproducción
  static const double offsetButtonHeight = 34; // OS
  static const double offsetFieldWidth = 76; // OS
  static const double compactMeterWidth = 22; // RM:78-85
  static const double compactMeterHeight = 8; // RM:78-85
  static const double recordButtonPaddingH = 22; // RV:482
  static const double recDot = 10; // RV:433
  static const double previewGradientRadius = 520; // RV:367
  static const double previewPlaceholderIcon = 28; // RV:411
  static const double inputLevelBarWidth = 12; // RM:198-207
  static const double mixerDividerHeight = 200; // RM:47
  static const double compactMasterWidth = 40; // RM:71
  static const double compactChannelWidth = 76; // RM:123
  static const double foldButtonHeight = 30; // RM:29-33

  // Ola 2 · Backing: acordes, marcos de sección y popover de sección.
  static const double chordChipHeight = 30;
  static const double chordQualityCellWidth = 60;
  static const double control32 = 32;
  static const double sectionEdgeGrab = 16;
  static const double sectionEdgeBarWidth = 6;
  static const double sectionEdgeBarMin = 16;
  static const double sectionEdgeBarMax = 30;
  static const double sectionEdgeBarInset = 10;
  static const double sectionPopoverWidth = 300;
  static const double sectionPopoverLabelWidth = 46;
  static const double sectionColorDot = 20;
  static const double sectionSuggestionHeight = 24;
  static const double sectionTimeMinWidth = 64;

  // Ola 2 · M3: medidas locales de Songsterr (features/tab) y de Backing (info y popover de sección).
  static const double songsterrWorkingBarWidth = 260; // TSS:179-189
  static const double songsterrPairingRowHeight = 44; // TSS:298
  static const double songsterrSlotDropdownWidth = 260; // TSS:298-319
  static const double songsterrSoloDropdownWidth = 200; // TSS:270-294
  static const double songsterrSoloLabelWidth = 90; // TSS:270-294; la ficha no da medida
  static const double songsterrWarningsMaxHeight = 140; // TSS:205-248
  static const double songsterrListWidth = 612;
  static const double songsterrSheetHeight = 640;
  static const double songsterrSheetMaxWidth = 1320;
  static const double songsterrChoosingColumnWidth = 190; // TSS:63-90, columna de pista
  static const double songsterrChoosingNarrowWidth = 170; // TSS:63-90, columna de instrumento
  static const double sectionSwatchRowHeight = 24;
  static const double sectionSwatchRingGap = 3;
  static const double backingInfoChevron = 10;
  static const double backingInfoFlowSpacing = 10;
  static const double backingInfoRunSpacing = 10;

  // Ola 3 · tamaños de letra
  static const double font10 = 10;
  static const double font20 = 20;
}
