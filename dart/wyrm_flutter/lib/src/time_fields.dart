part of 'explorer.dart';

// Times in forms (spec 02 0.2.4 `editor`): `daterange` — text `from/to` in
// RFC 3339, chosen from a list of ranges or by dates and times, as the
// date-range editor of a DSA client; `date` — one RFC 3339 instant;
// `duration` — a number of seconds, typed in the unit chosen beside it.
//
// The pickers are panels on the overlay, above the context menu and its
// forms (which are overlay entries too): a dialog route would open beneath
// them.

const _editorDateRange = 'daterange';
const _editorDate = 'date';
const _editorDuration = 'duration';

/// RFC 3339 in UTC to the second: `2026-10-22T00:00:00Z`.
String _isoSecond(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Local date for people: `2026-10-22`.
String _day(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

/// The ranges a DSA date-range editor offers, in local time; a week starts
/// on Monday.
List<(String, DateTime, DateTime)> _rangePresets(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final week = today.subtract(Duration(days: today.weekday - 1));
  final month = DateTime(now.year, now.month);
  final year = DateTime(now.year);
  return [
    ('Today', today, now),
    ('Yesterday', today.subtract(const Duration(days: 1)), today),
    ('This Week', week, now),
    ('Last Week', week.subtract(const Duration(days: 7)), week),
    ('This Month', month, now),
    ('Last Month', DateTime(now.year, now.month - 1), month),
    ('This Year', year, now),
    ('Last Year', DateTime(now.year - 1), year),
    ('Last Hour', now.subtract(const Duration(hours: 1)), now),
    ('Last 24 Hours', now.subtract(const Duration(hours: 24)), now),
    ('Last 7 Days', now.subtract(const Duration(days: 7)), now),
    ('Last 30 Days', now.subtract(const Duration(days: 30)), now),
  ];
}

/// History intervals as a DSA client offers them (`sys/history` Get
/// History has the same list).
const _historyIntervals = [
  'none', '1s', '5s', '10s', '15s', '30s', '1m', '5m', '10m', '15m', '30m', //
  '1h', '2h', '3h', '4h', '6h', '12h', '1d', '1w',
];

/// Units of a `duration` field, in seconds.
const _durationUnits = [('s', 1), ('min', 60), ('h', 3600), ('d', 86400)];

/// The range `text` holds (`from/to`), if it parses; an empty end is now.
(DateTime, DateTime)? _parseRange(String text) {
  final parts = text.split('/');
  if (parts.length != 2) return null;
  final from = DateTime.tryParse(parts[0].trim());
  if (from == null) return null;
  final to = parts[1].trim().isEmpty ? DateTime.now() : DateTime.tryParse(parts[1].trim());
  return to == null ? null : (from.toLocal(), to.toLocal());
}

/// A modal panel on top of the overlay; its result, `null` when dismissed.
Future<T?> _showPanel<T>(BuildContext context, Widget Function(void Function(T?) done) build) {
  final overlay = Overlay.of(context);
  final result = Completer<T?>();
  late OverlayEntry entry;
  void done(T? v) {
    if (result.isCompleted) return;
    entry.remove();
    result.complete(v);
  }

  entry = OverlayEntry(
    builder: (_) => Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => done(null),
          child: const ColoredBox(color: Color(0x66000000)),
        ),
      ),
      Center(
        child: Material(
          color: WyStyle.panel,
          shape: const RoundedRectangleBorder(side: BorderSide(color: WyStyle.line)),
          child: Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: WyStyle.accent, surface: WyStyle.panel),
            ),
            child: build(done),
          ),
        ),
      ),
    ]),
  );
  overlay.insert(entry);
  return result.future;
}

/// Choose a range: one of [_rangePresets], or From and To by date and time.
/// Returns `from/to` in RFC 3339 UTC.
Future<String?> pickTimeRange(BuildContext context, String current) =>
    _showPanel<String>(context, (done) => _TimeRangePanel(current: current, done: done));

/// Choose one instant; RFC 3339 UTC.
Future<String?> pickTime(BuildContext context, String current) => _showPanel<String>(
      context,
      (done) => _InstantPanel(
        initial: DateTime.tryParse(current)?.toLocal() ?? DateTime.now(),
        done: done,
      ),
    );

