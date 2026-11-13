import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../view_alarm_list.dart';
import '../view_card.dart';
import '../view_lamp.dart';
import '../view_style.dart';
import '../view_symbol.dart';
import '../view_trend.dart';
import '../view_value.dart';
import 'bind.dart';
import 'schemas.dart';

/// The figures of [value] with [decimals]; a text as it is.
String figuresOf(Object? value, int? decimals) => switch (value) {
  null => '—',
  final num n => n.toStringAsFixed(decimals ?? (n is int ? 0 : 1)),
  true => '1',
  false => '0',
  _ => '$value',
};

int? _int(Object? v) => switch (v) {
  final num n => n.toInt(),
  _ => null,
};

/// The state of a number against the document's limits and the quality the
/// bridge wrote.
ViewState stateOf(
  double? value,
  Object? quality,
  Map<String, Object?> limits,
) {
  if (value == null || quality == 'none' || quality == 'bad') {
    return .off;
  }
  bool above(String name) {
    final l = numberOf(limits[name]);
    return l != null && value > l;
  }

  bool below(String name) {
    final l = numberOf(limits[name]);
    return l != null && value < l;
  }

  if (above('badAbove') || below('badBelow')) {
    return .alarm;
  }
  if (quality == 'uncertain' || above('warnAbove') || below('warnBelow')) {
    return .warn;
  }
  return .normal;
}

/// `Value`: one figure of a point. Unit and decimals fall back to the
/// point's `~meta`; the limits colour it by state.
final jsb.Schema valueSchema = part(
  {
    'label': jsb.S.string(),
    'value': boundValue,
    'unit': jsb.S.string(),
    'decimals': jsb.S.integer(),
    'size': sizeSchema,
    'warnAbove': jsb.S.number(),
    'warnBelow': jsb.S.number(),
    'badAbove': jsb.S.number(),
    'badBelow': jsb.S.number(),
  },
  ['value'],
);

final valueItem = CatalogItem(
  name: 'Value',
  dataSchema: valueSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    return ViewBind(
      dataContext: item.dataContext,
      props: [data['value'], ...metaOf(item.dataContext, data['value'])],
      builder: (context, v) {
        final number = v[0] is String ? null : numberOf(v[0]);
        final state = v[0] is String && v[3] != 'none'
            ? ViewState.normal
            : stateOf(number, v[3], data);
        final value = ViewValue(
          vm: ViewValueVm(
            label: data['label'] as String? ?? '',
            value: figuresOf(v[0], _int(data['decimals']) ?? _int(v[2])),
            unit: data['unit'] as String? ?? v[1]?.toString() ?? '',
            state: state,
            size: .of(data['size']),
            note: switch (v[3]) {
              'none' => S.current.viewsNoData,
              'bad' => S.current.viewsBadQuality,
              'uncertain' => S.current.viewsUncertain,
              _ => '',
            },
          ),
        );
        return ViewCardScope.inside(context) ? value : ViewCard(child: value);
      },
    );
  },
);

/// `Lamp`: a two-state point. `on` is a bool, or a number that is on above
/// `onAbove` (above zero without it).
final jsb.Schema lampSchema = part(
  {
    'label': jsb.S.string(),
    'on': boundValue,
    'onAbove': jsb.S.number(),
    'onText': jsb.S.string(),
    'offText': jsb.S.string(),
  },
  ['on'],
);

final lampItem = CatalogItem(
  name: 'Lamp',
  dataSchema: lampSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    return ViewBind(
      dataContext: item.dataContext,
      props: [data['on'], metaOf(item.dataContext, data['on'])[2]],
      builder: (context, v) {
        final above = numberOf(data['onAbove']);
        final on = v[1] == 'none' || v[1] == 'bad'
            ? null
            : above != null
            ? switch (numberOf(v[0])) {
                final n? => n > above,
                null => null,
              }
            : boolOf(v[0]);
        return ViewLamp(
          vm: ViewLampVm(
            label: data['label'] as String? ?? '',
            text: switch (on) {
              true => data['onText'] as String? ?? '',
              false => data['offText'] as String? ?? '',
              null => S.current.viewsNoData,
            },
            state: on == null
                ? .off
                : on
                ? .on
                : .normal,
          ),
        );
      },
    );
  },
);

