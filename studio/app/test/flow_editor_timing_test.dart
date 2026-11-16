import 'dart:convert';
import 'dart:io';

import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/pages/flow_editor_page.dart';

import 'support/flow_app.dart';

/// How long the editor takes to follow one change of the store on a real
/// flow (62 blocks, 74 wires: the one the agent deployed on the demo's
/// `central`), before and after the connector is rewritten. It prints and
/// asserts no time: machines differ.
void main() {
  setUp(() => S.load(const Locale('en')));

  Object? json(String name) => jsonDecode(
    File('../business/test/support/flows/$name').readAsStringSync(),
  );

  /// The median and the 90th percentile of [us], in µs.
  String stats(List<int> us) {
    final s = [...us]..sort();
    return 'median=${s[s.length ~/ 2]}µs '
        'p90=${s[(s.length * 9) ~/ 10]}µs';
  }

  testWidgets('the editor follows a change of the store', (t) async {
    final def = (json('large_flow.json')! as Map).cast<String, Object?>();
    final app = FlowApp(
      flow: def['id']! as String,
      def: def,
      catalog: [
        for (final x in json('large_flow_types.json')! as List<Object?>)
          (x! as Map).cast<String, Object?>(),
      ],
    );
    await app.pump(t);
    expect(app.blocks, hasLength(62));

    // A block whose header shows on the canvas, selected by a click.
    final view = t.getRect(find.byType(FlowCanvas));
    final id = app.blocks.keys.firstWhere(
      (b) => view.deflate(40).contains(app.header(t, b)),
    );
    await app.select(t, id);
    expect(app.selected, id);

    /// 50 dispatches of [key]'s value (null: none, the frames alone), each
    /// followed by the frames that show it, timed on the wall clock. The
    /// store tells the connector in a microtask, so the first frame may
    /// come before the new view-model: two frames hold all of its work.
    Future<(List<int>, int)> time(String? key) async {
      final us = <int>[];
      final watch = Stopwatch();
      var built = 0;
      for (var i = 0; i < 50; i++) {
        final before = t.widget(find.byType(FlowEditorPage));
        watch
          ..reset()
          ..start();
        if (key != null) {
          app.store.dispatchSync(
            SetLiveValuesAction({
              key: LiveValue(
                time: DateTime.utc(2026, 11, 12, 2, 2, i),
                value: i,
              ),
            }),
          );
        }
        await t.pump();
        await t.pump();
        watch.stop();
        us.add(watch.elapsedMicroseconds);
        if (!identical(before, t.widget(find.byType(FlowEditorPage)))) {
          built++;
        }
      }
      return (us, built);
    }

    // A point a `subscribe` block of the flow reads: its block shows it,
    // so every change builds the page again.
    final (read, readBuilt) = await time('$plant/storage/dvpsm/cmd/ack');
    expect(app.inBlock('c_ack', '49'), findsOneWidget);
    // A point nothing on the page reads: the view-model is made again and
    // compares equal, so the page is not built again (before the rewrite
    // it always was: `page built 50/50`).
    final (unread, unreadBuilt) = await time(
      '$plant/downstream/elsewhere/x',
    );
    expect(unreadBuilt, 0);
    expect(read.every((us) => us > 0), isTrue);
    // The count is the page's: frames with no change build nothing.
    final (_, idleBuilt) = await time(null);
    expect(idleBuilt, 0);

    debugPrint('fromStore timing: ${stats(read)}');
    debugPrint('  (a key the flow reads; page built $readBuilt/50)');
    debugPrint('fromStore timing, a key not read: ${stats(unread)}');
    debugPrint('  (page built $unreadBuilt/50)');
    await app.leave(t);
  });
}
