import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';

void main() {
  setUp(() async => S.load(const Locale('en')));

  test('bytes: B under a KiB, one decimal under 100, whole above', () {
    expect(Formats.bytes(812), '812 B');
    expect(Formats.bytes(48 * 1024), '48 KiB');
    expect(Formats.bytes((3.1 * 1024 * 1024).round()), '3.1 MiB');
    expect(Formats.bytes(150 * 1024 * 1024), '150 MiB');
    expect(Formats.bytes((1.2 * 1024 * 1024 * 1024).round()), '1.2 GiB');
  });

  test('mebibytes: one decimal under 10 MiB, GiB from 1024', () {
    expect(Formats.mebibytes(4.2), '4.2 MiB');
    expect(Formats.mebibytes(310), '310 MiB');
    expect(Formats.mebibytes(1536), '1.5 GiB');
  });

  test('age: now, minutes, hours, days', () {
    expect(Formats.age(const Duration(seconds: 30)), 'just now');
    expect(Formats.age(const Duration(seconds: 30), now: 'now'), 'now');
    expect(Formats.age(const Duration(minutes: 5)), '5 min ago');
    expect(Formats.age(const Duration(hours: 2, minutes: 5)), '2 h ago');
    expect(Formats.age(const Duration(days: 3, hours: 1)), '3 d ago');
  });

  test('ago: the age of a moment from a given now', () {
    final now = DateTime(2026, 11, 15, 12);
    expect(
      Formats.ago(now.subtract(const Duration(minutes: 7)), now: now),
      '7 min ago',
    );
  });

  test('dates and clocks in local time', () {
    final t = DateTime(2026, 11, 3, 9, 5, 7);
    expect(Formats.shortDate(t), '3 Nov');
    expect(Formats.date(t), '2026-11-03');
    expect(Formats.clock(t), '09:05');
    expect(Formats.clockSeconds(t), '09:05:07');
    expect(Formats.dateTime(t), '2026-11-03 09:05');
  });

  test('a UTC moment is written in local time', () {
    final t = DateTime(2026, 11, 3, 9, 5);
    expect(Formats.clock(t.toUtc()), '09:05');
  });

  test('minutesSeconds: zero-padded, never negative', () {
    expect(Formats.minutesSeconds(const Duration(seconds: 245)), '04:05');
    expect(Formats.minutesSeconds(const Duration(minutes: 75)), '75:00');
    expect(Formats.minutesSeconds(const Duration(seconds: -3)), '00:00');
  });

  test('the words follow the language', () async {
    await S.load(const Locale('uk'));
    expect(Formats.age(const Duration(minutes: 5)), '5 хв тому');
    expect(Formats.shortDate(DateTime(2026, 11, 3)), '3 лис');
  });
}
