import 'generated/l10n.dart';

/// Typed values as a person reads them, in the current language
/// (studio-rules §5). A connector passes the value — an `int` of bytes, a
/// `DateTime`, a `Duration` — and the widget in `ui` calls one of these.
///
/// Times are written in local time: a UTC `DateTime` is moved to the
/// viewer's zone first, a local one is written as it is.
///
/// A count with a word (`3 points`) is not here: it is a plural message of
/// the `.arb` files, called as `S.current.pointsCount(n)`.
abstract final class Formats {
  static String _two(int n) => n.toString().padLeft(2, '0');

  /// A poll rate in seconds: `500 ms`, `1 s`, `2.5 s`.
  static String pollRate(num seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).round()} ms';
    }
    return seconds == seconds.roundToDouble()
        ? '${seconds.round()} s'
        : '$seconds s';
  }

  /// `812 B`, `48 KiB`, `3.1 MiB`, `1.2 GiB`.
  static String bytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const units = ['KiB', 'MiB', 'GiB', 'TiB'];
    var v = bytes / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    final whole = v >= 100 || v == v.roundToDouble();
    return '${whole ? v.round() : v.toStringAsFixed(1)} ${units[u]}';
  }

  /// A size given in MiB (the historian's `database_size`): `4.2 MiB`,
  /// `310 MiB`, `1.5 GiB`.
  static String mebibytes(num mib) => mib >= 1024
      ? '${(mib / 1024).toStringAsFixed(1)} GiB'
      : '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MiB';

  /// How long ago, from an [age]: `just now` under a minute, then
  /// `5 min ago`, `2 h ago`, `3 d ago`. [now] is the word under a minute
  /// where the design asks for another one (`now` on a device row).
  static String age(Duration age, {String? now}) {
    if (age.inMinutes < 1) {
      return now ?? S.current.agoNow;
    }
    if (age.inHours < 1) {
      return S.current.agoMinutes(age.inMinutes);
    }
    if (age.inDays < 1) {
      return S.current.agoHours(age.inHours);
    }
    return S.current.agoDays(age.inDays);
  }

  /// [age] of the moment [at], seen from [now] (the clock by default).
  static String ago(DateTime at, {DateTime? now, String? nowWord}) =>
      age((now ?? DateTime.now()).difference(at), now: nowWord);

  /// `3 Nov`.
  static String shortDate(DateTime t) {
    final l = t.toLocal();
    final months = S.current.monthsShort.split(',');
    return '${l.day} ${months[(l.month - 1) % months.length]}';
  }

  /// `2026-11-15`.
  static String date(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)}';
  }

  /// `14:25`.
  static String clock(DateTime t) {
    final l = t.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// `14:25:07`.
  static String clockSeconds(DateTime t) {
    final l = t.toLocal();
    return '${clock(l)}:${_two(l.second)}';
  }

  /// `2026-11-15 14:25`.
  static String dateTime(DateTime t) => '${date(t)} ${clock(t)}';

  /// A countdown or a short run: `04:05` (minutes and seconds; the minutes
  /// grow past 59).
  static String minutesSeconds(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${_two(s ~/ 60)}:${_two(s % 60)}';
  }

  /// A whole number with its thousands separated: `18,402`, `-3`.
  static String count(num n) {
    final digits = n.round().abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// A measured figure: one decimal below 100 (none when it is `.0`),
  /// whole and [count]ed from 100 up: `3.4`, `7`, `413`, `1,520`.
  static String figure(num n) {
    if (n.abs() >= 100) {
      return count(n);
    }
    final s = n.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// A size given in MiB as a tile shows it: the [figure] in MiB, or GiB
  /// with one decimal from 1024 MiB up: `(842, MiB)`, `(18.0, GiB)`.
  static ({String figure, String unit}) mebibyteFigure(num mib) => mib >= 1024
      ? (figure: (mib / 1024).toStringAsFixed(1), unit: 'GiB')
      : (figure: figure(mib), unit: 'MiB');

  /// [mebibyteFigure] as one text: `842 MiB`, `18.0 GiB`.
  static String mebibyteText(num mib) {
    final f = mebibyteFigure(mib);
    return '${f.figure} ${f.unit}';
  }

  /// A moment in UTC to the minute, as the broker's own times are shown:
  /// `2026-11-04 21:58 UTC`.
  static String utcMinute(DateTime t) {
    final u = t.toUtc();
    return '${u.year}-${_two(u.month)}-${_two(u.day)} '
        '${_two(u.hour)}:${_two(u.minute)} UTC';
  }

  /// The time of day in UTC to the second, as the broker's log writes it:
  /// `02:01:44`.
  static String utcClockSeconds(DateTime t) {
    final u = t.toUtc();
    return '${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}';
  }

  /// How long something has run, in its two largest units: `6 d 4 h`,
  /// `3 h 12 min`, `5 min`.
  static String runFor(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays} d ${d.inHours % 24} h';
    }
    if (d.inHours > 0) {
      return '${d.inHours} h ${d.inMinutes % 60} min';
    }
    return '${d.inMinutes} min';
  }
}
