import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/theme/common.dart';
import 'package:ui/views/catalog/bind.dart';
import 'package:ui/views/catalog/wyrm_catalog.dart';
import 'package:ui/views/view_card.dart';
import 'package:ui/views/view_lamp.dart';
import 'package:ui/views/view_placeholder.dart';
import 'package:ui/views/view_project_shell.dart';
import 'package:ui/views/view_slider.dart';
import 'package:ui/views/view_style.dart';
import 'package:ui/views/view_surface.dart';
import 'package:ui/views/view_symbol.dart';
import 'package:ui/views/view_trend.dart';

const _sim = 'wy/plant/downstream/bacnet/sim';
const _cpu = 'wy/plant/downstream/s7/plc1/cpu';
const _plc = 'wy/plant/downstream/modbus/plc1';

/// The lines of a sample as Studio hands them to the surface: the version
/// genui reads, and [params] filled in.
List<String> _lines(String file, [Map<String, String> params = const {}]) {
  final dir = Directory('../docs/design/genui').existsSync()
      ? '../docs/design/genui'
      : 'docs/design/genui';
  var text = File('$dir/$file').readAsStringSync();
  for (final e in params.entries) {
    text = text.replaceAll('"{${e.key}}', '"/${e.value}');
  }
  return [
    for (final line in const LineSplitter().convert(text))
      if (line.trim().isNotEmpty)
        line.replaceFirst(
          RegExp(r'"version":\s*"v0\.9\.1"'),
          '"version":"v0.9"',
        ),
  ];
}

String _esc(String key) => key.replaceAll('~', '~0').replaceAll('/', '~1');

/// What the bridge writes for demo-plant with one BACnet device.
Map<String, Object?> _plant({double temp = 21.5, double sp = 20}) => {
  '/$_cpu/temp': temp,
  '/$_cpu/counter': 256,
  '/$_sim/d1/temp': 21.2,
  '/$_sim/d1/sp': sp,
  '/$_sim/~children/d1/\$name': 'd1',
  '/$_sim/~children/d1/\$key': '$_sim/d1',
  '/$_sim/~children/d1/temp': 21.2,
  '/$_sim/~children/d1/sp': sp,
  '/~meta/${_esc('$_cpu/temp')}/unit': '°C',
};

TrendFormat _format() => TrendFormat(
  locale: 'test',
  clock: (t) => '12:00',
  clockSeconds: (t) => '12:00:00',
  day: (t) => 'Thu 12 Nov',
  weekday: (t) => 'Thu',
);

final _fired = <ViewActionVm>[];

/// One theme for a whole test: a new `ThemeData` per pump would animate and
/// rebuild everything that reads it.
final ThemeData _dark = darkTheme();

