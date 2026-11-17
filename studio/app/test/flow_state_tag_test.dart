import 'package:app/mappers/flow_mappers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/flow_summary.dart';
import 'package:ui/indicators/flow_state_tag.dart';
import 'package:ui/models/tone.dart';

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
}
