import 'dart:io';

import 'package:app/common/blocking_actions.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:flutter_test/flutter_test.dart';

/// The barrier's list and the `BlockingAction` mixin say the same thing.
///
/// Through async_redux 29 the barrier asked `Wait` for "any flag that is a
/// `BlockingAction`", so the mixin alone was membership. The store of
/// async_redux 30 compares exact runtime types and cannot be asked about a
/// mixin; the barrier asks about [blockingActions]. What the mixin gave for
/// free, that an action written later raises the barrier with no second
/// edit, is now this test: it reads the sources and fails while an action
/// has the mixin and is not listed, or is listed without it.
void main() {
  /// The actions of `business` and `app` whose `with` clause names
  /// `BlockingAction`, by class name.
  Set<String> marked() {
    final found = <String>{};
    final declaration = RegExp(
      r'class\s+(\w+)\s+extends\s+[\w<>, .]+?\s+with\s+([\w<>,\s.]+?)\s*\{',
    );
    for (final root in ['lib', '../business/lib']) {
      final dir = Directory(root);
      expect(dir.existsSync(), isTrue, reason: '$root is read from app/');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) {
          continue;
        }
        for (final m in declaration.allMatches(f.readAsStringSync())) {
          final mixins = m.group(2)!.split(',').map((x) => x.trim());
          if (mixins.any((x) => x.split('.').last == 'BlockingAction')) {
            found.add(m.group(1)!);
          }
        }
      }
    }
    return found;
  }

  test('the pattern finds an action that has the mixin', () {
    // Or the test below would pass for ever on a pattern that finds none.
    final declaration = RegExp(
      r'class\s+(\w+)\s+extends\s+[\w<>, .]+?\s+with\s+([\w<>,\s.]+?)\s*\{',
    );
    final m = declaration.firstMatch(
      'class SaveAction extends Action\n'
      '    with NonReentrant, WaitingAction, BlockingAction {',
    );
    expect(m?.group(1), 'SaveAction');
    expect(m?.group(2), contains('BlockingAction'));
  });

  test('every action with BlockingAction is listed, and only those', () {
    expect(
      {for (final t in blockingActions) '$t'},
      marked(),
      reason:
          'app/lib/common/blocking_actions.dart and the BlockingAction '
          'mixin disagree: the barrier covers the app for the listed '
          'types only',
    );
  });

  test('the list has no type twice', () {
    expect(blockingActions.toSet().length, blockingActions.length);
  });

  test('the log-in does not raise it: the page shows its own progress', () {
    // LogInAction was the one blocking action. The log-in page now shows
    // the busy button and the three live steps (docs/design/specs/login.md
    // §3.6–3.7); the barrier would blur them over.
    final w = Waiting.fixed({LogInAction});

    expect(w.any(blockingActions), isFalse);
    expect(w.logIn, isTrue);
  });

  test('nothing in flight raises nothing', () {
    expect(const Waiting.none().any(blockingActions), isFalse);
  });
}
