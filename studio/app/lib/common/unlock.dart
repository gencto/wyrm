import 'package:localization/localization.dart';

// Times and initials that log-in, security and access still write in `app`
// (unlock-discover.md §1). The platform's words are `DeviceOs`, the
// method's `UnlockMethod` (`ui/lib/indicators`), reached through
// `app/lib/mappers/device_mappers.dart`.

/// `3 Nov` for seconds since the Unix epoch; empty for 0.
String shortDate(int seconds) => seconds <= 0
    ? ''
    : Formats.shortDate(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));

/// `now`, `5 min ago`, `2 h ago`, `3 d ago`.
String agoOf(int seconds, {DateTime? now}) => seconds <= 0
    ? ''
    : Formats.ago(
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        now: now,
        nowWord: S.current.unlockAgoNow,
      );

/// Two letters of a user: `olena` → `OL`.
String initialsOf(String user) {
  final u = user.trim();
  if (u.isEmpty) {
    return '?';
  }
  final parts = u.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty);
  final two = parts.length > 1
      ? '${parts.first[0]}${parts.elementAt(1)[0]}'
      : u.substring(0, u.length < 2 ? u.length : 2);
  return two.toUpperCase();
}
