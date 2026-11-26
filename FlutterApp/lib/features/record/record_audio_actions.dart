/// Nivel de «Tu guitarra» (RV:127-128): máximo de `audio.levels` sobre los canales `guitarIn` (1-based).
double guitarInputLevel(List<int> guitarIn, List<double> levels) {
  double max = 0;
  for (final int ch in guitarIn) {
    if (ch >= 1 && ch - 1 < levels.length && levels[ch - 1] > max) max = levels[ch - 1];
  }
  return max;
}

/// M-6: pico (dBFS) máximo sobre los canales `guitarIn` (1-based); `-infinity` si no hay ninguno.
double guitarInputPeakDB(List<int> guitarIn, List<double> peakDB) {
  double max = double.negativeInfinity;
  for (final int ch in guitarIn) {
    if (ch >= 1 && ch - 1 < peakDB.length && peakDB[ch - 1] > max) max = peakDB[ch - 1];
  }
  return max;
}
