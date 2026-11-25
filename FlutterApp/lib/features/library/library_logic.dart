import 'package:toneforge/contract/library.dart';

/// Vista de la lista (se persiste su valor crudo).
enum LibraryGrouping {
  songs('songs'),
  artists('artists');

  const LibraryGrouping(this.raw);
  final String raw;

  static LibraryGrouping fromRaw(String? raw) => values.firstWhere(
    (v) => v.raw == raw,
    orElse: () => LibraryGrouping.songs,
  );
}

const _from = 'áàäâãåāéèëêēíìïîīóòöôõōúùüûūñçýÿ';
const _to = 'aaaaaaaeeeeeiiiiiooooouuuuunncyy';

/// Minúsculas y sin tildes (`LibraryFilter.fold`); la «ñ» se pliega a «n».
String foldText(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final r in lower.runes) {
    final c = String.fromCharCode(r);
    final i = _from.indexOf(c);
    b.write(i < 0 ? c : _to[i]);
  }
  return b.toString();
}

/// Temas ordenados por título plegado (estable por título original).
List<ProjectSummary> sortByTitle(Iterable<ProjectSummary> entries) {
  final list = entries.toList();
  list.sort((a, b) {
    final c = foldText(a.title).compareTo(foldText(b.title));
    return c != 0 ? c : a.title.compareTo(b.title);
  });
  return list;
}

/// Filtra por [query] (recortada, sin mayúsculas ni tildes) en título y artista.
List<ProjectSummary> filterEntries(Iterable<ProjectSummary> entries, String query) {
  final q = foldText(query.trim());
  if (q.isEmpty) return entries.toList();
  return [
    for (final e in entries)
      if (foldText(e.title).contains(q) || foldText(e.artist ?? '').contains(q)) e,
  ];
}

/// Artista con sus temas. [name] vacío = «Sin artista».
class ArtistGroup {
  const ArtistGroup({required this.name, required this.tracks});

  final String name;
  final List<ProjectSummary> tracks;

  bool get isUnknown => name.isEmpty;
}

/// Agrupa por artista (clave plegada): artistas por nombre plegado, «Sin artista» al final y temas por título.
List<ArtistGroup> groupByArtist(Iterable<ProjectSummary> entries) {
  final byKey = <String, List<ProjectSummary>>{};
  final names = <String, String>{};
  for (final e in sortByTitle(entries)) {
    final name = (e.artist ?? '').trim();
    final key = foldText(name);
    byKey.putIfAbsent(key, () => []).add(e);
    names.putIfAbsent(key, () => name);
  }
  final keys = byKey.keys.where((k) => k.isNotEmpty).toList()..sort();
  return [
    for (final k in keys) ArtistGroup(name: names[k]!, tracks: byKey[k]!),
    if (byKey.containsKey('')) ArtistGroup(name: '', tracks: byKey['']!),
  ];
}
