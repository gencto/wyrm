import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';

void main() {
  setUp(() => S.load(const Locale('en')));

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

  test('count: thousands separated, rounded, signed', () {
    expect(Formats.count(0), '0');
    expect(Formats.count(999), '999');
    expect(Formats.count(18402), '18,402');
    expect(Formats.count(1234567.4), '1,234,567');
    expect(Formats.count(-3), '-3');
  });

  test('figure: one decimal below 100 without .0, counted above', () {
    expect(Formats.figure(3.42), '3.4');
    expect(Formats.figure(7), '7');
    expect(Formats.figure(99.96), '100');
    expect(Formats.figure(412.5), '413');
    expect(Formats.figure(1490.5), '1,491');
  });

  test('mebibyteFigure: MiB as a figure, GiB with one decimal from 1024', () {
    expect(Formats.mebibyteFigure(842.3), (figure: '842', unit: 'MiB'));
    expect(Formats.mebibyteFigure(42.3), (figure: '42.3', unit: 'MiB'));
    expect(Formats.mebibyteFigure(18432), (figure: '18.0', unit: 'GiB'));
    expect(Formats.mebibyteText(310), '310 MiB');
  });

  test('utcMinute and utcClockSeconds write UTC whatever the zone', () {
    final t = DateTime.utc(2026, 11, 4, 21, 58, 7);
    expect(Formats.utcMinute(t), '2026-11-04 21:58 UTC');
    expect(Formats.utcMinute(t.toLocal()), '2026-11-04 21:58 UTC');
    expect(Formats.utcClockSeconds(t.toLocal()), '21:58:07');
  });

  test('runFor: the two largest units', () {
    expect(Formats.runFor(const Duration(seconds: 533000)), '6 d 4 h');
    expect(Formats.runFor(const Duration(hours: 3, minutes: 12)), '3 h 12 min');
    expect(Formats.runFor(const Duration(minutes: 5, seconds: 40)), '5 min');
  });
}
