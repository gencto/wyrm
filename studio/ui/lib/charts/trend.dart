import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'trend_scale.dart';

/// The quality of one row: `uncertain` runs are drawn dashed, `bad` rows are
/// never drawn (a gap).
enum TrendQuality { good, uncertain, bad }

/// The colour of a series, by the theme's tokens. By index the trend uses
/// [ember], [good], [warn], [badText], [text2] (spec §5).
enum TrendColor {
  ember,
  good,
  warn,
  badText,
  text2,
  text4;

  /// The colour of the series at [index].
  static TrendColor byIndex(int index) =>
      const [ember, good, warn, badText, text2][index % 5];

  Color of(AppColors c) => switch (this) {
    ember => c.ember,
    good => c.good,
    warn => c.warn,
    badText => c.badText,
    text2 => c.text2,
    text4 => c.text4,
  };
}

/// One row of a series: a time in µs since the epoch (UTC), its value
/// (null when it has none to draw), its quality, and the bucket's minimum
/// and maximum when they were read.
final class TrendSample extends Equatable {
  const TrendSample(this.t, this.v, {this.q = .good, this.lo, this.hi});

  final int t;
  final double? v;
  final TrendQuality q;
  final double? lo;
  final double? hi;

  @override
  List<Object?> get props => [t, v, q, lo, hi];
}

/// One line of a [Trend]. [samples] are the finest rows read for the window
/// (oldest first); [overview] the rows of the whole range for the brush.
final class TrendSeriesVm extends Equatable {
  const TrendSeriesVm({
    required this.id,
    required this.name,
    required this.color,
    this.label = '',
    this.unit = '',
    this.decimals = 1,
    this.samples = const [],
    this.overview = const [],
    this.hidden = false,
    this.locked = false,
    this.gapReason,
  });

  /// What [Trend.onSeriesToggle] reports.
  final String id;

  /// The key, in mono (`t1`, `boiler/t`).
  final String name;

  /// The point's name, beside the key.
  final String label;
  final TrendColor color;
  final String unit;

  /// The decimals of the point's values.
  final int decimals;
  final List<TrendSample> samples;
  final List<TrendSample> overview;

  /// Off in the legend: gone from the plot, the brush and the tooltip.
  final bool hidden;

  /// The viewer may not read it: a locked legend button, never drawn.
  final bool locked;

  /// Why a stretch with `bad` rows is empty (`comm_fail · device not
  /// reachable`), when the source knows; else *bad quality recorded*.
  final String? gapReason;

  @override
  List<Object?> get props => [
    id,
    name,
    label,
    color,
    unit,
    decimals,
    samples,
    overview,
    hidden,
    locked,
    gapReason,
  ];
}

/// How a [Trend] writes times: resolved where the locale lives (the
/// connector), used for the buckets only the widget knows.
final class TrendFormat extends Equatable {
  const TrendFormat({
    required this.locale,
    required this.clock,
    required this.clockSeconds,
    required this.day,
    required this.weekday,
  });

  /// `14:25`.
  final String Function(DateTime t) clock;

  /// `14:25:07`.
  final String Function(DateTime t) clockSeconds;

  /// `Wed 11 Nov`.
  final String Function(DateTime t) day;

  /// `Wed`.
  final String Function(DateTime t) weekday;

  /// The locale and zone the functions write in: two formats are equal
  /// when they write the same.
  final String locale;

  @override
  List<Object?> get props => [locale];
}

/// What [Trend] draws: its series, the whole range read (the brush), the
/// window shown (the plot), and what the plot's rows are (`15 min avg`,
/// `raw`). Times are µs since the epoch.
final class TrendVm extends Equatable {
  const TrendVm({
    required this.series,
    required this.rangeStart,
    required this.rangeEnd,
    required this.windowStart,
    required this.windowEnd,
    required this.rollup,
    required this.format,
    this.title = '',
    this.step,
    this.minWindow = 0,
    this.endsNow = false,
    this.live = false,
    this.following = true,
    this.loading = false,
    this.refining = false,
    this.card = true,
    this.legend = true,
    this.hint = true,
    this.plotHeight = 240,
    this.empty,
  });

  final List<TrendSeriesVm> series;
  final int rangeStart;
  final int rangeEnd;
  final int windowStart;
  final int windowEnd;

  /// What the plot's rows are, in the header and the tooltip.
  final String rollup;

  /// The bucket of the plot's rows; null for raw rows or live samples.
  final int? step;

  /// The narrowest window (12 buckets, 10 samples live).
  final int minWindow;

  /// The range ends now: the brush's last label is `now`.
  final bool endsNow;

  /// Live samples (no history): `Follow now` instead of `Reset zoom` once
  /// the window was moved away from now.
  final bool live;
  final bool following;

  /// The range is being read: a skeleton, no tooltip.
  final bool loading;

  /// A finer window is being read: the coarse line stays, a bar runs.
  final bool refining;

  /// The chart in words (`Supply and return temperature`).
  final String title;

  /// Drawn as its own card; off inside a card that has its own header.
  final bool card;

  /// The legend buttons in the header.
  final bool legend;

  /// The gesture hint under the brush (also hidden below 600 px).
  final bool hint;
  final double plotHeight;

  /// What the plot says when nothing was recorded; *No values recorded in
  /// this range.* when null.
  final String? empty;

  /// How times are written.
  final TrendFormat format;

  bool get zoomed => windowStart > rangeStart || windowEnd < rangeEnd;

