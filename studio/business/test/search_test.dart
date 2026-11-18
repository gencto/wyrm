import 'package:business/wyrm/search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/catalog_item.dart';

/// How a typed search matches (the official list of links): one rule for
/// every screen that searches it.
void main() {
  test('text is compared folded: case, outer and doubled spaces', () {
    expect(searchFold('  Siemens   S7 '), 'siemens s7');
    expect(searchWords('  Siemens   S7 '), ['siemens', 's7']);
    expect(searchWords('   '), isEmpty);
  });

  test('each word of the query is in one of the texts, in any order', () {
    const texts = ['Alarms (process)', 'Alarm classes, records'];
    expect(searchHit('alarm', texts), isTrue);
    expect(searchHit('RECORDS alarms', texts), isTrue);
    expect(searchHit('class proc', texts), isTrue, reason: 'part of a word');
    expect(searchHit('alarm modbus', texts), isFalse, reason: 'every word');
    expect(searchHit('', texts), isTrue);
    expect(searchHit('  ', const []), isTrue);
    expect(searchHit('x', const []), isFalse);
  });

  test('an item is hit by what the broker says of it, and by what its card '
      'reads on screen', () {
    const item = CatalogItem(
      id: 'package:meters',
      code: 'dlms',
      name: 'Meters',
      description: 'Electricity meters over DLMS',
    );
    expect(catalogHit(item, null, const []), isTrue);
    expect(catalogHit(item, 'dlms', const []), isTrue, reason: 'its code');
    expect(catalogHit(item, 'METERS', const []), isTrue, reason: 'its name');
    expect(catalogHit(item, 'electricity', const []), isTrue);
    expect(catalogHit(item, 'лічильники', const []), isFalse);
    // what the card reads in the language shown is handed in by the app
    expect(
      catalogHit(item, 'лічильники', const ['Лічильники електроенергії']),
      isTrue,
    );
    expect(catalogHit(item, 'dlms лічильники', const ['Лічильники']), isTrue);
  });
}
