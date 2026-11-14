import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/indicators/biometric_icon.dart';
import 'package:ui/overlays/lock_overlay.dart';

import 'frames/harness.dart';

/// The idle lock (ADR 0050 §1.4): no value of the shell in the semantics
/// tree, the shell kept mounted (its state survives), the card's buttons.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  const card = LockCardVm(
    title: 'Studio is locked',
    text: 'olena on plant · locked after 15 min without use.',
    glyph: BiometricGlyph.finger,
    unlockLabel: 'Unlock with Touch ID',
    usePassword: 'Use the password',
    logOut: 'Log out',
    passwordLabel: 'Password for olena',
    unlock: 'Unlock',
  );

  Widget shell(LockCardVm? vm, {VoidCallback? onUnlock}) => frame(
    LockOverlay(
      card: vm,
      onUnlock: onUnlock,
      child: const _Counter(),
    ),
  );

  testWidgets('hides the values from the semantics tree, keeps the shell', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(shell(null));
    await tester.tap(find.text('add'));
    await tester.pump();
    expect(find.bySemanticsLabel('supply_temp 21.6 °C · 1'), findsOneWidget);

    var unlocked = 0;
    await tester.pumpWidget(shell(card, onUnlock: () => unlocked++));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('supply_temp')), findsNothing);
    expect(find.bySemanticsLabel('Unlock with Touch ID'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Unlock with Touch ID').first);
    expect(unlocked, 1);

    await tester.pumpWidget(shell(null));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('supply_temp 21.6 °C · 1'),
      findsOneWidget,
      reason: 'the shell kept its state under the lock',
    );
    semantics.dispose();
  });

  testWidgets('without a key the card asks for the password', (tester) async {
    String? typed;
    await tester.pumpWidget(
      frame(
        LockOverlay(
          card: card,
          onPassword: (p) => typed = p,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pw');
    await tester.tap(find.text('Unlock'));
    expect(typed, 'pw');
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('supply_temp 21.6 °C · $_n'),
      TextButton(
        onPressed: () => setState(() => _n++),
        child: const Text('add'),
      ),
    ],
  );
}