  @override
  List<Object?> get props => [
    series,
    rangeStart,
    rangeEnd,
    windowStart,
    windowEnd,
    rollup,
    step,
    minWindow,
    endsNow,
    live,
    following,
    loading,
    refining,
    title,
    card,
    legend,
    hint,
    plotHeight,
    empty,
    format,
  ];
}

/// The time chart of Studio (board `Trend`, spec
/// `docs/design/specs/trend.md`): legend, the plot of the window with a
/// tooltip, drag-to-zoom and marker A, the time axis, and the brush over
/// the whole range. Hover, marker A and the drag band are its own state;
/// the window and the series shown go out through the callbacks.
class Trend extends StatefulWidget {
  const Trend({
    required this.vm,
    required this.onWindow,
    this.onSeriesToggle,
    this.onReset,
    this.onFollow,
    this.initialHover,
    this.initialMarker,
    super.key,
  });

  final TrendVm vm;

  /// The window the user chose (µs), already clamped to the range and to
  /// [TrendVm.minWindow].
  final void Function(int start, int end) onWindow;
  final ValueChanged<String>? onSeriesToggle;

  /// `Reset zoom` and a double-click: the whole range.
  final VoidCallback? onReset;

  /// `Follow now` (live).
  final VoidCallback? onFollow;

  /// The crosshair and marker A a frame starts with (µs).
  final int? initialHover;
  final int? initialMarker;

  @override
  State<Trend> createState() => _TrendState();
}

enum _Part { left, right, window, fresh }

class _TrendState extends State<Trend> {
  late final _hover = ValueNotifier<int?>(widget.initialHover);
  final _band = ValueNotifier<(double, double)?>(null);
  late int? _marker = widget.initialMarker;
  final _plotFocus = FocusNode(debugLabel: 'trend plot');
  final _leftFocus = FocusNode(debugLabel: 'trend window start');
  final _rightFocus = FocusNode(debugLabel: 'trend window end');
  late var _geo = _Geo(widget.vm);

  double? _downX;
  (DateTime, double)? _lastClick;
  double? _pinch;
  ({_Part part, int t0, int a0, int b0})? _drag;
  MouseCursor _brushCursor = SystemMouseCursors.precise;