Widget _app(
  List<String> messages,
  Map<String, Object?> data, {
  ViewDensity density = ViewDensity.desktop,
  ThemeData? theme,
  String surfaceId = 'demo-plant',
  bool shell = false,
  bool confirm = true,
  GlobalKey<ViewSurfaceState>? key,
}) {
  final surface = ViewSurface(
    key: key,
    surfaceId: surfaceId,
    messages: messages,
    data: data,
    density: density,
    format: _format(),
    onAction: _fired.add,
    confirm: (_, _) async => confirm,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? _dark,
    home: Scaffold(
      body: shell
          ? ViewProjectShell(
              vm: const ViewProjectVm(
                title: 'Plant · demo',
                clock: '12:00',
                crumbs: ['Overview'],
                rotation: 2,
                items: [
                  ViewNavItemVm(
                    id: 'overview',
                    label: 'Overview',
                    selected: true,
                    badge: 2,
                  ),
                  ViewNavItemVm(
                    id: '',
                    label: 'BACnet devices',
                    children: [
                      ViewNavItemVm(id: 'device?device=$_sim/d1', label: 'd1'),
                    ],
                  ),
                ],
              ),
              density: density,
              onItem: (_) {},
              onCrumb: (_) {},
              child: surface,
            )
          : surface,
    ),
  );
}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// Takes the surface off, so its trend's timer ends with the test.
Future<void> _end(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  setUpAll(() => S.load(const Locale('en')));
  setUp(_fired.clear);

  group('demo-plant with a fake bridge', () {
    const sizes = {
      ViewDensity.desktop: Size(1280, 900),
      ViewDensity.panel: Size(1024, 768),
      ViewDensity.phone: Size(390, 844),
      ViewDensity.kiosk: Size(1280, 800),
    };
    for (final (name, theme, colors) in [
      ('dark', darkTheme(), darkColors),
      ('light', lightTheme(), lightColors),
    ]) {
      for (final density in ViewDensity.values) {
        testWidgets('$name × ${density.name} follows theme and density', (
          tester,
        ) async {
          await _size(tester, sizes[density]!);
          await tester.pumpWidget(
            _app(
              _lines('demo-plant.a2ui.jsonl'),
              _plant(),
              density: density,
              theme: theme,
              shell: true,
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          // Every part is there, with the values the bridge wrote.
          expect(find.text('S7 temperature'), findsOneWidget);
          expect(find.text('21.5'), findsOneWidget);
          expect(find.text('°C'), findsWidgets);
          expect(find.text('256'), findsOneWidget);
          expect(find.byType(ViewTrend), findsOneWidget);
          expect(find.text('d1'), findsWidgets);
          expect(find.text('Reset S7 marker word'), findsOneWidget);
          expect(find.byType(ViewPlaceholder), findsNothing);

          // Density: the figures and the button are the density's.
          final figures = tester.widget<Text>(find.text('21.5'));
          expect(figures.style!.fontSize, density.value);
          expect(
            tester.getSize(find.byType(ViewSlider)).height,
            greaterThanOrEqualTo(density.button),
          );
          expect(
            tester
                .getSize(
                  find.ancestor(
                    of: find.text('Reset S7 marker word'),
                    matching: find.byType(Button),
                  ),
                )
                .height,
            density.button,
          );

          // Theme: a value in range is `text1`, the lamp that is off is
          // not lit, the card is `ground1` — the tokens of this theme.
          expect(figures.style!.color, colors.text1);
          final card = tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(ViewCard).first,
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(card.color, colors.ground1);
          expect(
            tester.widget<ViewLamp>(find.byType(ViewLamp)).vm.state,
            ViewState.normal,
          );

          // The menu takes the form of where it is shown.
          final overview = find.text('Overview');
          switch (density) {
            case .desktop:
              // A sidebar: the menu is left of the page, with its group.
              expect(find.text('BACNET DEVICES'), findsOneWidget);
              expect(
                tester.getTopLeft(overview.first).dx,
                lessThan(tester.getTopLeft(find.text('S7 temperature')).dx),
              );
            case .panel:
              // Tabs 52 high under the header.
              final tab = tester.getRect(overview.first);
              expect(tab.top, greaterThanOrEqualTo(density.header));
              expect(tab.bottom, lessThanOrEqualTo(density.header + 52));
            case .phone:
              // A bar at the bottom.
              expect(
                tester.getRect(overview.first).top,
                greaterThan(sizes[density]!.height - 56),
              );
            case .kiosk:
              // No menu: the page's title in the frame, and rotation dots.
              expect(find.text('BACNET DEVICES'), findsNothing);
              expect(overview, findsNothing);
          }
          // The badge of the page is drawn wherever the menu is.
          expect(find.text('2'), density == .kiosk ? findsNothing : findsOne);
          await _end(tester);
        });
      }
    }

    testWidgets('a value over its warn limit is `warn` in both themes', (
      tester,
    ) async {
      for (final (theme, colors) in [
        (darkTheme(), darkColors),
        (lightTheme(), lightColors),
      ]) {
        await tester.pumpWidget(
          _app(
            _lines('demo-plant.a2ui.jsonl'),
            _plant(temp: 31),
            theme: theme,
          ),
        );
        await tester.pump();

        expect(
          tester.widget<Text>(find.text('31.0')).style!.color,
          colors.warn,
        );
        await _end(tester);
      }
    });
  });

  group('genui without a model', () {
    testWidgets('a write rebuilds only the parts bound to its path', (
      tester,
    ) async {
      await _size(tester, const Size(1280, 900));
      final messages = _lines('demo-plant.a2ui.jsonl');
      await tester.pumpWidget(_app(messages, _plant()));
      await tester.pump();
      final subscriptions = viewBindSubscriptions;
      viewBindBuilds = 0;

      await tester.pumpWidget(_app(messages, _plant(temp: 22.5)));
      await tester.pump();

      expect(find.text('22.5'), findsWidgets);
      // `cpu/temp` is read by the Value and by the Trend: two binds build,
      // the other ten do not, and nothing subscribes again.
      expect(viewBindBuilds, 2);
      expect(viewBindSubscriptions, subscriptions);
      await _end(tester);
    });

    testWidgets('fifty writes a second cost one build of two parts each', (
      tester,
    ) async {
      await _size(tester, const Size(1280, 900));
      final messages = _lines('demo-plant.a2ui.jsonl');
      final key = GlobalKey<ViewSurfaceState>();
      await tester.pumpWidget(_app(messages, _plant(), key: key));
      await tester.pump();
      viewBindBuilds = 0;
      final writes = key.currentState!.writes;
      final watch = Stopwatch()..start();

      for (var i = 1; i <= 50; i++) {
        await tester.pumpWidget(
          _app(messages, _plant(temp: 21.5 + i / 100), key: key),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      watch.stop();

      expect(key.currentState!.writes - writes, 50);
      expect(viewBindBuilds, 100);
      // ignore: avoid_print, the figure goes into the brief's findings.
      print(
        'genui: 50 DataModel.update + frames in '
        '${watch.elapsedMilliseconds} ms '
        '(${(watch.elapsedMicroseconds / 50000).toStringAsFixed(2)} ms each)',
      );
      await _end(tester);
    });

    testWidgets('the template draws one card per child and follows the list', (
      tester,
    ) async {
      await _size(tester, const Size(1280, 900));
      final messages = _lines('demo-plant.a2ui.jsonl');
      await tester.pumpWidget(_app(messages, _plant()));
      await tester.pump();
      expect(find.byType(ViewSlider), findsOneWidget);

      final two = {
        ..._plant(),
        '/$_sim/~children/d2/\$name': 'd2',
        '/$_sim/~children/d2/\$key': '$_sim/d2',
        '/$_sim/~children/d2/temp': 26.0,
        '/$_sim/~children/d2/sp': 24.0,
      };
      await tester.pumpWidget(_app(messages, two));
      await tester.pump();
      expect(find.byType(ViewSlider), findsNWidgets(2));
      expect(find.text('d2'), findsOneWidget);
      // Relative paths read the instance's own values: d2 is above 25 °C.
      expect(
        tester
            .widgetList<ViewLamp>(find.byType(ViewLamp))
            .map((l) => l.vm.text),
        ['ok', 'warm'],
      );

      await tester.pumpWidget(_app(messages, _plant()));
      await tester.pump();
      expect(find.byType(ViewSlider), findsOneWidget);
      expect(find.text('d2'), findsNothing);
      await _end(tester);
    });

    testWidgets('an action is taken by Studio and never reaches genui', (
      tester,
    ) async {
      await _size(tester, const Size(1280, 900));
      final key = GlobalKey<ViewSurfaceState>();
      await tester.pumpWidget(
        _app(_lines('demo-plant.a2ui.jsonl'), _plant(), key: key),
      );
      await tester.pump();

      await tester.tap(find.text('Reset S7 marker word'));
      await tester.pump();
      expect(_fired.single.name, 'wyrm.set');
      expect(_fired.single.context, {'key': '$_cpu/mw', 'value': 0});

      // `$key` and `$value` are Studio's: the slider of the instance d1
      // writes d1's setpoint with the value let go of.
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pump();
      expect(_fired.last.name, 'wyrm.set');
      expect(_fired.last.context['key'], '$_sim/d1/sp');
      expect(_fired.last.context['value'], isA<double>());
      expect(_fired.last.context['value'], greaterThan(20));
      // No optimistic value: the slider shows the point's own again.
      expect(
        tester.widget<ViewSlider>(find.byType(ViewSlider)).vm.value,
        20,
      );

      // A tap on the card opens the device page with its key.
      await tester.tap(find.text('d1').first);
      await tester.pump();
      expect(_fired.last.name, 'wyrm.open');
      expect(_fired.last.context, {
        'page': 'device',
        'params': {'device': '$_sim/d1'},
      });

      // Nothing was submitted to the model side of genui.
      expect(key.currentState!.submitted, isEmpty);
      await _end(tester);
    });

    testWidgets('a write that is not confirmed is not made', (tester) async {
      await _size(tester, const Size(1280, 900));
      await tester.pumpWidget(
        _app(_lines('demo-plant.a2ui.jsonl'), _plant(), confirm: false),
      );
      await tester.pump();

      await tester.tap(find.text('Reset S7 marker word'));
      await tester.pump();

      expect(_fired, isEmpty);
      await _end(tester);
    });

    testWidgets("the confirm dialog asks with the document's own words", (
      tester,
    ) async {
      await _size(tester, const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme(),
          home: Scaffold(
            body: ViewSurface(
              surfaceId: 'demo-plant',
              messages: _lines('demo-plant.a2ui.jsonl'),
              data: _plant(),
              density: .desktop,
              format: _format(),
              onAction: _fired.add,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Reset S7 marker word'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Write 0 to MW10 on plc1?'), findsOneWidget);
      expect(_fired, isEmpty);

      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(_fired.single.context, {'key': '$_cpu/mw', 'value': 0});
      await _end(tester);
    });

    testWidgets("a page parameter and the page's own name", (tester) async {
      await _size(tester, const Size(1280, 900));
      await tester.pumpWidget(
        _app(
          _lines('demo-device.a2ui.jsonl', {'device': '$_sim/d1'}),
          {
            r'/$name': 'd1',
            '/$_sim/d1/temp': 21.2,
            '/$_sim/d1/sp': 20.0,
          },
          surfaceId: 'device',
        ),
      );
      await tester.pump();

      expect(find.text('d1'), findsOneWidget);
      // `size: l` is one and a half of the density's figures.
      expect(
        tester.widget<Text>(find.text('21.2')).style!.fontSize,
        ViewDensity.desktop.value * 1.5,
      );
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pump();
      expect(_fired.single.context['key'], '$_sim/d1/sp');
      await _end(tester);
    });
  });

  group('pump-station', () {
    Map<String, Object?> pumps() => {
      for (final (name, run, fault) in [
        ('p1', true, false),
        ('p2', false, true),
      ]) ...{
        '/$_plc/pumps/~children/$name/\$name': 'Pump ${name.substring(1)}',
        '/$_plc/pumps/~children/$name/\$key': '$_plc/pumps/$name',
        '/$_plc/pumps/~children/$name/run': run,
        '/$_plc/pumps/~children/$name/fault': fault,
        '/$_plc/pumps/~children/$name/speed': run ? 1450 : 0,
        '/$_plc/pumps/~children/$name/auto': true,
      },
      '/$_plc/flow_rate': 42.5,
    };

    testWidgets('symbols take their state colours, buttons their conditions', (
      tester,
    ) async {
      await _size(tester, const Size(1280, 1000));
      await tester.pumpWidget(
        _app(
          _lines('pump-station.a2ui.jsonl'),
          pumps(),
          surfaceId: 'pump-station',
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final symbols = tester
          .widgetList<ViewSymbol>(find.byType(ViewSymbol))
          .map((s) => (s.vm.state, s.vm.word))
          .toList();
      expect(symbols, [
        (ViewState.on, 'running'),
        (ViewState.alarm, 'fault'),
      ]);
      // A key without a value draws `—`, it does not break the surface.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('42.5'), findsOneWidget);
      expect(find.text('m³/h'), findsOneWidget);

      // `enabledWhen`: p1 runs, so only its Stop can be pressed.
      final buttons = tester.widgetList<Button>(find.byType(Button)).toList();
      expect(buttons.map((b) => b.onPressed != null), [
        false,
        true,
        true,
        false,
      ]);
      await tester.tap(find.text('Stop').first);
      await tester.pump();
      expect(_fired.single.name, 'wyrm.invoke');
      expect(_fired.single.context, {
        'key': '$_plc/pumps/p1',
        'action': 'stop',
      });
      await _end(tester);
    });

    testWidgets('the refine turn adds its parts and keeps the rest', (
      tester,
    ) async {
      await _size(tester, const Size(1280, 1000));
      final base = _lines('pump-station.a2ui.jsonl');
      final refined = [...base, ..._lines('pump-station.refine.a2ui.jsonl')];
      final key = GlobalKey<ViewSurfaceState>();
      await tester.pumpWidget(
        _app(base, pumps(), surfaceId: 'pump-station', key: key),
      );
      await tester.pump();
      final controller = key.currentState!.controller;
      final trend = tester.state(find.byType(ViewTrend));
      final subscriptions = viewBindSubscriptions;
      viewBindBuilds = 0;
      expect(find.byType(ViewLamp), findsNothing);

      await tester.pumpWidget(
        _app(refined, pumps(), surfaceId: 'pump-station', key: key),
      );
      await tester.pump();

      // The same surface: one controller, the trend keeps its state (its
      // samples), the new parts are there.
      expect(key.currentState!.controller, same(controller));
      expect(tester.state(find.byType(ViewTrend)), same(trend));
      expect(find.byType(ViewLamp), findsNWidgets(2));
      expect(
        tester.widget<ViewTrend>(find.byType(ViewTrend)).vm.series,
        hasLength(3),
      );
      // genui builds the whole surface again on `updateComponents` (every
      // bind builds), but only the changed and the new parts subscribe:
      // the trend (a third series), the new card and its two lamps.
      expect(viewBindSubscriptions - subscriptions, 4);
      expect(viewBindBuilds, greaterThan(3));
      // ignore: avoid_print, the figure goes into the brief's findings.
      print(
        'genui refine: $viewBindBuilds binds built, '
        '${viewBindSubscriptions - subscriptions} subscribed again',
      );
      await _end(tester);
    });
  });

  group('style contract', () {
    testWidgets('a theme and a colour in the document change nothing', (
      tester,
    ) async {
      await _size(tester, const Size(800, 600));
      final messages = [
        jsonEncode({
          'version': 'v0.9',
          'createSurface': {
            'surfaceId': 's',
            'catalogId': 'wyrm:views/0.1',
            'theme': {'primaryColor': '#FF00FF', 'font': 'Comic Sans MS'},
          },
        }),
        jsonEncode({
          'version': 'v0.9',
          'updateComponents': {
            'surfaceId': 's',
            'components': [
              {
                'id': 'root',
                'component': 'Column',
                'children': ['v', 'g', 'b'],
              },
              {
                'id': 'v',
                'component': 'Value',
                'label': 'T',
                'value': 1.5,
                'color': '#FF00FF',
                'fontSize': 80,
                'fontFamily': 'Comic Sans MS',
              },
              {'id': 'g', 'component': 'Gauge', 'value': 3},
              {
                'id': 'b',
                'component': 'Button',
                'label': 'Go',
                'color': '#FF00FF',
                'action': {
                  'event': {
                    'name': 'wyrm.set',
                    'context': {'key': 'wy/a/b', 'value': 1},
                  },
                },
              },
            ],
          },
        }),
      ];
      await tester.pumpWidget(_app(messages, const {}, surfaceId: 's'));
      await tester.pump();

      final figures = tester.widget<Text>(find.text('1.5')).style!;
      expect(figures.color, darkColors.text1);
      expect(figures.fontSize, ViewDensity.desktop.value);
      expect(figures.fontFamily, 'packages/ui/IBM Plex Mono');
      expect(
        tester
            .widget<Material>(
              find.descendant(
                of: find.byType(Button),
                matching: find.byType(Material),
              ),
            )
            .color,
        Colors.transparent,
      );
      // A part the catalog does not have is named, in Studio's own card.
      expect(find.text('Gauge is not in the catalog'), findsOneWidget);
      await _end(tester);
    });

    test('the schemas name no colour, font or pixel property', () {
      for (final MapEntry(key: part, value: schema)
          in wyrmCatalogSchemas().entries) {
        final properties =
            (schema as Map<String, Object?>)['properties']!
                as Map<String, Object?>;
        expect(schema['additionalProperties'], false, reason: part);
        for (final name in properties.keys) {
          expect(
            RegExp(
              'colou?r|font|width|height|padding|margin|style|url|html',
              caseSensitive: false,
            ).hasMatch(name),
            isFalse,
            reason: '$part.$name',
          );
        }
      }
      expect(wyrmCatalog().catalogId, wyrmCatalogId);
      expect(wyrmCatalog().items.map((i) => i.name), wyrmPartSchemas.keys);
    });

    test('state colours are the theme tokens, dark and light', () {
      for (final c in [darkColors, lightColors]) {
        expect(ViewState.normal.of(c), c.text1);
        expect(ViewState.on.of(c), c.good);
        expect(ViewState.warn.of(c), c.warn);
        expect(ViewState.alarm.of(c), c.bad);
        expect(ViewState.off.of(c), c.muted);
      }
    });

    test('the density comes from the width', () {
      expect(ViewDensity.forWidth(390), ViewDensity.phone);
      expect(ViewDensity.forWidth(1024), ViewDensity.panel);
      expect(ViewDensity.forWidth(1400), ViewDensity.desktop);
    });
  });
}
