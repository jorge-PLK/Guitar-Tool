import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';

/// Vocabulario de acordes del núcleo (raíces, calidades, índice de «N»); se pide una vez.
final FutureProvider<StudyChordVocabulary?> chordVocabularyProvider = FutureProvider<StudyChordVocabulary?>(
  (Ref ref) => ref.read(studyStoreProvider.notifier).chordVocabulary(),
);
