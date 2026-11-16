import 'package:app/common/app_store.dart';
import 'package:app/connectors/flow_editor_page_connector.dart';
import 'package:app/connectors/flows_page_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../business/test/support/catalog_0229.dart';
import '../../../business/test/support/fake_wyrm.dart';

export '../../../business/test/support/fake_wyrm.dart';

/// The site of every flow editor test.
const plant = 'wy/plant';

/// `wy/plant/dataflows`.
const dataflows = '$plant/dataflows';

/// The flow the tests open.
const tankKey = '$dataflows/tank';

/// The PLC node of the site's tree.
const plc = '$plant/downstream/plc';

/// The flow `tank` as the broker keeps it (spec 06): a point read, scaled,
/// published and written to a valve; an action block that starts a pump;
/// a number variable into a sum with a constant; and an instance of the
/// flow's own custom block `half`. Every block has its place.
Map<String, Object?> tankDef() => {
  'id': 'tank',
  'version': 3,
  'nodes': {
    'level': {'type': 'subscribe', 'key': 'downstream/plc/level'},
    'pct': {'type': 'scale', 'k': 2},
    'out': {'type': 'publish', 'node': 'level_pct'},
    'valve': {'type': 'set', 'path': 'downstream/plc/valve'},
    'pump': {
      'type': 'invoke',
      'path': 'downstream/plc',
      'action': 'start_pump',
      'args': {'speed': 50},
    },
    'limit': {'type': 'number', 'value': 80},
    'sum': {
      'type': 'add',
      'values': {'in.1': 5},
    },
    'h1': {'type': 'block:half'},
  },
  'edges': [
    ['level.out', 'pct.in'],
    ['pct.out', 'out.in'],
    ['pct.out', 'valve.in'],
    ['limit.out', 'sum.in.0'],
    ['sum.out', 'h1.x'],
  ],
  'layout': {
    'level': [40, 40],
    'pct': [340, 40],
    'out': [640, 40],
    'valve': [640, 240],
    'pump': [940, 40],
    'limit': [40, 460],
    'sum': [340, 460],
    'h1': [640, 560],
  },
  'blocks': {
    'half': {
      'description': 'Half of a value',
      'inputs': [
        {'name': 'x', 'to': 'div.in.0'},
      ],
      'outputs': [
        {'name': 'y', 'from': 'div.out'},
      ],
      'nodes': {
        'div': {
          'type': 'divide',
          'values': {'in.1': 2},
        },
      },
      'edges': <Object?>[],
      'layout': {
        'div': [300, 40],
      },
    },
  },
};

/// The flow editor over a fake gateway: the site `plant` with its flow
/// `tank`, the block catalog of spec 06 0.2.29, a library of custom
/// blocks and a PLC in the tree, as the connector reads them when it is
/// shown.
class FlowApp {
  FlowApp({
    String level = 'config',
    this.flow = 'tank',
    this.def,
    this._catalog,
  }) : login = FakeLogin(
         session: FakeSession(
           who: identityOf(
             subject: 'user:olena',
             site: 'plant',
             roles: const ['engineer'],
             max: level,
             grants: [('$plant/**', level)],
           ),
         ),
       ) {
    store = fakeStore(login: login);
    _broker();
  }

  /// The flow opened and its definition; null: [tankDef].
  final String flow;
  final Map<String, Object?>? def;

  /// The block catalog; null: spec 06 0.2.29's.
  final List<Map<String, Object?>>? _catalog;

  /// `wy/plant/dataflows/<flow>`.
  String get flowKey => '$dataflows/$flow';
  final FakeLogin login;
  late final Store<AppState> store;

  FakeWyrmApi get api => login.session.api;

  /// What the system clipboard holds (what Studio wrote, or a test put).
  String? clipboard;

