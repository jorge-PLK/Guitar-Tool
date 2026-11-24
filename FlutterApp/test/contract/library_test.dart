import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart' show CoreError, Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) {
    fail('No encuentro Contract/fixtures subiendo desde el cwd');
  }
  return jsonDecode(await source.read('library/$name')) as Json;
}

void main() {
  group('contract library', () {
    group('resultados y eventos', () {
      test(
        'library.list.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.list.result.json');
          final result = LibraryListResult.fromJson(json);
          expect(result.projects, hasLength(7));
          expect(result.projects[2].separationState, SeparationState.queued);
          expect(result.projects[5].separationState, SeparationState.failed);
          expect(
            result.projects[5].separationError,
            'Fallo de memoria al separar.',
          );
          expect(result.skipped.single.folderName, 'Rota');
          expect(result.toJson(), equals(json));
        },
      );

      test('library.list.result: un tema sin artista omite la clave', () async {
        final json = await _fixture('library.list.result.json');
        final charlie = LibraryListResult.fromJson(json).projects[3];
        expect(charlie.artist, isNull);
        expect(charlie.toJson().containsKey('artist'), isFalse);
        expect(charlie.toJson().containsKey('separationError'), isTrue);
      });

      test(
        'library.reveal.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.reveal.result.json');
          expect(RevealResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.rename.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.rename.result.json');
          expect(RenameResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.trash.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.trash.result.json');
          expect(RemovedResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.delete.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.delete.result.json');
          expect(RemovedResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.separate.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.separate.result.json');
          expect(QueuedResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.usage.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.usage.result.json');
          final result = UsageResult.fromJson(json);
          expect(result.totalBytes, json['totalBytes']);
          expect(result.projects, hasLength(7));
          expect(result.toJson(), equals(json));
        },
      );

      test(
        'library.cleanupInfo.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.cleanupInfo.result.json');
          expect(CleanupInfoResult.fromJson(json).toJson(), equals(json));
        },
      );

      test('library.cleanupInfo.noId.result: decodifica y codifica sin perder campos', () async {
        final json = await _fixture('library.cleanupInfo.noId.result.json');
        expect(CleanupInfoResult.fromJson(json).toJson(), equals(json));
      });

      test(
        'library.cleanup.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.cleanup.result.json');
          expect(CleanupResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.artistPhoto.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.artistPhoto.result.json');
          expect(ArtistPhotoResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.artistPhoto.null.result: photo null sale explícito',
        () async {
          final json = await _fixture('library.artistPhoto.null.result.json');
          final result = ArtistPhotoResult.fromJson(json);
          expect(result.photo, isNull);
          expect(result.toJson(), equals(json));
          expect(result.toJson().containsKey('photo'), isTrue);
        },
      );

      test(
        'library.markBest.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.markBest.result.json');
          expect(MarkedResult.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.relocate.result: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.relocate.result.json');
          final result = RelocateResult.fromJson(json);
          expect(result.mediaRemapped, isTrue);
          expect(result.toJson(), equals(json));
        },
      );

      test(
        'library.relocated.event: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.relocated.event.json');
          expect(RelocateResult.fromJson(json).toJson(), equals(json));
        },
      );

      test('library.relocateProgress.event: decodifica y codifica sin perder campos', () async {
        final json = await _fixture('library.relocateProgress.event.json');
        expect(RelocateProgress.fromJson(json).fraction, 0.5);
        expect(RelocateProgress.fromJson(json).toJson(), equals(json));
      });

      test('library.changed.event: payload vacío', () async {
        final json = await _fixture('library.changed.event.json');
        expect(json, isEmpty);
      });

      test('errores: decodifican a CoreError con code y message', () async {
        final rename = CoreError.fromJson(
          await _fixture('library.rename.error.json'),
        );
        expect(rename.code, 'empty-title');
        final deleteTake = CoreError.fromJson(
          await _fixture('library.deleteTake.error.json'),
        );
        expect(deleteTake.code, 'not-found');
        final trash = CoreError.fromJson(
          await _fixture('library.trash.error.json'),
        );
        expect(trash.code, 'not-found');
        final relocate = CoreError.fromJson(
          await _fixture('library.relocate.error.json'),
        );
        expect(relocate.code, 'work-in-progress');
      });
    });

    group('params', () {
      test('library.list.params y library.usage.params: vacíos', () async {
        expect(await _fixture('library.list.params.json'), isEmpty);
        expect(await _fixture('library.usage.params.json'), isEmpty);
      });

      test(
        'library.project.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.project.params.json');
          expect(ProjectIDParams.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.reveal.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.reveal.params.json');
          expect(ProjectIDParams.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.trash.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.trash.params.json');
          expect(ProjectIDParams.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.delete.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.delete.params.json');
          expect(ProjectIDParams.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.separate.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.separate.params.json');
          expect(ProjectIDParams.fromJson(json).toJson(), equals(json));
        },
      );

      test(
        'library.rename.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.rename.params.json');
          expect(RenameParams.fromJson(json).toJson(), equals(json));
        },
      );

      test('library.rename.params sin artista: omite la clave', () {
        const params = RenameParams(id: 'x', title: 'y');
        expect(params.toJson(), equals({'id': 'x', 'title': 'y'}));
      });

      test(
        'library.cleanupInfo.params y library.cleanup.params: decodifican',
        () async {
          final info = await _fixture('library.cleanupInfo.params.json');
          expect(OptionalIDParams.fromJson(info).toJson(), equals(info));
          final cleanup = await _fixture('library.cleanup.params.json');
          expect(OptionalIDParams.fromJson(cleanup).toJson(), equals(cleanup));
        },
      );

      test('library.cleanupInfo.noId.params: id null sale explícito', () async {
        final json = await _fixture('library.cleanupInfo.noId.params.json');
        expect(OptionalIDParams.fromJson(json).id, isNull);
        expect(OptionalIDParams.fromJson(json).toJson(), equals(json));
      });

      test('library.artistPhoto.params y .null.params: decodifican', () async {
        final json = await _fixture('library.artistPhoto.params.json');
        expect(ArtistPhotoParams.fromJson(json).toJson(), equals(json));
        final nullCase = await _fixture('library.artistPhoto.null.params.json');
        expect(ArtistPhotoParams.fromJson(nullCase).toJson(), equals(nullCase));
      });

      test(
        'library.relocate.params: decodifica y codifica sin perder campos',
        () async {
          final json = await _fixture('library.relocate.params.json');
          final params = RelocateParams.fromJson(json);
          expect(params.mode, RelocateMode.move);
          expect(params.toJson(), equals(json));
        },
      );
    });

    test(
      'valores de enum no previstos caen en unknown; fechas ISO parsean',
      () {
        final project = ProjectSummary.fromJson(const {
          'id': 'x',
          'title': 't',
          'folderName': 'f',
          'duration': 1,
          'sampleRate': 44100,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
          'separationState': 'paused',
          'separationError': null,
          'stemCount': 0,
          'takeCount': 0,
          'rigCount': 0,
          'hasAnalysis': false,
          'guitars': <String>[],
        });
        expect(project.separationState, SeparationState.unknown);
        expect(project.createdAtDate, DateTime.utc(2026));
        expect(project.updatedAtDate, DateTime.utc(2026));
        expect(StemKind.fromRaw('theremin'), StemKind.unknown);
        expect(RelocateMode.fromRaw('copy'), RelocateMode.unknown);
      },
    );
  });
}
