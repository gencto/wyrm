import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/flows/bind_refusal.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/field_word.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/overlays/review_panel.dart';

/// Studio's own words for a field of a block and for a staged change are
/// said by `ui` from the `.arb` files (studio-rules §5): in English the
/// words the editor always had, in Ukrainian their translation.
void main() {
  setUp(() => S.load(const Locale('en')));

  test('every field word reads as the editor always had it', () {
    expect(
      {for (final w in FieldWordTag.values) w.name: w.label},
      {
        'input': 'Input',
        'output': 'Output',
        'trigger': 'Trigger',
        'inputOutOfRange': 'Input out of range',
        'factor': 'Factor',
        'offset': 'Offset',
        'absoluteChange': 'Absolute change',
        'percentChange': 'Percent change',
        'function': 'Function',
        'operation': 'Operation',
        'expression': 'Expression',
        'message': 'Message',
        'delayMs': 'Delay (ms)',
        'point': 'Point',
        'valueName': 'Value name',
        'meta': 'Meta',
        'allowBadQuality': 'Allow bad quality',
        'onBadQuality': 'On bad quality',
        'maxSamples': 'Max samples',
        'memoryMb': 'Memory (MB)',
        'every': 'Every',
        'autoRun': 'Auto run',
        'runOnStart': 'Run on start',
        'scope': 'Scope',
        'resetMode': 'Reset mode',
        'node': 'Node',
        'writeOn': 'Write on',
        'runOn': 'Run on',
        'intervalS': 'Interval (s)',
        'periodMs': 'Period (ms)',
        'quietTimeMs': 'Quiet time (ms)',
        'delimiter': 'Delimiter',
        'alive': 'Alive',
        'result': 'Result',
        'average': 'Average',
        'active': 'Active',
        'count': 'Count',
        'value': 'Value',
        'runWhen': 'Run when',
        'caseOf': 'Case',
        'then': 'Then',
      },
    );
    expect(const FieldWordVm(FieldWordTag.input, 2).text, 'Input 2');
    expect(const FieldWordVm(FieldWordTag.then, 1).text, 'Then 1');
    expect([for (final o in ChangeOpTag.values) o.label], [
      'Edit',
      'Add',
      'Remove',
    ]);
  });

  test('a word wins over the data text; data reads as it came', () async {
    const worded = FieldRowVm(
      id: 'in:in.0',
      label: '',
      word: FieldWordVm(FieldWordTag.input, 1),
    );
    const data = FieldRowVm(id: 'p:size_s', label: 'Window');
    const row = InspectorRowVm(
      id: 'p:k',
      name: '',
      word: FieldWordVm(FieldWordTag.factor),
      editor: FieldEditorVm.text,
    );
    const pin = FlowPinVm(
      label: '',
      word: FieldWordVm(FieldWordTag.scope),
      pinned: true,
    );
    const target = RowTargetVm(
      'show',
      '',
      word: FieldWordVm(FieldWordTag.value),
    );
    const refusal = RefuseNoInput('', word: FieldWordVm(FieldWordTag.output));
    expect(
      (worded.reads, data.reads, row.label, pin.reads, target.text),
      ('Input 1', 'Window', 'Factor', 'Scope', 'show.Value'),
    );
    expect(refusal.label, S.current.refuseNoInput('Output'));
    expect(const RowTargetVm('plc1', 'fan').text, 'plc1.fan');

    await S.load(const Locale('uk'));
    expect(
      (worded.reads, data.reads, row.label, pin.reads, target.text),
      ('Вхід 1', 'Window', 'Множник', 'Межі', 'show.Значення'),
    );
    expect(ChangeOpTag.remove.label, 'Видалення');
  });
}