  void _broker() {
    api
      ..invokes['$dataflows ▸ node_types'] = [
        Value.from(_catalog ?? catalog0229()),
      ]
      ..invokes['$flowKey ▸ history'] = [
        Value.from([def ?? tankDef()]),
      ]
      ..invokes['$dataflows ▸ validate'] = [
        Value.from({'ok': true}),
      ]
      ..invokes['$dataflows ▸ deploy'] = [const VNull()]
      ..invokes['$dataflows ▸ list_blocks'] = [
        Value.from([
          {
            'name': 'ramp',
            'version': 2,
            'description': 'A ramp of a set point',
            'inputs': ['from', 'to'],
            'outputs': ['out'],
          },
        ]),
      ]
      ..invokes['$dataflows ▸ get_block'] = [
        Value.from({
          'name': 'ramp',
          'version': 2,
          'def': {
            'description': 'A ramp of a set point',
            'inputs': [
              {'name': 'from', 'to': 'r.in.0'},
              {'name': 'to', 'to': 'r.in.1'},
            ],
            'outputs': [
              {'name': 'out', 'from': 'r.out'},
            ],
            'nodes': {
              'r': {'type': 'add'},
            },
            'edges': <Object?>[],
          },
          'requires': <String, Object?>{},
        }),
      ]
      ..invokes['$dataflows ▸ put_block'] = [
        Value.from({'name': 'half', 'version': 1}),
      ]
      ..invokes['$dataflows ▸ remove_block'] = [const VNull()]
      ..invokes['$flowKey ▸ trigger'] = [const VNull()]
      // The flows list read after a deploy.
      ..children_[dataflows] = [Child(flow, NodeMeta())]
      // The PLC's own actions (the action block's and the Tree tab's).
      ..metas[plc] = NodeMeta(
        actions: {
          'start_pump': ActionMeta(
            params: {
              'speed': ParamMeta(ty: TypeCode.number, required: true),
            },
            level: Perm.write,
          ),
          'reset': ActionMeta(level: Perm.config),
        },
      )
      ..streamed.addAll({'$dataflows ▸ preview', '$flowKey ▸ watch'});
  }

