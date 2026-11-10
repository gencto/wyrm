// The real app against a demo gateway, on the desktop, with real fonts:
//
//   (examples/demo/run.sh running)
//   cd studio/app && flutter test integration_test -d macos \
//     --dart-define=WYRM_GATEWAY=http://127.0.0.1:8445
//
// It logs in and writes a PNG of each workspace to the app's temp folder
// (printed as `screen <path>`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/navigation/app_router.dart';
import 'package:app/run_env.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/environment.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart' as business;
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/wyrm/calls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:models/error_kind.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/forms/log_toolbar.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/overlays/problems_drawer.dart';
import 'package:ui/tables/log_table.dart';
import 'package:ui/trees/tree_row.dart';
import 'package:window_manager/window_manager.dart';

// ignore: do_not_use_environment, a test parameter.
const gateway = String.fromEnvironment('WYRM_GATEWAY');
// ignore: do_not_use_environment, a test parameter.
const password = String.fromEnvironment(
  'WYRM_PASSWORD',
  defaultValue: 'wyrm-demo-1',
);

/// A read nobody asked for, of a key that is not there: a quiet failure.
class _QuietRead extends business.Action {
  _QuietRead(this.key) : super(quiet: true);

  final String key;

  @override
  Future<AppState?> reduce() async {
    await metaOf(deps.wyrm, key);
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    final boundary = tester
        .renderObjectList<RenderRepaintBoundary>(
          find.byType(RepaintBoundary),
        )
        .first;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    // The macOS app is sandboxed: its temp folder is inside its container.
    final dir = Directory('${Directory.systemTemp.path}/wyrm-screens')
      ..createSync(recursive: true);
    debugPrint('screen ${dir.path}/$name.png');
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The canvas tools of the flow editor (flow-editor.md §12–§15) on the
  /// flow that is open: the shortcut card, Select all, the context menu
  /// with its Fields checklist, copy and paste, undo, the viewer's Edit
  /// mode. Only the draft in memory changes; nothing is deployed.
  Future<void> canvasTools(WidgetTester tester) async {
    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester, 500);
    }

    int blocks() => tester.widgetList(find.byType(FlowBlockView)).length;
    final canvas = tester.getRect(find.byType(FlowCanvas));
    final count = blocks();

