import 'package:localization/localization.dart';

import '../models/tone.dart';

/// The state of an agent task as it is drawn: in the task list, the pill
/// of the header, a state line of the conversation, the plan's state line
/// and the card's title.
enum TaskBadge {
  planning(Tone.ember),
  awaitingAnswer(Tone.warn),
  awaitingApproval(Tone.warn),
  running(Tone.ember),
  done(Tone.good),
  failed(Tone.bad);

  const TaskBadge(this.tone);

  final Tone tone;

  String get label => switch (this) {
    planning => S.current.taskPlanning,
    awaitingAnswer => S.current.taskAwaitingAnswer,
    awaitingApproval => S.current.taskAwaiting,
    running => S.current.taskRunning,
    done => S.current.taskDone,
    failed => S.current.taskFailed,
  };
}

/// Who approves the agent's plans (its `require_approval`), as *What it
/// may do* and the tiles of a suggestion say it.
enum AgentModeVm {
  write('write'),
  config('config'),
  never('never');

  const AgentModeVm(this.word);

  /// The mode's own word, as the cautions quote it.
  final String word;

  String get label => switch (this) {
    write => S.current.modeWrite,
    config => S.current.modeConfig,
    never => S.current.modeNever,
  };

  String get detail => switch (this) {
    write => S.current.modeWriteDetail,
    config => S.current.modeConfigDetail,
    never => S.current.modeNeverDetail,
  };
}

/// What a plan step does, as its chip says it.
enum StepVerb {
  set,
  invoke,
  wait,
  expect,
  sleep;

  /// `SET`, `INVOKE`: the chip's word.
  String get label => name.toUpperCase();

  /// The step changes the plant: its ring and chip are ember.
  bool get changes => this == set || this == invoke;
}

/// How a step of a run ended, as the plan and the run say it: the link's
/// own word and its colour.
enum StepOutcome {
  ok(Tone.good),
  failed(Tone.bad),
  skipped(Tone.neutral);

  const StepOutcome(this.tone);

  final Tone tone;

  /// The link's word for it (`ok`, `failed`, `skipped`).
  String get word => name;
}

/// A node key as a chip and a row show it: below the site, without
/// `downstream/` (`modbus/tcp/plc1/valve`).
String shortKey(String key) {
  final below = key.split('/').skip(2).join('/');
  return below.startsWith('downstream/')
      ? below.substring('downstream/'.length)
      : below;
}

/// A node key below its section (`modbus/tcp/ahu2/sp` of
/// `wy/central/downstream/modbus/tcp/ahu2/sp`).
String belowSection(String key) => key.split('/').skip(3).join('/');

/// The last segment of a key (`sp`).
String lastSegment(String key) => key.split('/').last;

/// A number without a needless fraction: `2.5`, `10`.
String plainNumber(double v) =>
    v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