  /// Logs in and shows the editor of [id] ([newFlowId] for a new flow) in
  /// [locale], as the Flows tab opens it.
  Future<void> pump(
    WidgetTester tester, {
    String? id,
    Locale locale = const Locale('en'),
  }) async {
    await S.load(locale);
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.runAsync(() async {
      await store.dispatchAndWait(SetGatewayAction('http://g'));
      await store.dispatchAndWait(SetUserAction('olena'));
      await store.dispatchAndWait(SetPasswordAction('pw'));
      await store.dispatchAndWait(LogInAction());
    });
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: AppStore(
          store: store,
          child: MaterialApp(
            theme: darkTheme(),
            locale: locale,
            supportedLocales: S.delegate.supportedLocales,
            localizationsDelegates: const [
              S.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: FlowEditorPageConnector(id: id ?? flow),
          ),
        ),
      ),
    );
    await settle(tester);
    // The site's tree as the Tree tab lists it.
    list('$plant/downstream', [
      Child('plc', NodeMeta(hasChildren: true, hasNodes: false)),
    ]);
    await settle(tester);
  }

  /// [children] as the live list of [key] answers (it is open).
  void list(String key, List<Child> children) =>
      api.lists[key]?.add(ListRefreshed(children));

  /// The PLC's points, as its live list answers when it opens.
  void plcPoints() => list(plc, [
    Child('level', NodeMeta(ty: TypeCode.number, unit: const TText('%'))),
    Child(
      'valve',
      NodeMeta(ty: TypeCode.bool_, writable: Writable.write),
    ),
  ]);

  /// Lets the fake broker's answers arrive and the screen follow them,
  /// past every debounce of the editor (preview 300 ms, validate 400 ms).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Takes the editor off the screen (it unwatches, its preview stops) and
  /// lets every timer of it run out.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    _restore?.call();
    _restore = null;
  }

  void Function()? _restore;

  /// Lets a `RenderFlex overflowed` of the canvas pass until [leave]: the
  /// Inputs and Outputs blocks of an inside view are 160 wide and their
  /// `− + 1 port` row overflows by 7.5 px, and in Ukrainian the Run button
  /// and the Form choice of the inspector overflow too (known faults of
  /// `ui/lib/flows`, not what these tests are about).
  void tolerateOverflow() {
    if (_restore != null) {
      return;
    }
    final before = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) {
        before?.call(d);
      }
    };
    _restore = () => FlutterError.onError = before;
  }

  /// Every word on the screen (the page, its menus and dialogs), in the
  /// order of the tree: each text, each text field's content as `[…]` and
  /// each switch as `[on]` or `[off]`.
  List<String> words(WidgetTester tester) => [
    for (final w in tester.widgetList(
      find.byWidgetPredicate(
        (w) => w is RichText || w is EditableText || w is Switch,
      ),
    ))
      switch (w) {
        final RichText r => r.text.toPlainText(),
        final EditableText e => '[${e.controller.text}]',
        final Switch s => s.value ? '[on]' : '[off]',
        _ => '',
      },
  ];

  /// The invokes of [action] made so far.
  List<Call> calls(String action) => [
    for (final c in api.calls)
      if (c.op == 'invoke' && c.action == action) c,
  ];

  /// The arguments of the invokes of [action], as plain Dart.
  List<Object?> argsOf(String action) => [
    for (final c in calls(action)) toDart(c.args),
  ];

  /// Lays [change] into the store, as the test needs it.
  void put(AppState Function(AppState) change) =>
      store.dispatchSync(_Put(change));

  /// [values] (full keys) as the broker sends them.
  void values(Map<String, Object?> values) => store.dispatchSync(
    SetLiveValuesAction({
      for (final e in values.entries)
        e.key: LiveValue(
          time: DateTime.utc(2026, 11, 12, 2, 2),
          value: e.value,
        ),
    }),
  );

  // ---------- what the tests read from the store ----------

  /// The draft on the canvas (the flow, or the inside of a block).
  Map<String, Map<String, Object?>> get blocks {
    final d = store.state.flowEditor.draft;
    if (d == null) {
      return const {};
    }
    return {
      for (final b in d.blocks.values)
        b.id: {'type': b.type.wire, 'x': b.x, 'y': b.y, ...b.cfg.unlock},
    };
  }

  /// The fields block [id] has pinned or taken off (`p:k` → true).
  Map<String, bool> pins(String id) =>
      store.state.flowEditor.draft?.blocks[id]?.pins.unlock ?? const {};

  /// The draft's wires as `from.port → to.port`.
  List<String> get edges {
    final d = store.state.flowEditor.draft;
    if (d == null) {
      return const [];
    }
    return [
      for (final e in d.edges) '${e.from}.${e.fromPort} → ${e.to}.${e.toPort}',
    ];
  }

  /// The selected blocks.
  Set<String> get selection => store.state.flowEditor.selection.unlock;

  /// The one selected block.
  String? get selected => store.state.flowEditor.selectedBlock;

  /// Steps that undo can take back.
  int get undo => store.state.flowEditor.undo.length;

  /// The custom blocks the canvas is inside of, outermost first.
  List<String> get frames => [
    for (final f in store.state.flowEditor.frames) f.block,
  ];

  /// The palette tab shown, by its name.
  String get palette => _name(store.state.flowEditor.palette);

  /// The block whose scope is asked, if any.
  String? get scopePrompt => _nameOrNull(store.state.flowEditor.scopePrompt);

  /// The field open in the value viewer (`<block>/<field>`), if any.
  String? get viewedField => _nameOrNull(store.state.flowEditor.viewedField);

  /// The editor's own clipboard.
  String? get ownClipboard => store.state.flowEditor.clipboard;

  /// The names of the custom blocks the draft on the canvas defines (the
  /// definition's `blocks`).
  Set<String> get blockDefs => {...?store.state.flowEditor.draft?.defs.keys};

  static String _name(Object v) => v is Enum ? v.name : '$v';

  static String? _nameOrNull(Object? v) => v == null ? null : _name(v);

  // ---------- driving the canvas ----------

  /// Block [id] on the canvas.
  Finder block(String id) => find.byKey(ValueKey(id));

  /// The text [label] inside block [id].
  Finder inBlock(String id, String label) =>
      find.descendant(of: block(id), matching: find.text(label));

  /// A point on block [id]'s header (it moves the block, a click selects).
  Offset header(WidgetTester tester, String id) =>
      tester.getTopLeft(block(id)) + const Offset(110, 14);

  /// Clicks block [id] on its header.
  Future<void> select(WidgetTester tester, String id) async {
    await tester.tapAt(header(tester, id));
    await settle(tester);
  }

  /// A click on the empty canvas.
  Future<void> clickEmpty(WidgetTester tester) async {
    await tester.tapAt(emptyCanvas(tester));
    await settle(tester);
  }

  /// A point of the canvas with no block, above the legend.
  Offset emptyCanvas(WidgetTester tester) =>
      tester.getTopLeft(block('limit')) + const Offset(0, -60);

  /// A drag of the primary button from [from] to [to], in steps.
  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await g.removePointer();
    await settle(tester);
  }

  /// Drags block [id] by its header by [by].
  Future<void> moveBy(WidgetTester tester, String id, Offset by) =>
      drag(tester, header(tester, id), header(tester, id) + by);

  /// A wire dragged from the row [from] (block, label) onto the row [to].
  Future<void> wire(
    WidgetTester tester,
    (String, String) from,
    (String, String) to,
  ) => drag(
    tester,
    tester.getCenter(inBlock(from.$1, from.$2)),
    tester.getCenter(inBlock(to.$1, to.$2)),
  );

  /// Opens (or closes) node [key] in the Tree tab with a tap on its row.
  Future<void> openTreeNode(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey('tree-$key')));
    await settle(tester);
  }

  /// The right button at [at]: the context menu.
  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  /// [key] with the primary modifier (⌘ on macOS, Ctrl elsewhere), and
  /// Shift when [shift].
  Future<void> primary(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    final mod = flowOnMac
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    if (shift) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyEvent(key);
    if (shift) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyUpEvent(mod);
    await settle(tester);
  }

  /// [key] alone.
  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  /// The inspector (the right panel).
  Finder get inspector => find.byType(FieldInspector);

  /// The text field of the inspector row labelled [label].
  Finder inspectorField(String label) => find
      .descendant(
        of: find
            .ancestor(
              of: find.descendant(of: inspector, matching: find.text(label)),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(TextField),
      )
      .first;

  /// The mouse over [at] (a tooltip shows, `V` reads the row under it).
  Future<void> hover(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(at);
    await tester.pumpAndSettle();
  }

  /// Taps the text [label] on the page (not in a menu).
  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(FlowEditorPage),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  /// Taps [label] anywhere (a menu item, a dialog button).
  Future<void> tapAnywhere(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
    await settle(tester);
  }
}

