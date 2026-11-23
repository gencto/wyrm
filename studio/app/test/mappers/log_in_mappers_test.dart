import 'package:app/mappers/log_in_mappers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/answer_fault.dart';
import 'package:ui/pages/log_in_data.dart';

/// Why `/api/info` gave nothing is named by `business` and said by `ui`
/// (studio-rules §5): the row's note is the words it had, in the language
/// on screen.
void main() {
  setUp(() => S.load(const Locale('en')));

  String note(AnswerFault f) => FoundProblemKind.noAnswer.text('', why: f.view);

  test('each reason in the note of a row with no answer', () {
    expect(
      note(const AnswerFault.timedOut()),
      'Not offered: /api/info did not answer (timed out).',
    );
    expect(
      note(const AnswerFault.http(502)),
      'Not offered: /api/info did not answer (HTTP 502).',
    );
    expect(
      note(const AnswerFault.notGateway()),
      contains('(not a WYRM gateway)'),
    );
    expect(
      note(const AnswerFault.wrongShape('GatewayInfo.site')),
      contains('not a WYRM gateway: the field GatewayInfo.site does not read'),
    );
    // the system's own words are shown as they came
    expect(
      note(const AnswerFault.said('Connection refused')),
      contains('(Connection refused)'),
    );
  });

  test('in Ukrainian', () async {
    await S.load(const Locale('uk'));
    expect(note(const AnswerFault.timedOut()), contains('(час вийшов)'));
    expect(note(const AnswerFault.said('ECONNRESET')), contains('ECONNRESET'));
  });
}
