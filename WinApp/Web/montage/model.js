// Constantes y formatos de Montaje (App/Sources/MontageView.swift, MontageFramingSheet.swift, Theme.swift `Fmt`).

/// Layouts, en el orden y con los textos del Mac (LayoutColumn.layouts).
export const LAYOUTS = [
  { kind: 'side', name: 'Lado a lado', desc: 'Landscape · 1920 × 1080' },
  { kind: 'grid', name: 'Rejilla', desc: 'Landscape · 3 o 4 tomas' },
  { kind: 'stack', name: 'Apilado', desc: 'Portrait · 1080 × 1920' },
  { kind: 'single', name: 'Plano único', desc: 'Portrait · rítmica y solista' },
  { kind: 'single-landscape', name: 'Plano único', desc: 'Landscape · rítmica y solista' },
];

/// Valores informativos de la mini-spec Fase 7, «Transiciones» (no se editan). El Mac los pone fijos en SettingsColumn.
export const TRANSITIONS = [
  ['Recolocación', 'Muelle · 0,5 s'],
  ['Entrada', 'Escala 92→100 % + nitidez'],
  ['Anticipación al solo', null],       // `snap.anticipationLabel`
  ['Fundido de audio', '80 ms'],
  ['Fundido de entrada y salida', '1 compás'],
  ['Esquinas', 'Redondeadas + sombra'],
];

/// Mac (MontageBody): por debajo de este ancho de contenido las columnas laterales ceden sitio a la vista previa.
export const COMPACT_WIDTH = 900;
/// Colores de los carriles y de la solista (MontageTimelineView.laneColors / soloColor).
export const LANE_COLORS = ['#5BC0EB', '#F2A33A', '#6FD99E', '#C97F9E', '#5DB5B5'];
export const SOLO_COLOR = '#B79CFF';
/// Margen del eje a cada lado del tramo del vídeo (fracción del tramo, mínimo un compás).
export const AXIS_MARGIN_FRACTION = 0.10;
/// Mac (MontageFramingSheet): lado de la zona de la esquina que escala la caja (px), lado mínimo, rangos.
export const HANDLE_RADIUS = 16;
export const MIN_BOX_SIDE = 0.05;
export const ZOOM_RANGE = [0.5, 3.0];
export const OFFSET_RANGE = [-0.5, 0.5];
/// Mac (`.task(id: time)` de la hoja): espera antes de pedir el fotograma al mover el deslizador.
export const FRAME_DEBOUNCE_MS = 80;

export const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
/// Fmt.duration del Mac: redondea al segundo.
export const fmtDur = s => { const t = Math.round(Math.max(s || 0, 0)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
export const fmtPercent = f => `${Math.round((f || 0) * 100)} %`;
/// Número con una decimal y coma (es).
export const num1 = x => (Math.round(x * 10) / 10).toFixed(1).replace('.', ',').replace('-', '−');
export const resLabel = r => (r.height === 720 && r.width === 1280 ? '720p' : r.height === 1080 && r.width === 1920 ? '1080p'
  : r.height === 2160 && r.width === 3840 ? '4K' : `${r.width}×${r.height}`);
export const fpsLabel = f => `${String(Math.round(f * 100) / 100).replace('.', ',')} fps`;
export const FPS_CHOICES = [24, 25, 30, 50, 60];

/// Nombre de la sección en el instante `t` (MontageController.sectionName).
export function sectionName(snap, t) {
  const s = (snap?.sections ?? []).find(x => t >= x.start && t < x.end);
  return s ? s.name : null;
}

export function laneColor(lane, index) {
  return lane.isSolo ? SOLO_COLOR : LANE_COLORS[index % LANE_COLORS.length];
}
