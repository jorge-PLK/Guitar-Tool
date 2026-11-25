part of 'tab.dart';

// Enums: el valor crudo del JSON va en `wire`. Lo no previsto cae en `unknown`.

enum TabPhase with TabWire {
  waitingAnalysis('waitingAnalysis'),
  empty('empty'),
  working('working'),
  ready('ready'),
  failed('failed'),
  choosingSource('choosingSource'),
  unknown('unknown');

  const TabPhase(this.wire);
  @override
  final String wire;
}

enum TabSource with TabWire {
  automatic('automatic'),
  songsterr('songsterr'),
  unknown('unknown');

  const TabSource(this.wire);
  @override
  final String wire;
}

enum TabTrackKind with TabWire {
  guitar('guitar'),
  bass('bass'),
  drums('drums'),
  vocal('vocal'),
  unknown('unknown');

  const TabTrackKind(this.wire);
  @override
  final String wire;
}

enum TabOrigin with TabWire {
  songsterr('songsterr'),
  stem('stem'),
  extra('extra'),
  unknown('unknown');

  const TabOrigin(this.wire);
  @override
  final String wire;
}

enum TabTranscription with TabWire {
  ready('ready'),
  queued('queued'),
  transcribing('transcribing'),
  missing('missing'),
  failed('failed'),
  unknown('unknown');

  const TabTranscription(this.wire);
  @override
  final String wire;
}

enum TabSynth with TabWire {
  rendering('rendering'),
  ready('ready'),
  failed('failed'),
  unknown('unknown');

  const TabSynth(this.wire);
  @override
  final String wire;
}

enum TabListenMode with TabWire {
  stems('stems'),
  transcription('transcription'),
  mixed('mixed'),
  unknown('unknown');

  const TabListenMode(this.wire);
  @override
  final String wire;
}

enum TabProgressState with TabWire {
  transcribing('transcribing'),
  done('done'),
  failed('failed'),
  cancelled('cancelled'),
  unknown('unknown');

  const TabProgressState(this.wire);
  @override
  final String wire;
}

enum TabTuningPreset with TabWire {
  standard('standard'),
  halfStepDown('halfStepDown'),
  wholeStepDown('wholeStepDown'),
  dropD('dropD'),
  custom('custom'),
  unknown('unknown');

  const TabTuningPreset(this.wire);
  @override
  final String wire;
}

enum TabHeaderCode with TabWire {
  meterBpm('meterBpm'),
  meter('meter'),
  unknown('unknown');

  const TabHeaderCode(this.wire);
  @override
  final String wire;
}

enum TabSummaryCode with TabWire {
  note('note'),
  noNote('noNote'),
  drums('drums'),
  drumsNoHits('drumsNoHits'),
  unknown('unknown');

  const TabSummaryCode(this.wire);
  @override
  final String wire;
}

enum TabDrumPiece with TabWire {
  kick('kick'),
  snare('snare'),
  hiHat('hiHat'),
  openHiHat('openHiHat'),
  tom('tom'),
  crash('crash'),
  unknown('unknown');

  const TabDrumPiece(this.wire);
  @override
  final String wire;
}