/// A date (a calendar that opens below it) and a time `HH:MM`.
class _InstantEditor extends StatefulWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _InstantEditor({required this.label, required this.value, required this.onChanged});

  @override
  State<_InstantEditor> createState() => _InstantEditorState();
}

class _InstantEditorState extends State<_InstantEditor> {
  bool _calendar = false;
  late final _time = TextEditingController(text: '${_two(widget.value.hour)}:${_two(widget.value.minute)}');

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _setTime(String text) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) return;
    final d = widget.value;
    widget.onChanged(DateTime(d.year, d.month, d.day, h, min));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          SizedBox(width: 50, child: Text(widget.label, style: WyStyle.formLabel)),
          Expanded(child: _Button(label: _day(d), onTap: () => setState(() => _calendar = !_calendar))),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: _FieldBox(
              child: TextField(
                controller: _time,
                style: WyStyle.input,
                cursorColor: WyStyle.accent,
                decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: 'HH:MM'),
                onChanged: _setTime,
              ),
            ),
          ),
        ]),
      ),
      if (_calendar)
        SizedBox(
          height: 300,
          child: CalendarDatePicker(
            initialDate: d,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            onDateChanged: (day) {
              setState(() => _calendar = false);
              widget.onChanged(DateTime(day.year, day.month, day.day, d.hour, d.minute));
            },
          ),
        ),
    ]);
  }
}

Widget _okCancel(VoidCallback? ok, VoidCallback cancel) =>
    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      SizedBox(width: 90, child: _Button(label: 'Cancel', onTap: cancel)),
      const SizedBox(width: 6),
      SizedBox(width: 90, child: _Button(label: 'OK', onTap: ok)),
    ]);

class _TimeRangePanel extends StatefulWidget {
  final String current;
  final void Function(String?) done;
  const _TimeRangePanel({required this.current, required this.done});

  @override
  State<_TimeRangePanel> createState() => _TimeRangePanelState();
}

class _TimeRangePanelState extends State<_TimeRangePanel> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final r = _parseRange(widget.current);
    _from = r?.$1 ?? DateTime(now.year, now.month, now.day);
    _to = r?.$2 ?? now;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Timerange', style: WyStyle.menu),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (name, from, to) in _rangePresets(DateTime.now()))
                SizedBox(
                  width: 125,
                  child: _Button(
                    label: name,
                    onTap: () => widget.done('${_isoSecond(from)}/${_isoSecond(to)}'),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Container(height: 1, color: WyStyle.line),
            const SizedBox(height: 6),
            const Text('Custom', style: WyStyle.formLabel),
            _InstantEditor(label: 'From', value: _from, onChanged: (t) => setState(() => _from = t)),
            _InstantEditor(label: 'To', value: _to, onChanged: (t) => setState(() => _to = t)),
            const SizedBox(height: 12),
            _okCancel(
              _to.isAfter(_from) ? () => widget.done('${_isoSecond(_from)}/${_isoSecond(_to)}') : null,
              () => widget.done(null),
            ),
          ]),
        ),
      );
}

class _InstantPanel extends StatefulWidget {
  final DateTime initial;
  final void Function(String?) done;
  const _InstantPanel({required this.initial, required this.done});

  @override
  State<_InstantPanel> createState() => _InstantPanelState();
}

class _InstantPanelState extends State<_InstantPanel> {
  late DateTime _t = widget.initial;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Date', style: WyStyle.menu),
            _InstantEditor(label: 'At', value: _t, onChanged: (t) => setState(() => _t = t)),
            const SizedBox(height: 12),
            _okCancel(() => widget.done(_isoSecond(_t)), () => widget.done(null)),
          ]),
        ),
      );
}

/// The calendar button beside a `daterange` or `date` field.
class _TimeButton extends StatelessWidget {
  final bool range;
  final TextEditingController controller;
  const _TimeButton({required this.range, required this.controller});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final v = range ? await pickTimeRange(context, controller.text) : await pickTime(context, controller.text);
          if (v != null) controller.text = v;
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.calendar_month, size: 16, color: WyStyle.accent),
        ),
      );
}
