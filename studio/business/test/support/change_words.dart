import 'package:models/change_side.dart';

/// The English of one side of a staged change, for the tests of `business`
/// that read a change as its review card shows it. The words themselves
/// are `ui`'s, from the `.arb` files (`ui/test/change_words_test.dart`
/// holds the same sentences).
extension ChangeSideEn on ChangeSide {
  String get en => switch (this) {
    ChangeSideText(:final text) => text,
    ChangeSideNone() => '—',
    ChangeSideRev(:final rev, detail: '') => 'rev $rev',
    ChangeSideRev(:final rev, :final detail) => 'rev $rev: $detail',
    ChangeSideFlag(on: true) => 'on',
    ChangeSideFlag(on: false) => 'off',
    ChangeSideKeys(:final count) => '$count top-level keys',
  };
}