  TrendVm get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    for (final f in [_leftFocus, _rightFocus]) {
      f.addListener(() => setState(() {}));
    }
  }

  @override
  void didUpdateWidget(Trend old) {
    super.didUpdateWidget(old);
    if (old.vm != vm) {
      _geo = _Geo(vm);
    }
  }

  @override
  void dispose() {
    _hover.dispose();
    _band.dispose();
    _plotFocus.dispose();
    _leftFocus.dispose();
    _rightFocus.dispose();
    super.dispose();
  }

  int get _span => math.max(1, vm.windowEnd - vm.windowStart);
  int get _range => math.max(1, vm.rangeEnd - vm.rangeStart);

  /// One bucket: the plot's step, the usual spacing, or a 300th.
  int get _bucket => vm.step ?? _geo.usual ?? math.max(1, _span ~/ 300);

  int _tAt(double x, double w) =>
      vm.windowStart + (_span * (x / w).clamp(0.0, 1.0)).round();
  double _xAt(int t, double w) => (t - vm.windowStart) / _span * w;

  int _snap(int t) => snap(
    t,
    step: vm.step,
    anchor: _geo.anchor,
    times: _geo.times,
  ).clamp(vm.windowStart, vm.windowEnd);

  void _window(int a, int b) {
    final (x, y) = clampWindow(
      a,
      b,
      vm.rangeStart,
      vm.rangeEnd,
      math.min(vm.minWindow, _range),
    );
    if (x != vm.windowStart || y != vm.windowEnd) {
      widget.onWindow(x, y);
    }
  }

  DateTime _dt(int t) => DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true);

  String _rangeText(int a, int b) {
    final f = vm.format;
    final da = _dt(a);
    final db = _dt(b);
    final same = f.day(da) == f.day(db);
    return '${f.weekday(da)} ${f.clock(da)} – '
        '${same ? '' : '${f.weekday(db)} '}${f.clock(db)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final rangeText = _rangeText(vm.windowStart, vm.windowEnd);
    final hasRight = _geo.right != null;
    // 44 px, or wider for a long unit (`6000 msg/s`).
    final yW = math
        .max(
          44,
          math.max(
            _labelWidth(_geo.left, _geo.leftUnit),
            hasRight ? _labelWidth(_geo.right!, _geo.rightUnit) : 0,
          ),
        )
        .toDouble();
    final side = yW + 8;
    final body = Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        _header(c, s, rangeText),
        Row(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            SizedBox(
              width: yW,
              height: vm.plotHeight,
              child: _yLabels(c, _geo.left, _geo.leftUnit, end: true),
            ),
            Expanded(child: _plot(c, s, rangeText)),
            if (hasRight)
              SizedBox(
                width: yW,
                height: vm.plotHeight,
                child: _yLabels(c, _geo.right!, _geo.rightUnit, end: false),
              ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(left: side, right: hasRight ? side : 0),
          child: SizedBox(
            height: 14,
            child: _ticks(_plotTicks(), mono(size: 11, color: c.text4)),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(right: hasRight ? side : 0, top: 4),
          child: Row(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              SizedBox(
                width: yW,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.trendAll,
                    textAlign: .right,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ),
              ),
              Expanded(child: _brush(c, s)),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: side, right: hasRight ? side : 0),
          child: SizedBox(
            height: 14,
            child: _ticks(_brushTicks(s), mono(size: 10, color: c.muted)),
          ),
        ),
        if (vm.hint)
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < 600
                ? const SizedBox.shrink()
                : Text(
                    s.trendHint,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
          ),
      ],
    );
    final content = DefaultTextStyle.merge(
      style: TextStyle(fontSize: 13, color: c.text1),
      child: body,
    );
    if (!vm.card) {
      return content;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: content,
    );
  }

  /// The width of the widest Y label of [axis] (the top one carries [unit]).
  double _labelWidth(TrendAxis axis, String unit) {
    var w = 0.0;
    final ticks = axis.ticks;
    for (final (i, v) in ticks.indexed) {
      final p = TextPainter(
        text: TextSpan(
          text: i == ticks.length - 1 && unit.isNotEmpty
              ? '${axis.label(v)} $unit'
              : axis.label(v),
          style: mono(size: 11),
        ),
        textDirection: .ltr,
      )..layout();
      w = math.max(w, p.width.ceilToDouble());
      p.dispose();
    }
    return w;
  }

  // ---------------------------------------------------------------- header

  Widget _header(AppColors c, S s, String rangeText) {
    Widget pill(String label, VoidCallback? onTap) => Material(
      color: c.emberTint,
      shape: StadiumBorder(side: BorderSide(color: c.emberLine)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: .center,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: c.emberSoft),
          ),
        ),
      ),
    );
    final right = Row(
      mainAxisSize: .min,
      spacing: 10,
      children: [
        Text.rich(
          TextSpan(
            text: rangeText,
            style: mono(size: 12, color: c.text2),
            children: [
              TextSpan(
                text: '  · ${vm.rollup}',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 12,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
        if (vm.live && !vm.following)
          pill(s.trendFollowNow, widget.onFollow)
        else if (vm.zoomed && !vm.loading)
          pill(s.trendResetZoom, widget.onReset),
      ],
    );
    if (!vm.legend) {
      return Align(alignment: .centerRight, child: right);
    }
    return Row(
      spacing: 16,
      children: [
        Expanded(
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: .center,
            children: [
              for (final x in vm.series) _legendButton(c, s, x),
              Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  SizedBox(
                    width: 14,
                    height: 10,
                    child: CustomPaint(
                      painter: _DashedBox(
                        fill: c.bad.withValues(alpha: 0.18),
                        line: c.bad,
                      ),
                    ),
                  ),
                  Text(
                    s.trendNoData,
                    style: TextStyle(fontSize: 12, color: c.bad),
                  ),
                ],
              ),
            ],
          ),
        ),
        right,
      ],
    );
  }

  Widget _legendButton(AppColors c, S s, TrendSeriesVm x) {
    final off = x.hidden || x.locked;
    final button = Opacity(
      opacity: off ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.segment,
          side: BorderSide(color: off ? c.line1 : c.line2),
        ),
        child: InkWell(
          onTap: x.locked || widget.onSeriesToggle == null
              ? null
              : () => widget.onSeriesToggle!(x.id),
          borderRadius: Radii.segment,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                if (x.locked)
                  Icon(Icons.lock_outline, size: 12, color: c.text4)
                else
                  Container(width: 16, height: 2, color: x.color.of(c)),
                Text(x.name, style: mono(size: 13, color: c.text1)),
                if (x.label.isNotEmpty)
                  Text(x.label, style: TextStyle(fontSize: 13, color: c.text4)),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      toggled: !off,
      child: Tooltip(
        message: x.locked ? s.trendLocked(x.name) : s.trendShowHide(x.name),
        child: button,
      ),
    );
  }

  // ------------------------------------------------------------------ axes

  Widget _yLabels(
    AppColors c,
    TrendAxis axis,
    String unit, {
    required bool end,
  }) {
    if (vm.loading || _geo.shown.isEmpty) {
      return const SizedBox.shrink();
    }
    final ticks = axis.ticks;
    return Stack(
      clipBehavior: .none,
      children: [
        for (final (i, v) in ticks.indexed)
          Positioned(
            top: axis.y(v, vm.plotHeight),
            left: end ? null : 0,
            right: end ? 0 : null,
            child: FractionalTranslation(
              translation: const Offset(0, -0.5),
              child: Text(
                i == ticks.length - 1 && unit.isNotEmpty
                    ? '${axis.label(v)} $unit'
                    : axis.label(v),
                style: mono(size: 11, color: c.text4),
              ),
            ),
          ),
      ],
    );
  }

  /// Five labels under the plot; the first and a midnight one carry the
  /// weekday.
  List<(double, String)> _plotTicks() {
    if (vm.loading) {
      return const [];
    }
    final f = vm.format;
    return [
      for (var k = 0; k < 5; k++)
        () {
          final t = _snap(vm.windowStart + (_span * k / 4).round());
          final d = _dt(t);
          final hm = f.clock(d);
          return (
            k / 4,
            k == 0 || hm == '00:00' ? '${f.weekday(d)} $hm' : hm,
          );
        }(),
    ];
  }

  List<(double, String)> _brushTicks(S s) => [
    for (var k = 0; k < 5; k++)
      (
        k / 4,
        k == 4 && vm.endsNow
            ? s.trendNow
            : vm.format.clock(
                _dt(
                  snap(
                    vm.rangeStart + (_range * k / 4).round(),
                    times: _geo.overviewTimes,
                  ),
                ),
              ),
      ),
  ];

  Widget _ticks(List<(double, String)> ticks, TextStyle style) => LayoutBuilder(
    builder: (context, box) => Stack(
      clipBehavior: .none,
      children: [
        for (final (i, (f, label)) in ticks.indexed)
          Positioned(
            left: f * box.maxWidth,
            top: 0,
            child: FractionalTranslation(
              translation: Offset(
                i == 0
                    ? 0
                    : i == ticks.length - 1
                    ? -1
                    : -0.5,
                0,
              ),
              child: Text(label, maxLines: 1, softWrap: false, style: style),
            ),
          ),
      ],
    ),
  );

  // ------------------------------------------------------------------ plot

  Widget _plot(AppColors c, S s, String rangeText) {
    final h = vm.plotHeight;
    if (vm.loading) {
      return SizedBox(height: h, child: _skeleton(c, bars: 3));
    }
    final message = _geo.empty
        ? vm.empty ?? s.trendNothing
        : _geo.shown.isEmpty
        ? s.trendAllHidden
        : null;
    return SizedBox(
      height: h,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final plot = Stack(
            clipBehavior: .none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PlotPainter(
                      geo: _geo,
                      start: vm.windowStart,
                      end: vm.windowEnd,
                      grid: c.ground3,
                      gap: c.bad,
                      colors: c,
                    ),
                  ),
                ),
              ),
              if (message != null)
                Center(
                  child: Text(
                    message,
                    style: TextStyle(fontSize: 13, color: c.text4),
                  ),
                ),
              if (vm.refining)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: c.ember,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              Positioned.fill(
                child: RepaintBoundary(child: _overlay(c, s, w, h)),
              ),
            ],
          );
          return Semantics(
            label: s.trendDescribe(vm.title, rangeText),
            image: true,
            child: Focus(
              focusNode: _plotFocus,
              onKeyEvent: (_, e) => _plotKey(e),
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                onExit: (_) {
                  _hover.value = null;
                  _band.value = null;
                },
                child: Listener(
                  behavior: .opaque,
                  onPointerHover: (e) => _hoverAt(e.localPosition.dx, w),
                  onPointerDown: (e) => _plotDown(e, w),
                  onPointerMove: (e) => _plotMove(e, w),
                  onPointerUp: (e) => _plotUp(e, w),
                  onPointerCancel: (_) {
                    _downX = null;
                    _band.value = null;
                  },
                  onPointerSignal: (e) => _plotWheel(e, w),
                  onPointerPanZoomStart: (_) => _pinch = 1,
                  onPointerPanZoomUpdate: (e) => _plotPinch(e, w),
                  child: plot,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _skeleton(AppColors c, {required int bars}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      mainAxisAlignment: .spaceEvenly,
      crossAxisAlignment: .start,
      children: [
        for (final f in [0.92, 0.7, 0.84].take(bars))
          FractionallySizedBox(
            widthFactor: f,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: c.ground4,
                borderRadius: Radii.chip,
              ),
            ),
          ),
      ],
    ),
  );

  void _hoverAt(double x, double w) {
    if (vm.loading || _geo.shown.isEmpty) {
      return;
    }
    _hover.value = _snap(_tAt(x, w));
  }

  void _plotDown(PointerDownEvent e, double w) {
    if (e.kind == .mouse && e.buttons != kPrimaryMouseButton) {
      return;
    }
    _downX = e.localPosition.dx;
    _band.value = null;
    _plotFocus.requestFocus();
    if (e.kind == .touch) {
      _hoverAt(e.localPosition.dx, w);
    }
  }

  void _plotMove(PointerMoveEvent e, double w) {
    _hoverAt(e.localPosition.dx, w);
    final d = _downX;
    if (d == null || w <= 0) {
      return;
    }
    final x = e.localPosition.dx.clamp(0.0, w);
    final l = math.min(d, x) / w;
    final r = math.max(d, x) / w;
    _band.value = r - l > 0.005 ? (l, r) : null;
  }

  void _plotUp(PointerUpEvent e, double w) {
    final d = _downX;
    _downX = null;
    final band = _band.value;
    _band.value = null;
    if (d == null || w <= 0) {
      return;
    }
    final x = e.localPosition.dx.clamp(0.0, w);
    if ((x - d).abs() / w > 0.01 && band != null) {
      _window(_tAt(band.$1 * w, w), _tAt(band.$2 * w, w));
      return;
    }
    if (_geo.shown.isEmpty) {
      return;
    }
    // A click: marker A here, or cleared within 4 px of it.
    final t = _snap(_tAt(x, w));
    final m = _marker;
    setState(
      () => _marker = m != null && (_xAt(m, w) - x).abs() <= 4 ? null : t,
    );
    final now = DateTime.now();
    final last = _lastClick;
    if (last != null &&
        now.difference(last.$1) < kDoubleTapTimeout &&
        (last.$2 - x).abs() < 4) {
      _lastClick = null;
      widget.onReset?.call();
    } else {
      _lastClick = (now, x);
    }
  }

  void _plotWheel(PointerSignalEvent e, double w) {
    if (e is! PointerScrollEvent || w <= 0 || e.scrollDelta.dy == 0) {
      return;
    }
    final at = _tAt(e.localPosition.dx, w);
    final (a, b) = zoomWindow(
      vm.windowStart,
      vm.windowEnd,
      at,
      e.scrollDelta.dy > 0 ? 1.25 : 0.8,
    );
    _window(a, b);
  }

  void _plotPinch(PointerPanZoomUpdateEvent e, double w) {
    final last = _pinch;
    if (last == null || e.scale <= 0 || w <= 0) {
      return;
    }
    _pinch = e.scale;
    final at = _tAt(e.localPosition.dx, w);
    final (a, b) = zoomWindow(vm.windowStart, vm.windowEnd, at, last / e.scale);
    _window(a, b);
  }

  KeyEventResult _plotKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return .ignored;
    }
    final h = _hover.value ?? _snap(vm.windowStart + _span ~/ 2);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _hover.value = _snap(h - _bucket);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _hover.value = _snap(h + _bucket);
    } else if (k == LogicalKeyboardKey.home) {
      _hover.value = _snap(vm.windowStart);
    } else if (k == LogicalKeyboardKey.end) {
      _hover.value = _snap(vm.windowEnd);
    } else if (k == LogicalKeyboardKey.escape) {
      _hover.value = null;
    } else {
      return .ignored;
    }
    return .handled;
  }

  // --------------------------------------------------------------- overlay

  Widget _overlay(AppColors c, S s, double w, double h) =>
      ValueListenableBuilder(
        valueListenable: _band,
        builder: (context, band, _) => ValueListenableBuilder(
          valueListenable: _hover,
          builder: (context, hover, _) {
            final m = _marker;
            final mx = m != null && m >= vm.windowStart && m <= vm.windowEnd
                ? _xAt(m, w)
                : null;
            final hx = hover == null ? null : _xAt(hover, w);
            return IgnorePointer(
              child: Stack(
                clipBehavior: .none,
                children: [
                  if (band != null)
                    Positioned(
                      left: band.$1 * w,
                      width: (band.$2 - band.$1) * w,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.ember.withValues(alpha: 0.12),
                          border: Border.symmetric(
                            vertical: BorderSide(color: c.ember),
                          ),
                        ),
                      ),
                    ),
                  if (mx != null) ...[
                    Positioned(
                      left: mx,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      child: CustomPaint(painter: _DashedLine(c.text3)),
                    ),
                    Positioned(
                      left: mx,
                      top: 4,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: Container(
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: .center,
                          decoration: BoxDecoration(
                            color: c.line2,
                            borderRadius: Radii.chip,
                          ),
                          child: Text(
                            s.trendMarker(vm.format.clock(_dt(m!))),
                            style: mono(size: 11, color: c.text1),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (hover != null && hx != null && _geo.shown.isNotEmpty)
                    ..._crosshair(c, s, hover, hx, w, h),
                ],
              ),
            );
          },
        ),
      );

  List<Widget> _crosshair(
    AppColors c,
    S s,
    int t,
    double x,
    double w,
    double h,
  ) {
    final rows = <Widget>[];
    final dots = <Widget>[];
    final words = <String>[];
    for (final x0 in _geo.shown) {
      final p = _geo.at(x0, t);
      final color = x0.color.of(c);
      if (p == null || !drawable(p)) {
        final reason = _geo.reasonAt(x0, t, s);
        rows.add(
          _row(
            c,
            color,
            x0.label.isEmpty ? x0.name : x0.label,
            s.trendNoData,
            '',
            c.bad,
            reason,
            c.bad,
          ),
        );
        words.add('${x0.name} ${s.trendNoData}, $reason');
        continue;
      }
      final axis = _geo.axisOf(x0);
      dots.add(
        Positioned(
          left: x - 6.5,
          top: axis.y(p.v!, h) - 6.5,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: c.ground1,
              shape: BoxShape.circle,
              border: .all(color: color, width: 2),
            ),
          ),
        ),
      );
      final v = p.v!.toStringAsFixed(x0.decimals);
      final String? sub;
      final Color subColor;
      if (p.q == .uncertain) {
        sub = s.trendUncertain;
        subColor = c.warn;
      } else if (p.lo != null && p.hi != null) {
        sub = s.trendMinMax(
          p.lo!.toStringAsFixed(x0.decimals),
          p.hi!.toStringAsFixed(x0.decimals),
        );
        subColor = c.muted;
      } else {
        sub = null;
        subColor = c.muted;
      }
      rows.add(
        _row(
          c,
          color,
          x0.label.isEmpty ? x0.name : x0.label,
          v,
          x0.unit,
          c.text1,
          sub,
          subColor,
        ),
      );
      words.add('${x0.name} $v ${x0.unit}${sub == null ? '' : ', $sub'}');
    }
    final delta = _delta(s, t);
    final f = vm.format;
    final d = _dt(t);
    final bucket = vm.step != null
        ? s.trendBucket(vm.rollup, f.clock(d), f.clock(_dt(t + vm.step!)))
        : vm.live
        ? '${vm.rollup} · ${f.clockSeconds(d)}'
        : s.trendRawAt(f.clockSeconds(d));
    final right = x > w * 0.6;
    final tip = Container(
      width: 232,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.ground2.withValues(alpha: 0.97),
        border: .all(color: c.line2),
        borderRadius: Radii.card,
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 8,
        children: [
          Row(
            crossAxisAlignment: .baseline,
            textBaseline: .alphabetic,
            spacing: 8,
            children: [
              Text(f.clock(d), style: mono(size: 13, color: c.text1)),
              Text(f.day(d), style: TextStyle(fontSize: 11, color: c.text4)),
              Expanded(
                child: Text(
                  bucket,
                  textAlign: .right,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 11, color: c.muted),
                ),
              ),
            ],
          ),
          ...rows,
          for (final line in delta)
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                line,
                style: TextStyle(fontSize: 11, color: c.text3),
              ),
            ),
          Text(
            _marker == null ? s.trendSetMarker : s.trendClearMarker,
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ],
      ),
    );
    return [
      Positioned(
        left: x,
        top: 0,
        bottom: 0,
        width: 1,
        child: ColoredBox(color: c.muted),
      ),
      ...dots,
      Positioned(
        top: 12,
        left: right ? null : x + 14,
        right: right ? w - x + 14 : null,
        child: Semantics(
          liveRegion: true,
          label: [
            '${f.clock(d)} ${f.day(d)}, $bucket',
            ...words,
            ...delta,
          ].join('. '),
          child: ExcludeSemantics(child: tip),
        ),
      ),
    ];
  }

  Widget _row(
    AppColors c,
    Color line,
    String label,
    String value,
    String unit,
    Color valueColor,
    String? sub,
    Color subColor,
  ) => Column(
    crossAxisAlignment: .stretch,
    mainAxisSize: .min,
    spacing: 2,
    children: [
      Row(
        spacing: 8,
        children: [
          Container(width: 10, height: 2, color: line),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(fontSize: 13, color: c.text3),
            ),
          ),
          Text(value, style: mono(size: 14, color: valueColor)),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 18),
            child: Text(unit, style: TextStyle(fontSize: 11, color: c.text4)),
          ),
        ],
      ),
      if (sub != null)
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(sub, style: TextStyle(fontSize: 11, color: subColor)),
        ),
    ],
  );

  /// `Δ from A (13:00): +2.4 °C t1 over 1 h 25 min`: the first shown series,
  /// or one line per series when their units differ.
  List<String> _delta(S s, int t) {
    final m = _marker;
    if (m == null) {
      return const [];
    }
    final units = {for (final x in _geo.shown) x.unit};
    final of = units.length > 1 ? _geo.shown : _geo.shown.take(1);
    final over = _duration(s, (t - m).abs());
    final at = vm.format.clock(_dt(m));
    return [
      for (final x in of)
        if ((_geo.at(x, m), _geo.at(x, t)) case (final a?, final b?)
            when drawable(a) && drawable(b))
          () {
            final dv = b.v! - a.v!;
            final sign = dv >= 0 ? '+' : '';
            final value =
                '$sign${dv.toStringAsFixed(x.decimals)}'
                '${x.unit.isEmpty ? '' : ' ${x.unit}'}';
            return s.trendDelta(at, value, x.name, over);
          }(),
    ];
  }

  static String _duration(S s, int us) {
    final secs = us ~/ 1000000;
    if (secs < 60) {
      return s.trendSeconds('$secs');
    }
    final mins = secs ~/ 60;
    if (mins < 60) {
      return s.trendMinutes('$mins');
    }
    return s.trendHoursMinutes('${mins ~/ 60}', '${mins % 60}');
  }

  // ----------------------------------------------------------------- brush

  Widget _brush(AppColors c, S s) => SizedBox(
    height: 56,
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        double xr(int t) => (t - vm.rangeStart) / _range * w;
        final l = xr(vm.windowStart);
        final r = xr(vm.windowEnd);
        final scrim = c.ground0.withValues(alpha: 0.62);
        Widget handle(FocusNode node, double at, String label, bool left) =>
            Positioned(
              left: at - 6,
              top: 0,
              bottom: 0,
              width: 12,
              child: Semantics(
                slider: true,
                label: label,
                value: _rangeText(vm.windowStart, vm.windowEnd),
                child: Focus(
                  focusNode: node,
                  onKeyEvent: (_, e) => _handleKey(e, left: left),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c.ember,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(3),
                        ),
                        border: node.hasFocus
                            ? .all(color: c.text1, width: 1.5)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
        return MouseRegion(
          cursor: _brushCursor,
          onHover: (e) {
            final cur = switch (_partAt(e.localPosition.dx, l, r)) {
              .left || .right => SystemMouseCursors.resizeLeftRight,
              .window => SystemMouseCursors.grab,
              .fresh => SystemMouseCursors.precise,
            };
            if (cur != _brushCursor) {
              setState(() => _brushCursor = cur);
            }
          },
          child: Listener(
            behavior: .opaque,
            onPointerDown: (e) => _brushDown(e, w, l, r),
            onPointerMove: (e) => _brushMove(e, w),
            onPointerUp: (_) => _drag = null,
            onPointerCancel: (_) => _drag = null,
            onPointerSignal: (e) {
              if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
                final d = (_span * 0.1).round() * e.scrollDelta.dy.sign.toInt();
                _window(vm.windowStart + d, vm.windowEnd + d);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: c.ground0,
                border: .all(color: c.ground4),
                borderRadius: Radii.segment,
              ),
              clipBehavior: .antiAlias,
              child: vm.loading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _skeleton(c, bars: 1),
                    )
                  : Stack(
                      clipBehavior: .none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BrushPainter(
                              geo: _geo,
                              start: vm.rangeStart,
                              end: vm.rangeEnd,
                              gap: c.bad,
                              colors: c,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          width: math.max(0, l),
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(color: scrim),
                        ),
                        Positioned(
                          left: r,
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(color: scrim),
                        ),
                        Positioned(
                          left: l,
                          width: math.max(0, r - l),
                          top: 0,
                          bottom: 0,
                          child: Tooltip(
                            message: s.trendMoveWindow,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.ember.withValues(alpha: 0.06),
                                border: Border.symmetric(
                                  horizontal: BorderSide(
                                    color: c.ember,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        handle(_leftFocus, l, s.trendWindowStart, true),
                        handle(_rightFocus, r, s.trendWindowEnd, false),
                      ],
                    ),
            ),
          ),
        );
      },
    ),
  );

  _Part _partAt(double x, double l, double r) {
    if ((x - l).abs() <= 6) {
      return .left;
    }
    if ((x - r).abs() <= 6) {
      return .right;
    }
    return x > l && x < r ? .window : .fresh;
  }

  int _tRange(double x, double w) =>
      vm.rangeStart + (_range * (x / w).clamp(0.0, 1.0)).round();

  void _brushDown(PointerDownEvent e, double w, double l, double r) {
    if (vm.loading || w <= 0) {
      return;
    }
    final x = e.localPosition.dx;
    final t = _tRange(x, w);
    final part = _partAt(x, l, r);
    _drag = (part: part, t0: t, a0: vm.windowStart, b0: vm.windowEnd);
    switch (part) {
      case .left:
        _leftFocus.requestFocus();
      case .right:
        _rightFocus.requestFocus();
      case .window || .fresh:
        break;
    }
    if (part == .fresh) {
      _window(t, t + vm.minWindow);
    }
  }

  void _brushMove(PointerMoveEvent e, double w) {
    final g = _drag;
    if (g == null || w <= 0) {
      return;
    }
    final t = _tRange(e.localPosition.dx, w);
    final min = vm.minWindow;
    switch (g.part) {
      case .window:
        final d = t - g.t0;
        _window(g.a0 + d, g.b0 + d);
      case .left:
        _window(math.min(t, vm.windowEnd - min), vm.windowEnd);
      case .right:
        _window(vm.windowStart, math.max(t, vm.windowStart + min));
      case .fresh:
        final a = math.min(g.t0, t);
        final b = math.max(g.t0, t);
        _window(a, math.max(b, a + min));
    }
  }

  KeyEventResult _handleKey(KeyEvent e, {required bool left}) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return .ignored;
    }
    final k = e.logicalKey;
    final dir = k == LogicalKeyboardKey.arrowLeft
        ? -1
        : k == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (dir == 0) {
      return .ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final d = dir * (shift ? _range ~/ 24 : _bucket);
    final min = vm.minWindow;
    if (left) {
      _window(math.min(vm.windowStart + d, vm.windowEnd - min), vm.windowEnd);
    } else {
      _window(vm.windowStart, math.max(vm.windowEnd + d, vm.windowStart + min));
    }
    return .handled;
  }
}

