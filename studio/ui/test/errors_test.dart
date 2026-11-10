import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/alerts/panel_fault.dart';
import 'package:ui/alerts/start_fault.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/buttons/problems_pill.dart';
import 'package:ui/containers/fault_boundary.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/problems_drawer.dart';

import 'frames/errors.dart';
import 'frames/harness.dart';

/// A widget that throws while it builds until [broken] is cleared.
class _Fragile extends StatelessWidget {
  const _Fragile();

  static var broken = true;

  @override
  Widget build(BuildContext context) {
    if (broken) {
      throw RangeError.index(3, const [1, 2, 3]);
    }
    return const Text('the inspector');
  }
}

void main() {
  setUpAll(() => S.load(const Locale('en')));

  group('ErrorDialog keys (errors.md §3)', () {
    late List<String> log;

    Future<void> open(WidgetTester tester, String kind) async {
      log = [];
      await tester.pumpWidget(
        frame(
          ErrorDialog(
            vm: errorDialogVm(kind),
            onPrimary: () => log.add('primary'),
            onSecondary: () => log.add('secondary'),
            onClose: () => log.add('close'),
            onCopy: () => log.add('copy'),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the main button has the focus, so Enter presses it', (
      tester,
    ) async {
      await open(tester, 'rights');

      final primary = find.byKey(const ValueKey('error-primary'));
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: primary, matching: find.text('OK')),
          ),
        ).hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, ['primary']);
    });

    testWidgets('Esc is Close, not the main button', (tester) async {
      await open(tester, 'reach');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(log, ['close']);
    });

    testWidgets('Cmd+C and Ctrl+C copy the details', (tester) async {
      await open(tester, 'broker');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(log, ['copy', 'copy']);
    });

    testWidgets('the buttons call what they stand for', (tester) async {
      await open(tester, 'rights');
      await tester.tap(find.text('See my access'));
      await tester.tap(find.text('Copy details'));
      await tester.tap(find.byKey(const ValueKey('error-close')));
      await tester.tap(find.text('OK'));
      expect(log, ['secondary', 'copy', 'close', 'primary']);
    });

    testWidgets('Tab stays inside the dialog', (tester) async {
      await open(tester, 'rights');
      final seen = <String>{};
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus!.context!;
        expect(
          find.descendant(
            of: find.byType(ErrorDialog),
            matching: find.byWidget(focus.widget),
          ),
          findsOneWidget,
        );
        seen.add('${focus.widget.runtimeType}');
      }
      expect(seen, isNotEmpty);
    });

    testWidgets('Details are closed, and open on a tap; open for broker', (
      tester,
    ) async {
      await open(tester, 'rights');
      expect(find.text('permission_denied (0x21)'), findsNothing);
      expect(find.text('permission_denied'), findsOneWidget, reason: 'chip');

      await tester.tap(find.byKey(const ValueKey('error-details')));
      await tester.pump();
      expect(find.text('permission_denied (0x21)'), findsOneWidget);
      expect(find.text('olena (operator)'), findsOneWidget);

      await tester.pumpWidget(
        frame(
          ErrorDialog(
            vm: errorDialogVm('broker', details: true),
            onPrimary: () {},
            onClose: () {},
          ),
        ),
      );
      expect(find.text('internal_error (0x25)'), findsOneWidget);
    });

    testWidgets('a timeout on a write warns that it may have been applied', (
      tester,
    ) async {
      await open(tester, 'reach');
      expect(
        find.textContaining('may still have been applied'),
        findsOneWidget,
      );
      await open(tester, 'gone');
      expect(find.textContaining('may still have been applied'), findsNothing);
    });

    testWidgets('busy counts down, disabled, then tries again once by '
        'itself', (tester) async {
      await open(tester, 'busy');
      expect(find.text('Try again in 4 s'), findsOneWidget);

      // Disabled while it counts: neither a tap nor Enter presses it.
      await tester.tap(find.byKey(const ValueKey('error-primary')));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Try again in 3 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(log, ['primary']);

      await tester.pump(const Duration(seconds: 10));
      expect(log, ['primary'], reason: 'once');
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the message can be selected', (tester) async {
      await open(tester, 'input');
      expect(
        find.widgetWithText(
          SelectableText,
          'poll_rate: 0 is below the minimum of 100 ms.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('it is an alert dialog named by its title', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, 'rights');
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('You can’t deploy pump-control').first,
        ),
        isNotNull,
      );
      handle.dispose();
    });

    testWidgets('a long key and a long message fit a narrow window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        frame(
          ErrorDialog(
            vm: ErrorDialogVm(
              tone: .bad,
              icon: 'err_broker',
              title: 'Installing ${'a-very-long-package-name' * 3} failed',
              where: 'wy/plant/${'downstream/segment' * 8} › install_repo',
              saidLabel: 'The broker said',
              said: 'x' * 900,
              advice: const ['One.', 'Two.'],
              chip: 'internal_error',
              details: const [ErrorRowVm('Status', 'internal_error (0x25)')],
              detailsOpen: true,
              secondary: 'Close',
              primary: 'Open the log',
            ),
            onPrimary: () {},
            onClose: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FaultBoundary and PanelFault (errors.md §5)', () {
    late ErrorWidgetBuilder before;

    setUp(() {
      before = ErrorWidget.builder;
      ErrorWidget.builder = PanelFault.builder;
      _Fragile.broken = true;
    });
    tearDown(() => ErrorWidget.builder = before);

    Widget screen() => frame(
      Row(
        children: [
          const Expanded(child: Text('the tree')),
          SizedBox(
            width: 400,
            child: FaultBoundary(
              panel: .inspector,
              child: Builder(builder: (_) => const _Fragile()),
            ),
          ),
        ],
      ),
    );

    testWidgets('a panel that throws is replaced by the card; the rest of '
        'the screen stays', (tester) async {
      await tester.pumpWidget(screen());
      expect(tester.takeException(), isA<RangeError>());

      expect(find.text('The inspector could not be drawn'), findsOneWidget);
      expect(
        find.textContaining('The rest of Studio still works'),
        findsOneWidget,
      );
      expect(find.textContaining('RangeError'), findsOneWidget);
      expect(find.textContaining('· inspector ·'), findsOneWidget);
      expect(find.text('the tree'), findsOneWidget);
      expect(find.text('Draw it again'), findsOneWidget);
      expect(find.text('Copy report'), findsOneWidget);
    });

    testWidgets('Draw it again builds that panel again, and only it', (
      tester,
    ) async {
      var outer = 0;
      await tester.pumpWidget(
        frame(
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (_) {
                    outer++;
                    return const Text('the tree');
                  },
                ),
              ),
              const SizedBox(
                width: 400,
                child: FaultBoundary(panel: .inspector, child: _Fragile()),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isA<RangeError>());
      final outerBefore = outer;

      // Still broken: the card again.
      await tester.tap(find.text('Draw it again'));
      await tester.pump();
      expect(tester.takeException(), isA<RangeError>());
      expect(find.text('The inspector could not be drawn'), findsOneWidget);

      _Fragile.broken = false;
      await tester.tap(find.text('Draw it again'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('the inspector'), findsOneWidget);
      expect(find.text('The inspector could not be drawn'), findsNothing);
      expect(outer, outerBefore, reason: 'the tree was not built again');
    });

    testWidgets('Copy report hands the fault and the panel to the app', (
      tester,
    ) async {
      final copied = <(Object, String?)>[];
      PanelFault.copyReport = (d, panel) => copied.add((d.exception, panel));
      addTearDown(() => PanelFault.copyReport = null);
      await tester.pumpWidget(screen());
      tester.takeException();

      await tester.tap(find.text('Copy report'));

      expect(copied.single.$1, isA<RangeError>());
      expect(copied.single.$2, 'inspector');
    });

    testWidgets('without a boundary it is "This part", with no Draw it '
        'again', (tester) async {
      await tester.pumpWidget(frame(const _Fragile()));
      tester.takeException();
      expect(find.text('This part could not be drawn'), findsOneWidget);
      expect(find.text('Draw it again'), findsNothing);
    });

    testWidgets('in a box too small for the card it is the mark alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        frame(
          const Center(
            child: SizedBox(width: 40, height: 24, child: _Fragile()),
          ),
        ),
      );
      tester.takeException();
      expect(find.text('This part could not be drawn'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });

    testWidgets('a fault above the app (no theme, no direction) still '
        'draws the card', (tester) async {
      await tester.pumpWidget(const _Fragile());
      expect(tester.takeException(), isA<RangeError>());
      expect(find.text('This part could not be drawn'), findsOneWidget);
    });
  });

  group('toasts (errors.md §4)', () {
    testWidgets('one hides when its 8 s are up; one of a stream stays', (
      tester,
    ) async {
      final expired = <int>[];
      await tester.pumpWidget(
        frame(
          Align(
            alignment: .bottomRight,
            child: SizedBox(
              width: ToastStack.width,
              child: ToastStack(
                toasts: errorToasts,
                onDismiss: (_) {},
                onExpire: expired.add,
              ),
            ),
          ),
        ),
      );
      expect(find.text('hides in 8 s'), findsOneWidget);
      expect(find.text('stays until edge is back'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('hides in 5 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      expect(expired, [1]);
      await tester.pump(const Duration(seconds: 30));
      expect(expired, [1], reason: 'the stream one never expires');
    });

    testWidgets('at most three are drawn: the newest', (tester) async {
      await tester.pumpWidget(
        frame(
          SingleChildScrollView(
            child: ToastStack(
              toasts: [
                for (var i = 1; i <= 5; i++) ToastVm(id: i, title: 'toast $i'),
              ],
              onDismiss: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('toast 1'), findsNothing);
      expect(find.text('toast 2'), findsNothing);
      expect(find.text('toast 3'), findsOneWidget);
      expect(find.text('toast 5'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Details, Try again and Dismiss name the toast', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        frame(
          ToastStack(
            toasts: errorToasts,
            onDismiss: (id) => log.add('dismiss $id'),
            onDetails: (id) => log.add('details $id'),
            onRetry: (id) => log.add('retry $id'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('toast-details-2')));
      await tester.tap(find.byKey(const ValueKey('toast-retry-1')));
      await tester.tap(find.byKey(const ValueKey('toast-dismiss-1')));
      expect(log, ['details 2', 'retry 1', 'dismiss 1']);
      expect(find.byKey(const ValueKey('toast-retry-2')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Problems (errors.md §4)', () {
    testWidgets('the drawer lists them with their links', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final log = <String>[];
      await tester.pumpWidget(
        frame(
          Align(
            alignment: .centerRight,
            child: ProblemsDrawer(
              problems: errorProblems,
              onClose: () => log.add('close'),
              onClear: () => log.add('clear'),
              onDetails: (id) => log.add('details $id'),
              onRetry: (id) => log.add('retry $id'),
            ),
          ),
        ),
      );
      expect(find.text('Problems · this session'), findsOneWidget);
      expect(find.text('shown as a dialog'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('problem-details-4')));
      await tester.tap(find.byKey(const ValueKey('problem-retry-5')));
      await tester.tap(find.byKey(const ValueKey('problems-clear')));
      await tester.tap(find.byKey(const ValueKey('problems-close')));

      expect(log, ['details 4', 'retry 5', 'clear', 'close']);
      expect(find.byKey(const ValueKey('problem-retry-4')), findsNothing);
    });

    testWidgets('the pill says the count and opens the drawer', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        frame(
          Center(
            child: ProblemsPill(
              vm: const ProblemsPillVm(label: '3 problems', bad: true),
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('3 problems'));
      expect(taps, 1);
    });
  });

  group('Back to the form (errors.md §3)', () {
    testWidgets('the field the broker named shows its words and takes the '
        'focus; typing in it clears them', (tester) async {
      Widget form(Map<String, String> errors, String? focus) => frame(
        ActionForm(
          fields: [
            ParamFieldVm(
              id: 'name',
              label: 'Name',
              kind: ParamKind.text,
              value: 'plc1',
              onChanged: (_) {},
            ),
            ParamFieldVm(
              id: 'poll_rate',
              label: 'Poll rate',
              kind: ParamKind.number,
              value: 0,
              onChanged: (_) {},
            ),
          ],
          submit: 'Save',
          errors: errors,
          focus: focus,
          onSubmit: (_) {},
        ),
      );
      await tester.pumpWidget(form(const {}, null));
      expect(find.text('0 is below the minimum of 100 ms.'), findsNothing);

      await tester.pumpWidget(
        form(const {
          'poll_rate': '0 is below the minimum of 100 ms.',
        }, 'poll_rate'),
      );
      await tester.pump();

      expect(find.text('0 is below the minimum of 100 ms.'), findsOneWidget);
      final field = find.widgetWithText(TextFormField, '0');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.enterText(field, '200');
      await tester.pump();
      expect(find.text('0 is below the minimum of 100 ms.'), findsNothing);
    });
  });

  group('start screen (errors.md §6)', () {
    testWidgets('the three ways on; the kept file is named', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        frame(
          StartFault(
            vm: const StartFaultVm(
              title: 'Studio could not start',
              body: 'The settings are unreadable.',
              rows: [ErrorRowVm('Error', 'FormatException: Invalid database')],
              note: 'Kept as settings.db.broken. Log in again.',
              noteCode: 'settings.db.broken',
            ),
            onFresh: () => log.add('fresh'),
            onCopy: () => log.add('copy'),
            onQuit: () => log.add('quit'),
          ),
        ),
      );
      await tester.tap(find.text('Start with fresh settings'));
      await tester.tap(find.text('Copy report'));
      await tester.tap(find.text('Quit'));
      expect(log, ['fresh', 'copy', 'quit']);
      expect(find.textContaining('settings.db.broken'), findsOneWidget);
    });
  });
}
