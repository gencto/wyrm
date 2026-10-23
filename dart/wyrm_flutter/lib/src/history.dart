// The history window of a point: recorded values from the broker's
// historian (spec 01 `~val?history=`, ADR 0014) as a line chart and a table.

part of 'explorer.dart';

/// "View History" on a point: a window with a range (presets or from/to in
/// RFC 3339), an interval and a rollup; then a chart of the numeric values
/// and the rows.
abstract final class WyHistory {
  static void open(BuildContext context, WyrmApi api, String key) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Positioned(
          left: size.width * 0.15,
          top: 40,
          width: size.width * 0.8,
          height: size.height - 80,
          child: _HistoryWindow(api: api, nodeKey: key, onClose: entry.remove),
        );
      },
    );
    overlay.insert(entry);
  }
}

class _HistoryWindow extends StatefulWidget {
  final WyrmApi api;
  final String nodeKey;
  final VoidCallback onClose;
  const _HistoryWindow({required this.api, required this.nodeKey, required this.onClose});

  @override
  State<_HistoryWindow> createState() => _HistoryWindowState();
}

/// Ranges offered as buttons.
const _presets = [('1 h', Duration(hours: 1)), ('24 h', Duration(days: 1)), ('7 d', Duration(days: 7)), ('30 d', Duration(days: 30))];

const _rollups = ['none', 'avg', 'min', 'max', 'sum', 'first', 'last', 'count', 'delta', 'and', 'or'];

String _iso(DateTime t) => t.toUtc().toIso8601String();

String _timeOf(int us) => _iso(DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true));