/// `Symbol`: a process symbol coloured by its state.
final jsb.Schema symbolSchema = part(
  {
    'kind': jsb.S.string(enumValues: ['pump']),
    'running': boundBool,
    'fault': boundBool,
    'value': boundValue,
    'unit': jsb.S.string(),
    'size': sizeSchema,
  },
  ['kind'],
);

final symbolItem = CatalogItem(
  name: 'Symbol',
  dataSchema: symbolSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    return ViewBind(
      dataContext: item.dataContext,
      props: [
        data['running'],
        data['fault'],
        data['value'],
        ...metaOf(item.dataContext, data['value']).take(2),
      ],
      builder: (context, v) {
        final running = boolOf(v[0]);
        final fault = boolOf(v[1]) ?? false;
        final s = S.current;
        final (state, word) = fault
            ? (ViewState.alarm, s.viewsFault)
            : switch (running) {
                true => (ViewState.on, s.viewsRunning),
                false => (ViewState.off, s.viewsStopped),
                null => (ViewState.off, s.viewsNoData),
              };
        return ViewSymbol(
          vm: ViewSymbolVm(
            kind: data['kind'] as String? ?? '',
            state: state,
            word: word,
            value: v[2] == null ? '' : figuresOf(v[2], _int(v[4])),
            unit: data['unit'] as String? ?? v[3]?.toString() ?? '',
            size: .of(data['size']),
          ),
        );
      },
    );
  },
);

/// `1h`, `24h`, `15m`, `30s` as a duration; an hour for anything else.
Duration rangeOf(Object? text) {
  final m = RegExp(r'^(\d+)([smhd])$').firstMatch('$text');
  final n = int.tryParse(m?.group(1) ?? '') ?? 1;
  return switch (m?.group(2)) {
    's' => Duration(seconds: n),
    'm' => Duration(minutes: n),
    'd' => Duration(days: n),
    _ => Duration(hours: n),
  };
}

/// `Trend`: the series over time, drawn by Studio's own trend.
final jsb.Schema trendSchema = part(
  {
    'title': jsb.S.string(),
    'range': jsb.S.string(),
    'series': jsb.S.list(items: pathSchema),
  },
  ['series'],
);

final trendItem = CatalogItem(
  name: 'Trend',
  dataSchema: trendSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final series = [
      for (final s in data['series'] as List<Object?>? ?? const [])
        if (pathOf(s) != null) s,
    ];
    return ViewBind(
      dataContext: item.dataContext,
      props: [
        for (final s in series) ...[s, ...metaOf(item.dataContext, s)],
      ],
      builder: (context, v) => _carded(
        context,
        ViewTrend(
          vm: ViewTrendVm(
            title: data['title'] as String? ?? '',
            range: rangeOf(data['range']),
            series: [
              for (final (i, s) in series.indexed)
                ViewTrendSeriesVm(
                  name: (keyOfProp(item.dataContext, s) ?? '')
                      .split('/')
                      .reversed
                      .take(2)
                      .toList()
                      .reversed
                      .join('/'),
                  value: v[i * 4 + 3] == 'none' || v[i * 4 + 3] == 'bad'
                      ? null
                      : numberOf(v[i * 4]),
                  unit: v[i * 4 + 1]?.toString() ?? '',
                  decimals: _int(v[i * 4 + 2]) ?? 1,
                  uncertain: v[i * 4 + 3] == 'uncertain',
                ),
            ],
          ),
        ),
      ),
    );
  },
);

/// [child] in a card of its own unless it already sits in one.
Widget _carded(BuildContext context, Widget child) =>
    ViewCardScope.inside(context) ? child : ViewCard(child: child);

/// `AlarmList`: the active alarms of a source. A placeholder in the
/// prototype: the title and the empty line.
final jsb.Schema alarmListSchema = part({
  'title': jsb.S.string(),
  'source': jsb.S.string(),
  'filter': jsb.S.string(),
  'limit': jsb.S.integer(),
});

final alarmListItem = CatalogItem(
  name: 'AlarmList',
  dataSchema: alarmListSchema,
  widgetBuilder: (item) => Builder(
    builder: (context) {
      final list = ViewAlarmList(
        title: (item.data as JsonMap)['title'] as String? ?? '',
      );
      return ViewCardScope.inside(context) ? list : ViewCard(child: list);
    },
  ),
);
