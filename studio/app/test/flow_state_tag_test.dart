import 'package:app/mappers/flow_mappers.dart';
import 'package:app/mappers/history_mappers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/flow_summary.dart';
import 'package:models/logging_type.dart';
import 'package:ui/indicators/flow_state_tag.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/history_screen.dart';

/// A flow's state as it is drawn: one whose value Studio could not read
/// is shown as such, in both languages, and never as "not deployed".
void main() {
  test('each state of a flow has its tag', () async {
    await S.load(const Locale('en'));
    expect(
      const FlowSummary(id: 'f', draft: true).tag,
      FlowStateTag.notDeployed,
    );
    expect(
      const FlowSummary(id: 'f', running: true, version: 2).tag,
      FlowStateTag.deployed,
    );
    expect(const FlowSummary(id: 'f', version: 2).tag, FlowStateTag.stopped);
    expect(
      const FlowSummary(id: 'f', problem: 'no rights', version: 2).tag,
      FlowStateTag.error,
    );

    const odd = FlowSummary(id: 'f', unreadable: true);
    expect(odd.tag, FlowStateTag.unreadable);
    expect(odd.tag.tone, Tone.warn);
    expect(odd.row.state, FlowStateTag.unreadable);
    expect(odd.tag.label(odd.version), 'state not read');
    expect(odd.tag.label(odd.version), isNot(S.current.notDeployed));

    await S.load(const Locale('uk'));
    expect(odd.tag.label(odd.version), 'стан не прочитано');
  });

  test('how a watch group records, in both languages', () async {
    await S.load(const Locale('en'));
    expect(
      [for (final l in LoggingType.values) l.ui.label],
      ['None', 'Interval', 'All Data', 'Point Change'],
    );
    expect(
      {for (final l in LoggingType.values) l.ui},
      {...GroupLogging.values},
    );
    await S.load(const Locale('uk'));
    expect(LoggingType.pointChange.ui.label, 'Зміна точки');
  });
}