/// What [Trend] derives from its Vm once per change: the series shown,
/// their lines, gaps and axes.
final class _Geo {
  _Geo(TrendVm vm)
    : shown = [
        for (final s in vm.series)
          if (!s.hidden && !s.locked) s,
      ] {
    for (final s in shown) {
      traces[s.id] = trace(s.samples, vm.step);
      overviews[s.id] = trace(s.overview, null);
    }
    leftUnit = shown.isEmpty ? '' : shown.first.unit;
    final other = shown.where((s) => s.unit != leftUnit).firstOrNull;
    rightUnit = other?.unit ?? '';
    double lo(bool r) => _bound(vm, r, true);
    double hi(bool r) => _bound(vm, r, false);
    left = TrendAxis.fit(lo(false), hi(false));
    right = other == null ? null : TrendAxis.fit(lo(true), hi(true));
    gaps = unionOf([for (final t in traces.values) ...t.gaps]);
    overviewGaps = unionOf([for (final t in overviews.values) ...t.gaps]);
    final all = <int>{
      for (final s in shown)
        for (final p in s.samples) p.t,
    }.toList()..sort();
    times = all;
    overviewTimes = <int>{
      for (final s in vm.series)
        if (!s.locked)
          for (final p in s.overview) p.t,
    }.toList()..sort();
    anchor = all.isEmpty ? null : all.first;
    usual = shown.isEmpty ? null : _spacing(shown);
    // The brush scale: every readable series over the whole range.
    var a = double.infinity;
    var b = -double.infinity;
    for (final s in vm.series) {
      if (s.locked) {
        continue;
      }
      for (final p in s.overview) {
        if (drawable(p)) {
          a = math.min(a, p.v!);
          b = math.max(b, p.v!);
        }
      }
    }
    overviewLo = a;
    overviewHi = b;
    empty = vm.series.every(
      (s) => s.locked || (s.samples.isEmpty && s.overview.isEmpty),
    );
    _vm = vm;
  }

