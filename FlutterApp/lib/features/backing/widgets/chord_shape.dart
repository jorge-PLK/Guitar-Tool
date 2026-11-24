/// Cejilla de una forma de acorde: traste y cuerdas extremas (0 = 6.ª cuerda, 5 = 1.ª, en cualquier orden).
class ChordBarre {
  const ChordBarre({required this.fret, required this.from, required this.to});

  final int fret;
  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is ChordBarre && other.fret == fret && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(fret, from, to);
}

/// Modelo de vista de la forma de un acorde (la entregará el núcleo).
/// [frets]: 6 entradas de la cuerda grave a la aguda; `null` = no se toca, 0 = al aire.
class ChordShape {
  const ChordShape({required this.frets, this.baseFret = 1, this.barre});

  /// Siempre 6 entradas.
  final List<int?> frets;
  final int baseFret;
  final ChordBarre? barre;

  @override
  bool operator ==(Object other) =>
      other is ChordShape &&
      other.baseFret == baseFret &&
      other.barre == barre &&
      _listEq(other.frets, frets);

  @override
  int get hashCode => Object.hash(baseFret, barre, Object.hashAll(frets));

  static bool _listEq(List<int?> a, List<int?> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