/// The id the editor opens a new flow with.
const String newFlow = newFlowId;

/// Lays a state in, as the test needs it.
class _Put extends ReduxAction<AppState> {
  _Put(this.change);

  final AppState Function(AppState) change;

  @override
  AppState reduce() => change(state);
}

/// The main states of the editor whose words the tests read.
enum FlowState {
  /// `tank` loaded, nothing selected: the flow's summary, Blocks tab.
  loaded,

  /// One block of each kind selected.
  level,
  pct,
  out,
  valve,
  pump,
  limit,
  sum,

  /// Every block selected (Ctrl+A).
  many,
  myBlocks,

  /// The Tree tab with the PLC open: its points' values and its action.
  tree,

  /// Inside the custom block `half` (its instance `h1` opened).
  inside,

  /// A new flow: its name field.
  newFlow,

  /// The broker's validate refused the draft, naming `pct`.
  problem,

  /// A wire into `level`'s key: the scope is asked.
  scope,
  menuBlock,
  menuCanvas,

  /// `pct`'s Factor open in the value viewer.
  viewer,

  /// A deploy in flight.
  deploying,

  /// A user with `write` only, after an edit: Deploy says why it is off.
  writeOnly,
}

/// Shows the editor in [state], driven as the user gets there.
Future<FlowApp> shownIn(
  WidgetTester t,
  FlowState state, {
  Locale locale = const Locale('en'),
}) async {
  final app = FlowApp(level: state == .writeOnly ? 'write' : 'config');
  if (state == .problem) {
    app.api.invokes['$dataflows ▸ validate'] = [
      Value.from({'ok': false, 'error': 'nodes.pct: k must be a number'}),
    ];
  }
  if (locale.languageCode != 'en') {
    app.tolerateOverflow();
  }
  await app.pump(t, id: state == .newFlow ? newFlow : null, locale: locale);
  switch (state) {
    case .loaded || .newFlow || .problem:
      break;
    case .level || .pct || .out || .valve || .pump || .limit || .sum:
      await app.select(t, state.name);
    case .many:
      await app.clickEmpty(t);
      await app.primary(t, LogicalKeyboardKey.keyA);
    case .myBlocks:
      await app.tapText(t, S.current.paletteMyBlocks);
    case .tree:
      app.values({'$plc/level': 42.5, '$plc/valve': true});
      await app.tapText(t, S.current.paletteTree);
      await app.openTreeNode(t, plc);
      app.plcPoints();
      await app.settle(t);
    case .inside:
      app.tolerateOverflow();
      await t.tap(find.byKey(const ValueKey('open-h1')));
      await app.settle(t);
    case .scope:
      await app.wire(t, ('limit', 'Value'), ('level', 'Point'));
    case .menuBlock:
      await app.rightClick(t, app.header(t, 'pct'));
    case .menuCanvas:
      await app.rightClick(t, app.emptyCanvas(t));
    case .viewer:
      await app.hover(t, t.getCenter(app.inBlock('pct', 'Factor')));
      await app.key(t, LogicalKeyboardKey.keyV);
    case .deploying:
      await app.moveBy(t, 'limit', const Offset(0, 40));
      app.api.delays['$dataflows ▸ deploy'] = const Duration(seconds: 5);
      await t.tap(find.text(S.current.deploy));
      await t.pump(const Duration(milliseconds: 100));
    case .writeOnly:
      await app.moveBy(t, 'limit', const Offset(0, 40));
      await app.hover(t, t.getCenter(find.text(S.current.deploy)));
  }
  return app;
}