  final List<TrendSeriesVm> shown;
  final traces = <String, TrendTrace>{};
  final overviews = <String, TrendTrace>{};
  late final String leftUnit;
  late final String rightUnit;
  late final TrendAxis left;
  late final TrendAxis? right;
  late final List<TrendGap> gaps;
  late final List<TrendGap> overviewGaps;
  late final List<int> times;
  late final List<int> overviewTimes;
  late final int? anchor;
  late final int? usual;
  late final double overviewLo;
  late final double overviewHi;
  late final bool empty;
  late final TrendVm _vm;

  static int? _spacing(List<TrendSeriesVm> shown) {
    for (final s in shown) {
      if (spacing(s.samples) case final v?) {
        return v;
      }
    }
    return null;
  }

  TrendAxis axisOf(TrendSeriesVm s) =>
      right != null && s.unit != leftUnit ? right! : left;

  double _bound(TrendVm vm, bool rightAxis, bool low) {
    var v = low ? double.infinity : -double.infinity;
    for (final s in shown) {
      if ((s.unit != leftUnit) != rightAxis) {
        continue;
      }
      for (final p in s.samples) {
        if (!drawable(p) || p.t < vm.windowStart || p.t > vm.windowEnd) {
          continue;
        }
        final x = low ? (p.lo ?? p.v!) : (p.hi ?? p.v!);
        v = low ? math.min(v, x) : math.max(v, x);
      }
    }
    return v;
  }

