import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/system_app.dart';

/// The backup dialogs as System opens and closes them (ADR 0048 §3): the
/// broker backup with its estimate, a kept backup's removal, and a
/// dialog closed while its estimate is still read.
void main() {
  setUp(() => S.load(const Locale('en')));

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(Dialog), matching: find.text(text));

  Future<SystemApp> maintenance(WidgetTester t, {Duration? estimate}) async {
    final app = SystemApp();
    app.api.answers['$sys/backups ▸ estimate'] = (_) => [
      Value.from({
        'sections': {'control': 4096, 'history': 81920},
      }),
    ];
    if (estimate != null) {
      app.api.delays['$sys/backups ▸ estimate'] = estimate;
    }
    await app.pump(t, tab: SysTab.maintenance);
    return app;
  }

  testWidgets('Back up… opens with the estimate; Cancel closes it in the '
      'store', (t) async {
    final app = await maintenance(t);
    await t.tap(find.text('Back up…'));
    await app.settle(t);
    expect(find.byType(Dialog), findsOneWidget);
    expect(app.store.state.backups.stage, 'choose');
    expect(app.calls('estimate'), hasLength(1));
    expect(app.store.state.backups.estimate['history'], 81920);

    await t.tap(inDialog(S.current.cancel));
    await app.settle(t);
    expect(find.byType(Dialog), findsNothing);
    expect(app.store.state.backups.stage, isNull);
    await app.leave(t);
  });

  testWidgets('Back up… closed while its estimate runs, then Restore…: the '
      'late estimate leaves the restore and its upload alone', (t) async {
    final app = await maintenance(t, estimate: const Duration(seconds: 3));
    await t.tap(find.text('Back up…'));
    await app.settle(t);
    await t.tap(inDialog(S.current.cancel));
    await app.settle(t);
    expect(
      app.store.state.backups.stage,
      isNull,
      reason: 'closed at once, not when the estimate ends',
    );

    await t.tap(find.text('Restore…'));
    await app.settle(t);
    expect(app.store.state.backups.stage, 'restore');
    // an upload of the restore is under way
    app.put(
      (s) => s.copyWith.backups(upload: 'u1', uploadName: 'plant.wyrm-backup'),
    );

    // the first estimate ends now
    await t.pump(const Duration(seconds: 4));
    await app.settle(t);
    final b = app.store.state.backups;
    expect(b.stage, 'restore');
    expect(b.upload, 'u1');
    expect(b.uploadName, 'plant.wyrm-backup');
    expect(b.estimate, isEmpty, reason: 'read for the closed dialog');
    expect(app.calls('restore_abort'), isEmpty);
    expect(find.byType(Dialog), findsOneWidget);
    await app.leave(t);
  });

  testWidgets('a failed backup is removed after the question, and its '
      'dialog closes', (t) async {
    final app = await maintenance(t);
    app.api.invokes['$sys/backups/b3 ▸ remove'] = const [VNull()];
    // the rows are newest first: b5, b4, b3 (failed)
    await t.tap(find.text('Open').at(2));
    await app.settle(t);
    expect(app.store.state.backups.job, 'b3');

    await t.tap(inDialog(S.current.remove));
    await app.settle(t);
    expect(
      find.text(S.current.bakRemoveTitle('plant-b3.wyrm-backup')),
      findsOneWidget,
    );
    expect(app.calls('remove'), isEmpty, reason: 'asked first');

    await t.tap(find.text(S.current.remove).last);
    await app.settle(t);
    final call = app.calls('remove').single;
    expect(call.key, '$sys/backups/b3');
    expect(find.byType(Dialog), findsNothing);
    expect(app.store.state.backups.stage, isNull);
    await app.leave(t);
  });

  testWidgets('a removal the user takes back removes nothing', (t) async {
    final app = await maintenance(t);
    await t.tap(find.text('Open').at(2));
    await app.settle(t);
    await t.tap(inDialog(S.current.remove));
    await app.settle(t);
    await t.tap(find.text(S.current.cancel).last);
    await app.settle(t);
    expect(app.calls('remove'), isEmpty);
    expect(app.store.state.backups.job, 'b3', reason: 'still open');
    await app.leave(t);
  });
}