    await tester.tap(find.byKey(const ValueKey('flow-help')));
    await settle(tester, 500);
    await shot(tester, '03f_flow_shortcuts');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 300);

    // Fit all, then everything selected.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await chord(LogicalKeyboardKey.keyA);
    await shot(tester, '03g_flow_select_all');

    // Copy, paste (under the pointer's last place), then take it back.
    await chord(LogicalKeyboardKey.keyC);
    await chord(LogicalKeyboardKey.keyV);
    debugPrint('flow paste: $count blocks, then ${blocks()}');
    await shot(tester, '03h_flow_pasted');
    await chord(LogicalKeyboardKey.keyZ);
    debugPrint('flow undo: ${blocks()} blocks');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 300);

    // The menu of one block, and its Fields checklist.
    final block = find.byType(FlowBlockView).first;
    await tester.tapAt(
      tester.getTopLeft(block) + const Offset(60, 50),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await settle(tester, 500);
    debugPrint('flow menu: ${find.byType(FlowMenu).evaluate().length}');
    if (find.text('Fields').evaluate().isNotEmpty) {
      await tester.tap(find.text('Fields'));
      await settle(tester, 500);
    }
    await shot(tester, '03i_flow_menu_fields');
    await tester.tapAt(canvas.bottomRight - const Offset(30, 90));
    await settle(tester, 500);

    // The value viewer of the first inspector row, in its Edit mode.
    final eye = find.byTooltip('View value');
    if (eye.evaluate().isNotEmpty) {
      for (final e in eye.evaluate().toList()) {
        await tester.tap(find.byWidget(e.widget), warnIfMissed: false);
        await settle(tester, 500);
        if (find.byKey(const ValueKey('viewer-edit')).evaluate().isNotEmpty) {
          break;
        }
      }
      await shot(tester, '03j_flow_viewer');
      final edit = find.byKey(const ValueKey('viewer-edit'));
      if (edit.evaluate().isNotEmpty) {
        await tester.tap(edit);
        await settle(tester, 500);
        await shot(tester, '03k_flow_viewer_edit');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester, 300);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, 300);
    }
    // Nothing selected again: the inspector shows the flow.
    await tester.tapAt(canvas.bottomRight - const Offset(30, 90));
    await settle(tester, 300);
    debugPrint('flow canvas tools: overflow ${tester.takeException()}');
  }

  /// Wave 2 of the flow editor (flow-editor.md §17–§20, ADR 0040) on the
  /// flow that is open: what the broker can do (said in the log), the Tree
  /// tab as the site's live tree with values and actions, a value and an
  /// action dragged onto the canvas, the action block's inspector, the My
  /// blocks tab and the custom-block items of the menu (on, or off with
  /// the reason on a broker without ADR 0040). Only the draft in memory
  /// changes; nothing is deployed, nothing is run.
  Future<void> wave2(WidgetTester tester, Store<AppState> store) async {
    final ed = SelectFlowEditor(store.state);
    debugPrint(
      'flow caps: ${ed.caps} library=${ed.library.length} '
      'libraryOff=${ed.libraryOff}',
    );
    int blocks() => tester.widgetList(find.byType(FlowBlockView)).length;
    final canvas = tester.getRect(find.byType(FlowCanvas));
    final before = blocks();

    Future<void> dragOut(Finder row, Offset to) async {
      final from = tester.getCenter(row);
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await settle(tester, 800);
    }

    // The Tree tab: the tree of the site, opened down to a device.
    await tester.tap(find.text('Tree').first);
    await settle(tester);
    final palette = find.byType(BlockPalette);
    Finder inTree(String name) =>
        find.descendant(of: palette, matching: find.text(name));
    // The tree is the Explorer's: a node it opened is open here already.
    for (final key in [
      'wy/edge/downstream/modbus',
      'wy/edge/downstream/modbus/line1',
      'wy/edge/downstream/modbus/line1/ahu1',
    ]) {
      final row = find.descendant(
        of: palette,
        matching: find.byKey(ValueKey('tree-$key')),
      );
      if (row.evaluate().isEmpty) {
        continue;
      }
      await tester.ensureVisible(row);
      await settle(tester, 300);
      if (!tester.widget<TreeRow>(row).vm.expanded) {
        await tester.tap(row);
        await settle(tester, 1800);
      }
    }
    debugPrint('flow tree: ahu1 rows ${inTree('ahu1').evaluate().length}');
    final rows = tester.widgetList<TreeRow>(
      find.descendant(of: palette, matching: find.byType(TreeRow)),
    );
    final leaves = [
      for (final r in rows)
        if (r.vm.drag?.startsWith('key:') ?? false) r.vm,
    ];
    final actions = [
      for (final r in rows)
        if (r.vm.drag?.startsWith('act:') ?? false) r.vm,
    ];
    debugPrint(
      'flow tree: ${rows.length} rows, ${leaves.length} values '
      '(${leaves.where((l) => l.value != null).length} with a value), '
      '${actions.length} actions',
    );
    await shot(tester, '03l_flow_tree');

    // A value onto the canvas: a block that reads it (a writable one asks
    // Read or Write first).
    if (leaves.isNotEmpty) {
      await dragOut(
        find.byKey(ValueKey('tree-${leaves.first.drag}')),
        canvas.center + const Offset(-120, 160),
      );
      if (find.text('Read').evaluate().isNotEmpty) {
        await shot(tester, '03m_flow_tree_read_write');
        await tester.tap(find.text('Read').last);
        await settle(tester, 800);
      }
      debugPrint('flow tree value dropped: $before blocks, then ${blocks()}');
    }
    // An action onto the canvas: the action block, selected.
    if (actions.isNotEmpty) {
      await dragOut(
        find.byKey(ValueKey('tree-${actions.first.drag}')),
        canvas.center + const Offset(140, 200),
      );
      debugPrint('flow tree action dropped: ${blocks()} blocks');
      await shot(tester, '03n_flow_action_block');
    }
    debugPrint('flow tree: overflow ${tester.takeException()}');

    // My blocks: on with the site's library, or off with the reason.
    await tester.tap(find.text('My blocks').first, warnIfMissed: false);
    await settle(tester, 1200);
    debugPrint(
      'flow my blocks: tab ${SelectFlowEditor(store.state).palette}, '
      'library ${SelectFlowEditor(store.state).library.length}',
    );
    await shot(tester, '03o_flow_my_blocks');

    // The menu of the selection: Create custom block…, on or off.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester, 400);
    final block = find.byType(FlowBlockView).first;
    await tester.tapAt(
      tester.getTopLeft(block) + const Offset(60, 50),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await settle(tester, 600);
    await shot(tester, '03p_flow_menu_custom');
    final create = find.descendant(
      of: find.byType(FlowMenu),
      matching: find.textContaining('Create custom block'),
    );
    debugPrint('flow menu create: ${create.evaluate().length}');
    if (SelectFlowEditor(store.state).caps.blocks &&
        create.evaluate().isNotEmpty) {
      await tester.tap(create.first);
      await settle(tester, 800);
      await shot(tester, '03q_flow_create_block');
      if (find.byKey(const ValueKey('block-create')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('block-create')));
        await settle(tester, 1000);
        await shot(tester, '03r_flow_custom_instance');
        final open = find.text('Open inside');
        if (open.evaluate().isNotEmpty) {
          await tester.tap(open.first);
          await settle(tester, 1000);
          await shot(tester, '03s_flow_custom_inside');
          await tester.tap(find.byKey(const ValueKey('flow-back')));
          await settle(tester, 800);
        }
      }
    } else {
      await tester.tapAt(canvas.bottomRight - const Offset(30, 90));
      await settle(tester, 400);
    }
    // Back to the deployed draft: every edit of this walk is undone.
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester, 150);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 300);
    debugPrint(
      'flow wave 2: ${blocks()} blocks at the end (was $before), '
      'overflow ${tester.takeException()}',
    );
    await tester.tap(find.text('Blocks').first);
    await settle(tester, 500);
  }

  /// The error dialog is a route over the app: its own layer.
  Future<void> dialogShot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(ErrorDialog),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${Directory.systemTemp.path}/wyrm-screens')
      ..createSync(recursive: true);
    debugPrint('screen ${dir.path}/$name.png');
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('log in and visit every workspace', (tester) async {
    await runEnv(await Environment.dev());
    // The window opens where the user left it and as large (once it is
    // ready to show); the steps below count on the boards' 1440 × 900.
    await settle(tester, 1000);
    await windowManager.setSize(const Size(1440, 900));
    await windowManager.center();
    await settle(tester, 2500);
    await shot(tester, '00_login');

    final fields = find.byType(EditableText);
    final store = StoreProvider.backdoorInheritedWidget<AppState>(
      tester.element(find.byType(Router<Object>).first),
    );

    // Errors the page shows itself (docs/design/specs/errors.md §2): a
    // gateway that does not answer and a wrong password are inline, never
    // a dialog, and each is a line in Problems.
    await tester.enterText(fields.at(0), 'http://127.0.0.1:9');
    await tester.enterText(fields.at(1), 'admin');
    await tester.enterText(fields.at(2), password);
    await tester.tap(find.text('Log in').last);
    await settle(tester, 6000);
    expect(find.byType(ErrorDialog), findsNothing);
    final first = store.state.problems.items.first;
    debugPrint(
      'errors: unreachable gateway → ${first.kind.name}/'
      '${first.status?.name}: ${first.title}',
    );
    expect(store.state.problems.items.first.kind, ErrorKind.reach);
    await shot(tester, '00b_login_unreachable');

    await tester.enterText(fields.at(0), gateway);
    await tester.enterText(fields.at(2), 'not-the-password');
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);
    expect(find.byType(ErrorDialog), findsNothing);
    debugPrint(
      'errors: wrong password → ${store.state.problems.items.first.kind.name}'
      '/${store.state.problems.items.first.status?.name}: '
      '${store.state.problems.items.first.title}',
    );
    expect(store.state.problems.items.first.kind, ErrorKind.rights);
    expect(store.state.problems.toasts, isEmpty);
    await shot(tester, '00c_login_wrong');

    await tester.enterText(fields.at(2), password);
    await tester.tap(find.text('Log in').last);
    await settle(tester, 4000);
    debugPrint(
      'after log in: token=${store.state.session.token} '
      'site=${store.state.site.name} wait=${store.state.wait} '
      'login=${store.state.login} '
      'route=${appRouter.current.name}',
    );
    await shot(tester, '01_explorer');
    if (find.text('mock').evaluate().isNotEmpty) {
      await tester.tap(find.text('mock').first);
      await settle(tester, 2500);
      await shot(tester, '01b_explorer_mock');
      store.dispatchSync(
        SelectNodeAction('wy/edge/downstream/modbus/line1/ahu1'),
      );
      await settle(tester, 3000);
      await shot(tester, '01d_explorer_device');
      final point = find.text('setpoint');
      if (point.evaluate().isNotEmpty) {
        await tester.tap(point.last);
        await settle(tester, 2000);
        await shot(tester, '01e_explorer_point');
      }
      store.dispatchSync(
        SelectNodeAction('wy/edge/downstream/modbus/line1/ahu1'),
      );
      await settle(tester);
      // The tab: the header's Actions ▾ (first) opens the node menu.
      await tester.tap(find.text('Actions').last);
      await settle(tester, 1000);
      await shot(tester, '01c_explorer_actions');
      final readId = find.text('Read Device Identification');
      if (readId.evaluate().isNotEmpty) {
        await tester.tap(readId.first);
        await settle(tester, 800);
        await tester.tap(find.text('Run now').last);
        await settle(tester, 2500);
        await shot(tester, '01f_explorer_action_result');
      }
      await tester.tap(find.text('Points').first);
      await settle(tester, 500);

      // One frame per node kind (docs/design/specs/explorer.md "Frames by
      // node kind"): none of them shows the device's points.
      for (final (shotName, key) in [
        ('01g_explorer_flow', 'wy/edge/dataflows/ahu2_ctl'),
        ('01h_explorer_link', 'wy/edge/downstream/modbus'),
        ('01i_explorer_connection', 'wy/edge/downstream/modbus/line1'),
        ('01j_explorer_storage', 'wy/edge/storage/line1'),
        ('01k_explorer_storage_folder', 'wy/edge/storage/line1/test'),
        ('01l_explorer_broker', 'wy/edge/upstream/central'),
      ]) {
        store.dispatchSync(SelectNodeAction(key));
        await settle(tester, 2500);
        // The frame's first tab: Contents, or a flow's Parameters.
        final first = find.text('Contents').evaluate().isNotEmpty
            ? 'Contents'
            : 'Parameters';
        await tester.tap(find.text(first).first);
        await settle(tester, 500);
        await shot(tester, shotName);
        debugPrint(
          '$shotName: points tab ${find.text('Points').evaluate().isNotEmpty}'
          ', overflow ${tester.takeException()}',
        );
        if (key.endsWith('/ahu2_ctl')) {
          // The header's Actions ▾ (before the Actions tab) builds the
          // node menu; the shot cannot hold the overlay, so it only must
          // not throw (its header is covered by ui/test/long_names_test).
          await tester.tap(find.text('Actions').first);
          await settle(tester, 1000);
          debugPrint('flow menu: overflow ${tester.takeException()}');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester, 500);
          final edit = find.text('Edit dataflow');
          if (edit.evaluate().isNotEmpty) {
            await tester.tap(edit.first);
            await settle(tester, 3500);
            await shot(tester, '01g3_explorer_flow_editor');
            debugPrint('editor route: ${appRouter.current.name}');
            await tester.tap(find.byType(IconButton).last);
            await settle(tester);
          }
        }
      }
    }

    for (final (i, name) in [
      'Links',
      'Flows',
      'History',
      'Access',
      'Sites',
      'Assistant',
      'System',
    ].indexed) {
      await tester.tap(find.text(name).first);
      await settle(tester, 2500);
      await shot(tester, '0${i + 2}_${name.toLowerCase()}');
      if (name == 'Flows' && find.text('ahu2_ctl').evaluate().isNotEmpty) {
        await tester.tap(find.text('ahu2_ctl').first);
        await settle(tester, 1000);
        await shot(tester, '03b_flows_selected');
        await tester.tap(find.text('Edit dataflow').first);
        await settle(tester, 3500);
        await shot(tester, '03c_flow_editor');
        // Blocks of the owner's concat check: a variable (one field Value)
        // and concat (bound inputs show the values that come in).
        for (final (b, n) in [('concat1', '03d'), ('string1', '03e')]) {
          final f = find.descendant(
            of: find.byType(FlowCanvas),
            matching: find.text(b),
          );
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first, warnIfMissed: false);
            await settle(tester, 800);
            await shot(tester, '${n}_flow_$b');
          }
        }
        await canvasTools(tester);
        await wave2(tester, store);
        // The editor's own close, in its top bar: the inspector's eye
        // buttons come after it.
        await tester.tap(
          find
              .byWidgetPredicate((w) => w is AppIcon && w.name == 'ui_close')
              .first,
        );
        await settle(tester);
      }
      if (name == 'Assistant' && find.byType(TextField).evaluate().isNotEmpty) {
        await tester.enterText(
          find.byType(TextField).last,
          'What does modbus read on this site?',
        );
        await settle(tester, 300);
        await tester.tap(find.text('Ask').last);
        await settle(tester, 6000);
        await shot(tester, '07b_assistant_ask');
        final refused = find.textContaining('started no task');
        debugPrint('assistant refusal shown: ${refused.evaluate().isNotEmpty}');
        if (find.text('OK').evaluate().isNotEmpty) {
          await tester.tap(find.text('OK').last);
          await settle(tester, 500);
        }
        await tester.tap(find.text('What it may do').first);
        await settle(tester, 500);
        await shot(tester, '07c_assistant_rights');
      }
      if (name == 'System') {
        // The four tabs of System (specs/system.md). Nothing is written:
        // no level is applied, nothing is cleared, no profile is put.
        expect(find.text('links_connected'), findsOneWidget);
        expect(find.text('upstream_connected'), findsOneWidget);
        expect(find.text('downstream_connected'), findsOneWidget);
        expect(find.textContaining('NEEDS A LOOK'), findsOneWidget);
        await tester.tap(find.text('Bytes'));
        await settle(tester, 600);
        expect(find.textContaining('data_in_per_second'), findsOneWidget);
        await shot(tester, '08b_system_bytes');

        await tester.tap(find.text('Availability').first);
        await settle(tester, 800);
        final standby = find.text('standby_connected').evaluate().isNotEmpty;
        debugPrint('system availability: ${standby ? 'standby' : 'none'}');
        expect(
          standby ||
              find
                  .text('No standby is following this broker')
                  .evaluate()
                  .isNotEmpty,
          isTrue,
        );
        expect(find.textContaining('NEEDS A LOOK'), findsOneWidget);
        await shot(tester, '08c_system_availability');

        await tester.tap(find.text('Log').first);
        await settle(tester, 2500);
        expect(find.byType(LogToolbar), findsOneWidget);
        expect(
          find.textContaining('Broker log level', findRichText: true),
          findsOneWidget,
        );
        final rows = tester.widget<LogTable>(find.byType(LogTable)).rows;
        debugPrint('system log rows: ${rows.length}');
        expect(rows, isNotEmpty);
        await shot(tester, '08d_system_log');

        await tester.tap(find.text('Maintenance').first);
        await settle(tester, 800);
        expect(find.text('Disconnected links'), findsOneWidget);
        expect(find.text('Device profiles'), findsOneWidget);
        expect(find.text('Back up and restore'), findsOneWidget);
        expect(find.textContaining('NEEDS A LOOK'), findsOneWidget);
        await shot(tester, '08e_system_maintenance');

        await tester.tap(find.text('Overview').first);
        await settle(tester, 500);
      }
      if (name == 'Links' && find.text('modbus').evaluate().isNotEmpty) {
        await tester.tap(find.text('modbus').first);
        await settle(tester);
        await shot(tester, '0${i + 2}b_links_modbus');
      }
    }

    // ---- errors (docs/design/specs/errors.md) -------------------------------
    // Real refusals of the demo broker; nothing on it is changed.
    final site = store.state.site.name;
    String said() {
      final e = store.state.problems.items.firstOrNull;
      return e == null
          ? 'nothing'
          : '${e.kind.name}/${e.status?.name} "${e.title}" [${e.where}] '
                '"${e.message}"';
    }

    // A call the user started, refused on its argument: the dialog.
    final mock = 'wy/$site/downstream/mock';
    await store.dispatchAndWait(InvokeNodeAction(mock, 'count', {'n': -1}));
    await settle(tester, 1200);
    debugPrint('errors: count n=-1 → ${said()}');
    if (find.byType(ErrorDialog).evaluate().isNotEmpty) {
      await dialogShot(tester, '09a_error_dialog');
      await tester.tap(find.byKey(const ValueKey('error-details')));
      await settle(tester, 400);
      await dialogShot(tester, '09b_error_dialog_details');
      // A second error while it is open: Problems only.
      final before = store.state.problems.items.length;
      await store.dispatchAndWait(
        InvokeNodeAction('wy/$site/downstream/no-such-link', 'ping'),
      );
      await settle(tester, 800);
      expect(find.byType(ErrorDialog), findsOneWidget);
      expect(store.state.problems.items.length, before + 1);
      debugPrint('errors: a missing key while a dialog is open → ${said()}');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, 600);
      expect(find.byType(ErrorDialog), findsNothing);
    }

    // The same missing key with nothing open: the Gone dialog.
    await store.dispatchAndWait(
      InvokeNodeAction('wy/$site/downstream/no-such-link', 'ping'),
    );
    await settle(tester, 1200);
    debugPrint('errors: a missing key → ${said()}');
    if (find.byType(ErrorDialog).evaluate().isNotEmpty) {
      await dialogShot(tester, '09c_error_gone');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, 600);
    }

    // Something Studio does on its own: a toast, then the drawer.
    await store.dispatchAndWait(
      RetrieveNodeDetailAction('wy/$site/downstream/no-such-link/nope'),
    );
    await store.dispatchAndWait(RetrieveLinksAction(quiet: true));
    await store.dispatchAndWait(
      _QuietRead('wy/$site/downstream/no-such-link/nope'),
    );
    await settle(tester, 800);
    if (find.byType(ErrorDialog).evaluate().isNotEmpty) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, 600);
    }
    debugPrint(
      'errors: quiet read → ${said()}; toasts '
      '${store.state.problems.toasts.length}, unread '
      '${store.state.problems.unread}',
    );
    expect(store.state.problems.toasts, isNotEmpty);
    expect(find.byType(ToastStack), findsOneWidget);
    await shot(tester, '09d_error_toast');
    await tester.tap(find.byKey(const ValueKey('problems-pill')));
    await settle(tester, 800);
    expect(find.byType(ProblemsDrawer), findsOneWidget);
    expect(store.state.problems.unread, 0);
    await shot(tester, '09e_problems');
    debugPrint('errors: overflow ${tester.takeException()}');
    await tester.tap(find.byKey(const ValueKey('problems-close')));
    await settle(tester, 400);
  }, skip: gateway.isEmpty);
}
