/// Nivel de «Tu guitarra» (RV:127-128): máximo de `audio.levels` sobre los canales `guitarIn` (1-based).
double guitarInputLevel(List<int> guitarIn, List<double> levels) {
  double max = 0;
  for (final int ch in guitarIn) {
    if (ch >= 1 && ch - 1 < levels.length && levels[ch - 1] > max) max = levels[ch - 1];
  }
  return max;
}