  /// The row of [s] at the crosshair [t] (within half a bucket).
  TrendSample? at(TrendSeriesVm s, int t) {
    final tol = (_vm.step ?? spacing(s.samples) ?? 1) ~/ 2;
    final i = nearest(s.samples, t, math.max(0, tol));
    return i < 0 ? null : s.samples[i];
  }

  /// Why [s] has nothing at [t].
  String reasonAt(TrendSeriesVm s, int t, S words) {
    final g = traces[s.id]?.gaps.where((g) => t > g.from && t < g.to);
    final bad =
        (g != null && g.isNotEmpty && g.first.bad) ||
        (at(s, t)?.q == TrendQuality.bad);
    return bad
        ? (s.gapReason ?? words.trendBadRecorded)
        : words.trendNoDataRecorded;
  }
}

class _PlotPainter extends CustomPainter {
  const _PlotPainter({
    required this.geo,
    required this.start,
    required this.end,
    required this.grid,
    required this.gap,
    required this.colors,
  });

  final _Geo geo;
  final int start;
  final int end;
  final Color grid;
  final Color gap;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final span = math.max(1, end - start);
    double x(int t) => (t - start) / span * size.width;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final g = Paint()..color = grid;
    if (geo.shown.isNotEmpty) {
      for (final v in geo.left.ticks) {
        final y = geo.left.y(v, size.height).roundToDouble() + 0.5;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          g..strokeWidth = 1,
        );
      }
    }
    for (final b in geo.gaps) {
      if (b.to < start || b.from > end) {
        continue;
      }
      final r = Rect.fromLTRB(x(b.from), 0, x(b.to), size.height);
      canvas.drawRect(r, Paint()..color = gap.withValues(alpha: 0.12));
      _dashedRect(canvas, r.deflate(0.5), gap);
    }
    for (final s in geo.shown) {
      final axis = geo.axisOf(s);
      final p = Paint()
        ..color = s.color.of(colors)
        ..style = .stroke
        ..strokeWidth = 2
        ..strokeJoin = .round;
      for (final run in geo.traces[s.id]!.runs) {
        final path = _path(run.points, x, (v) => axis.y(v, size.height));
        if (path == null) {
          continue;
        }
        canvas.drawPath(run.dashed ? _dash(path, 5, 4) : path, p);
      }
    }
    canvas.restore();
  }

  /// The run as a path, from the last point before the window to the first
  /// after it.
  Path? _path(
    List<TrendSample> pts,
    double Function(int) x,
    double Function(double) y,
  ) {
    var i0 = 0;
    while (i0 + 1 < pts.length && pts[i0 + 1].t < start) {
      i0++;
    }
    var i1 = pts.length - 1;
    while (i1 - 1 > i0 && pts[i1 - 1].t > end) {
      i1--;
    }
    if (pts[i0].t > end || pts[i1].t < start || i1 <= i0) {
      return null;
    }
    final path = Path()..moveTo(x(pts[i0].t), y(pts[i0].v!));
    for (var i = i0 + 1; i <= i1; i++) {
      path.lineTo(x(pts[i].t), y(pts[i].v!));
    }
    return path;
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.geo != geo ||
      old.start != start ||
      old.end != end ||
      old.grid != grid ||
      old.gap != gap ||
      old.colors != colors;
}

