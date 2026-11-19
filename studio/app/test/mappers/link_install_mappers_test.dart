import 'package:app/mappers/link_install_mappers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/catalog_item.dart';
import 'package:models/known_link.dart';

/// The search of the official list: the rule is `business`'s
/// (`catalogHit`), the mapper hands it what each card reads on screen, so
/// a built-in driver is found by its title and line in the language shown.
void main() {
  setUp(() => S.load(const Locale('en')));

  // built in: the broker gives no title and no line, Studio words both
  const alarm = CatalogItem(
    id: 'driver:alarm',
    code: 'alarm',
    titled: KnownLink.alarm,
    described: KnownLink.alarm,
  );
  // a package of the repository: the broker's own title and line
  const meters = CatalogItem(
    id: 'package:meters',
    code: 'dlms',
    name: 'Meters',
    description: 'Electricity meters over DLMS',
  );
  const items = [alarm, meters];

  List<String> found(String? query) => [
    for (final c in catalogCards(items, query, null)) c.id,
  ];

  test('no words: every card, the one picked marked', () {
    expect(found(null), ['driver:alarm', 'package:meters']);
    expect(found('  '), ['driver:alarm', 'package:meters']);
    final cards = catalogCards(items, null, 'package:meters');
    expect([for (final c in cards) c.selected], [false, true]);
  });

  test('a built-in driver is found by its localized line, in English', () {
    final card = catalogCards(items, null, null).first;
    expect(card.summary, 'Alarm classes, records and acknowledgement');
    expect(found('acknowledgement'), ['driver:alarm']);
    expect(found('RECORDS alarm'), ['driver:alarm']);
    expect(found('modbus'), isEmpty);
  });

  test('and in Ukrainian by its Ukrainian line; the English one is not on '
      'screen and is not matched', () async {
    await S.load(const Locale('uk'));
    addTearDown(() => S.load(const Locale('en')));
    final card = catalogCards(items, null, null).first;
    expect(card.name, 'Тривоги');
    expect(found('тривоги'), ['driver:alarm']);
    expect(found('підтвердж'), ['driver:alarm']);
    expect(found('acknowledgement'), isEmpty);
    // its code is the broker's data: found in every language
    expect(found('alarm'), ['driver:alarm']);
  });

  test('a package is found by the broker’s own words and by its code', () {
    expect(found('electricity'), ['package:meters']);
    expect(found('dlms'), ['package:meters']);
    expect(found('meters dlms'), ['package:meters']);
  });
}
