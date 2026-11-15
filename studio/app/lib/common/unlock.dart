import 'package:localization/localization.dart';

// Times that Access still writes in `app` (unlock-discover.md §1); the
// log-in page words its own in `ui`. The platform's words are `DeviceOs`, the
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
