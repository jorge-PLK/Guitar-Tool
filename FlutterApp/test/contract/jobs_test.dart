import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/jobs.dart';
import 'package:toneforge/core/core_client.dart' show Json;
import 'package:toneforge/core/mock_core.dart';

Future<Json> _fixture(String name) async {
  final source = await DirectoryFixtureSource.find();
  if (source == null) fail('No encuentro Contract/fixtures subiendo desde el cwd');
  return jsonDecode(await source.read('jobs/$name')) as Json;
}

void main() {
  test('import.file.params: decodifica y codifica sin perder campos', () async {
    final json = await _fixture('import.file.params.json');
    expect(ImportFileParams.fromJson(json).toJson(), equals(json));
  });

  test('import.file.result: decodifica y codifica sin perder campos', () async {
    final json = await _fixture('import.file.result.json');
    expect(ImportResult.fromJson(json).toJson(), equals(json));
  });

  test('jobs.cancel.params: decodifica y codifica sin perder campos', () async {
    final json = await _fixture('jobs.cancel.params.json');
    expect(JobCancelParams.fromJson(json).toJson(), equals(json));
  });

  test('jobs.cancel.result: decodifica y codifica sin perder campos', () async {
    final json = await _fixture('jobs.cancel.result.json');
    expect(CancelResult.fromJson(json).toJson(), equals(json));
  });

  test('jobs.list.result: decodifica y codifica sin perder campos', () async {
    final json = await _fixture('jobs.list.result.json');
    final result = JobsListResult.fromJson(json);
    expect(result.jobs, hasLength(1));
    expect(result.jobs.first.stage, JobStage.separation);
    expect(result.jobs.first.state, JobState.running);
    expect(result.toJson(), equals(json));
  });

  test('jobs.progress.event: decodifica y codifica sin perder campos', () async {
    final json = await _fixture('jobs.progress.event.json');
    final job = JobInfo.fromJson(json);
    expect(job.fraction, 0.25);
    expect(job.isImportJob, isFalse);
    expect(job.toJson(), equals(json));
  });

  test('valores de stage y state no previstos caen en unknown', () {
    final job = JobInfo.fromJson(const {
      'id': 'link-1',
      'title': 'x',
      'stage': 'remux',
      'state': 'paused',
      'text': '',
    });
    expect(job.stage, JobStage.unknown);
    expect(job.state, JobState.unknown);
    expect(job.isLinkJob, isTrue);
  });
}
