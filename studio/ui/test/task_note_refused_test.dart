import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/task_card.dart';

/// Why an approval was refused is said by the card: the gateway's own
/// words as they came, Studio's two reasons in the language shown.
void main() {
  test('the words of a refused approval, en and uk', () async {
    await S.load(const Locale('en'));
    expect(
      const TaskNoteRefused('step 2 needs config').text,
      startsWith(
        'The approval was refused; the task still waits. '
        'step 2 needs config\n',
      ),
    );
    expect(
      const TaskNoteRefused.changed().why,
      'the plan or its ticks changed after they were shown. Read the plan '
      'again and approve what it says now.',
    );
    expect(
      const TaskNoteRefused.unseen(3).why,
      'the arguments of step 3 are masked: its schema is not known. Show '
      'them, then approve.',
    );
    expect(const TaskNoteRefused.changed().caution, isTrue);

    await S.load(const Locale('uk'));
    addTearDown(() => S.load(const Locale('en')));
    expect(const TaskNoteRefused.unseen(3).why, contains('кроку 3'));
    expect(const TaskNoteRefused.changed().why, startsWith('план або'));
    // the gateway's words are data: as they came
    expect(const TaskNoteRefused('no').why, 'no');
  });

  test('two refusals are equal by what they say', () {
    expect(const TaskNoteRefused.unseen(1), const TaskNoteRefused.unseen(1));
    expect(
      const TaskNoteRefused.unseen(1),
      isNot(const TaskNoteRefused.unseen(2)),
    );
    expect(
      const TaskNoteRefused.changed(),
      isNot(const TaskNoteRefused('changed')),
    );
  });
}