class _BrushPainter extends CustomPainter {
  const _BrushPainter({
    required this.geo,
    required this.start,
    required this.end,
    required this.gap,
    required this.colors,
  });

  final _Geo geo;
  final int start;
  final int end;
  final Color gap;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final span = math.max(1, end - start);
    double x(int t) => (t - start) / span * size.width;
    final lo = geo.overviewLo;
    final hi = geo.overviewHi;
    final range = hi - lo > 0 ? hi - lo : 1.0;
    double y(double v) =>
        size.height - 4 - (v - lo) / range * (size.height - 8);
    for (final b in geo.overviewGaps) {
      canvas.drawRect(
        Rect.fromLTRB(x(b.from), 0, x(b.to), size.height),
        Paint()..color = gap.withValues(alpha: 0.18),
      );
    }
    if (!lo.isFinite) {
      return;
    }
    for (final s in geo.shown) {
      final p = Paint()
        ..color = s.color.of(colors).withValues(alpha: 0.8)
        ..style = .stroke
        ..strokeWidth = 1.2
        ..strokeJoin = .round;
      for (final run in geo.overviews[s.id]!.runs) {
        final path = Path()
          ..moveTo(x(run.points.first.t), y(run.points.first.v!));
        for (final q in run.points.skip(1)) {
          path.lineTo(x(q.t), y(q.v!));
        }
        canvas.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(_BrushPainter old) =>
      old.geo != geo ||
      old.start != start ||
      old.end != end ||
      old.colors != colors;
}

class _DashedBox extends CustomPainter {
  const _DashedBox({required this.fill, required this.line});

  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = fill);
    _dashedRect(canvas, r.deflate(0.5), line, dash: 2, gap: 2);
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.fill != fill || old.line != line;
}

class _DashedLine extends CustomPainter {
  const _DashedLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(
        Offset(0.5, y),
        Offset(0.5, math.min(y + 4, size.height)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}

void _dashedRect(
  Canvas canvas,
  Rect r,
  Color color, {
  double dash = 4,
  double gap = 4,
}) {
  final path = Path()..addRect(r);
  canvas.drawPath(
    _dash(path, dash, gap),
    Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1,
  );
}

Path _dash(Path source, double dash, double gap) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}
