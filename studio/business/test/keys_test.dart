import 'package:business/wyrm/keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// The path line of Explorer (docs/design/specs/explorer.md §3.1): which
/// segments open their node.
void main() {
  const sections = ['downstream', 'dataflows', 'storage', 'upstream'];

  test('every parent from the section down is a link', () {
    expect(
      parentLinksOf('wy/plant/downstream/s7/plc1/cpu', sections: sections),
      {
        'wy/plant/downstream',
        'wy/plant/downstream/s7',
        'wy/plant/downstream/s7/plc1',
      },
    );
  });

  test('wy, the site and the node itself are never links', () {
    final links = parentLinksOf(
      'wy/plant/storage/recipes/a',
      sections: sections,
    );
    expect(links, isNot(contains('wy')));
    expect(links, isNot(contains('wy/plant')));
    expect(links, isNot(contains('wy/plant/storage/recipes/a')));
  });

  test('a section alone has nothing above it to open', () {
    expect(parentLinksOf('wy/plant/downstream', sections: sections), isEmpty);
    expect(parentLinksOf(null, sections: sections), isEmpty);
  });

  test('a section the tree does not list gives no links', () {
    expect(
      parentLinksOf('wy/plant/sys/links/modbus', sections: sections),
      isEmpty,
    );
  });
}
