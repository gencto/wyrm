import 'package:localization/localization.dart';

import 'trend.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// How every trend of Studio writes its times: in local time, with the
/// weekday and month names of the language on screen (spec trend.md §5).
TrendFormat trendFormat() {
  final days = S.current.trendWeekdays.split(',');
  final months = S.current.trendMonths.split(',');
  String wd(DateTime t) => days[(t.weekday - 1) % days.length];
  return TrendFormat(
    locale: '${S.current.trendWeekdays} ${DateTime.now().timeZoneOffset}',
    clock: (t) {
      final l = t.toLocal();
      return '${_two(l.hour)}:${_two(l.minute)}';
    },
    clockSeconds: (t) {
      final l = t.toLocal();
      return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
    },
    day: (t) {
      final l = t.toLocal();
      return '${wd(l)} ${l.day} ${months[(l.month - 1) % months.length]}';
    },
    weekday: (t) => wd(t.toLocal()),
  );
}

/// What a trend's plot draws for a [step]: `15 min avg`, `1 h avg`, `1 d
/// avg`; `raw` for none.
String trendRollup(Duration? step) {
  final s = S.current;
  if (step == null) {
    return s.trendRaw;
  }
  final name = step.inDays >= 1 && step.inHours % 24 == 0
      ? s.trendStepDays('${step.inDays}')
      : step.inHours >= 1 && step.inMinutes % 60 == 0
      ? s.trendStepHours('${step.inHours}')
      : s.trendStepMinutes('${step.inMinutes}');
  return s.trendAvg(name);
}