class _HistoryWindowState extends State<_HistoryWindow> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _interval = TextEditingController(text: 'none');
  String _rollup = 'none';
  List<HistRow>? _rows;
  String? _error;
  bool _loading = false;

  /// The point's own meta: its unit for the rows and the chart.
  NodeMeta? _meta;

  @override
  void initState() {
    super.initState();
    _from.text = _iso(DateTime.now().subtract(const Duration(hours: 1)));
    widget.api.meta(widget.nodeKey).then((m) {
      if (mounted) setState(() => _meta = m);
    }, onError: (Object _) {});
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final interval = _interval.text.trim();
    try {
      final rows = await widget.api.history(
        widget.nodeKey,
        from: _from.text.trim(),
        to: _to.text.trim(),
        agg: _rollup == 'none' ? null : _rollup,
        window: interval.isEmpty || interval == 'none' ? null : interval,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is WyrmException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  void _preset(Duration d) {
    _from.text = _iso(DateTime.now().subtract(d));
    _to.text = '';
    _load();
  }

  Widget _field(String label, TextEditingController c, double width, {String? hint}) => SizedBox(
        width: width,
        child: Row(children: [
          Text(label, style: WyStyle.formLabel),
          const SizedBox(width: 6),
          Expanded(
            child: _FieldBox(
              child: TextField(
                controller: c,
                style: WyStyle.input,
                cursorColor: WyStyle.accent,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: WyStyle.input.copyWith(color: WyStyle.placeholder),
                ),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final status = _error ??
        (_loading
            ? 'Loading…'
            : rows == null
                ? ''
                : rows.isEmpty
                    ? 'No rows. A point gets history from a watch in sys/history.'
                    : '${rows.length} rows');
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(color: WyStyle.field, border: Border.all(color: WyStyle.line), boxShadow: WyStyle.shadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 34,
            color: WyStyle.tabBar,
            padding: const EdgeInsets.only(left: 14, right: 6),
            child: Row(children: [
              Expanded(
                child: Text('History: ${widget.nodeKey}',
                    overflow: TextOverflow.ellipsis, style: WyStyle.tab.copyWith(fontSize: 14)),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 18, color: WyStyle.text),
                onPressed: widget.onClose,
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final (label, d) in _presets) SizedBox(width: 56, child: _Button(label: label, onTap: () => _preset(d))),
              _field('From', _from, 280),
              _field('To', _to, 280, hint: 'now'),
              _field('Interval', _interval, 150),
              // wide enough for its list (a menu panel is at least 160)
              SizedBox(
                width: 230,
                child: Row(children: [
                  Text('Rollup', style: WyStyle.formLabel),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _EnumField(
                      value: _rollup,
                      options: _rollups,
                      onChanged: (v) => setState(() => _rollup = v),
                    ),
                  ),
                ]),
              ),
              SizedBox(width: 80, child: _Button(label: 'Load', onTap: _load)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(status,
                style: WyStyle.formLabel.copyWith(color: _error != null ? WyStyle.error : WyStyle.text)),
          ),
          if (rows != null && rows.isNotEmpty) ...[
            Container(
              height: 220,
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(color: WyStyle.panel, border: Border.all(color: WyStyle.line)),
              child: CustomPaint(painter: _ChartPainter(rows, unitSuffix(_meta)), size: Size.infinite),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length + 1,
                itemExtent: 26,
                itemBuilder: (_, i) {
                  Widget cell(String t, double w, {bool head = false, Color? color}) => Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                            color: head ? WyStyle.panel : null,
                            border: Border.all(color: WyStyle.line, width: 0.5)),
                        child: Text(t,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WyStyle.formLabel.copyWith(color: color ?? (head ? WyStyle.text : WyStyle.accent))),
                      );
                  if (i == 0) {
                    return Row(children: [
                      cell('time (UTC)', 260, head: true),
                      cell('value', 220, head: true),
                      cell('quality', 120, head: true),
                    ]);
                  }
                  final r = rows[i - 1];
                  return Row(children: [
                    cell(_timeOf(r.t), 260),
                    cell(formatValue(r.v, _meta), 220),
                    cell(r.q?.wireName ?? '', 120, color: r.q == Quality.bad ? WyStyle.error : null),
                  ]);
                },
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A line of the numeric values over time (bools as 0/1): min and max on
/// the left, the first and last time below; `bad` samples as red dots.
class _ChartPainter extends CustomPainter {
  final List<HistRow> rows;

  /// Written after the min and max labels (`' °C'`), or empty.
  final String unit;
  _ChartPainter(this.rows, this.unit);

  static double? _num(Value v) => switch (v) {
        VInt(:final v) => v.toDouble(),
        VFloat(:final v) => v,
        VBool(:final v) => v ? 1 : 0,
        _ => null,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (final r in rows)
        if (_num(r.v) case final y?) (r.t, y, r.q == Quality.bad),
    ];
    final label = TextPainter(textDirection: TextDirection.ltr);
    void text(String s, Offset at) {
      label.text = TextSpan(text: s, style: WyStyle.label);
      label.layout();
      label.paint(canvas, at);
    }

    if (pts.isEmpty) {
      text('No numeric values to draw', const Offset(10, 10));
      return;
    }
    const left = 70.0, bottom = 22.0, top = 10.0, right = 10.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final t0 = pts.first.$1, t1 = pts.last.$1;
    var lo = pts.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
    var hi = pts.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    double x(int t) => t1 == t0 ? plot.center.dx : plot.left + (t - t0) / (t1 - t0) * plot.width;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    final grid = Paint()
      ..color = WyStyle.line
      ..strokeWidth = 1;
    canvas.drawRect(plot, grid..style = PaintingStyle.stroke);
    final line = Path()..moveTo(x(pts.first.$1), y(pts.first.$2));
    for (final p in pts.skip(1)) {
      line.lineTo(x(p.$1), y(p.$2));
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = WyStyle.accent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    final bad = Paint()..color = WyStyle.error;
    for (final p in pts.where((p) => p.$3)) {
      canvas.drawCircle(Offset(x(p.$1), y(p.$2)), 3, bad);
    }
    String n(double v) => v.abs() >= 1000 || v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsPrecision(4);
    text('${n(hi)}$unit', const Offset(6, top));
    text('${n(lo)}$unit', Offset(6, plot.bottom - 12));
    text(_timeOf(t0), Offset(left, plot.bottom + 4));
    final end = _timeOf(t1);
    label.text = TextSpan(text: end, style: WyStyle.label);
    label.layout();
    label.paint(canvas, Offset(plot.right - label.width, plot.bottom + 4));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.rows != rows || old.unit != unit;
}
