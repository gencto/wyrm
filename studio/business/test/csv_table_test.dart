import 'package:business/wyrm/mappers/csv_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// The CSV rules of `table_from_csv` and `table_to_csv`, mirrored from
/// `crates/wyrm-flow/src/blocks/tables.rs` (`parse_csv`, `write_csv` and
/// their test `csv_both_ways`): the viewer's "As table" tab shows what the
/// block will produce.
void main() {
  List<Object?> col(
    String csv,
    String name, {
    bool header = true,
    String d = ',',
  }) {
    final t = parseCsv(csv, delimiter: d, header: header)!;
    final i = t.columns.indexOf(name);
    return [for (final r in t.rows) r[i]];
  }

  test('a header names the columns; cells are texts', () {
    final t = parseCsv('a,b\n1,2\n3,4')!;
    expect(t.columns, ['a', 'b']);
    expect(col('a,b\n1,2\n3,4', 'b'), ['2', '4']);
  });

  test('without a header the columns are v1, v2, …', () {
    final t = parseCsv('x;y\n1;2', delimiter: ';', header: false)!;
    expect(t.columns, ['v1', 'v2']);
    expect(t.rows, hasLength(2));
  });

  test('a quoted field keeps its delimiter', () {
    expect(col('a,b\n1,"x,y"\n', 'b'), ['x,y']);
  });

  test('an empty line inside is a row, an empty last one is not', () {
    expect(col('a\n\nb\n', 'v1', header: false), ['a', '', 'b']);
  });

  test(
    '"" is a quote in a field of more than two quotes; CR LF ends a row',
    () {
      expect(col('"say ""hi""",2\r\n', 'v1', header: false), ['say "hi"']);
    },
  );

  test('a quoted field is the text between its first and last quote', () {
    // Text around the quotes is dropped; a delimiter between them stays.
    expect(col('x"a,b"y\n', 'v1', header: false), ['a,b']);
    // An open quote runs to the end of the text.
    expect(col('"open,end', 'v1', header: false), ['open,end']);
  });

  test('no row at all is parse_error', () {
    expect(parseCsv(''), isNull);
    expect(parseCsv('\n'), isNotNull, reason: 'one empty line is a row');
  });

  test('a name twice keeps both columns; an empty one is v<n>', () {
    expect(parseCsv('a,a\n1,2')!.columns, ['a', 'a_2']);
    expect(parseCsv('a,,a,a_2\n1,2,3,4')!.columns, ['a', 'v2', 'a_2', 'a_2_2']);
  });

  test(
    'a row longer than the header adds columns; a shorter one lacks cells',
    () {
      final t = parseCsv('a\n1,2\n3')!;
      expect(t.columns, ['a', 'v2']);
      expect(t.rows, [
        ['1', '2'],
        ['3', null],
      ]);
    },
  );

  test('the bounds are checked while it reads', () {
    expect(parseCsv('${List.filled(129, 'a').join(',')}\n1'), isNull);
    expect(parseCsv('x' * (64 * 1024 + 2), header: false), isNull);
    expect(parseCsv('a\n${List.filled(10001, '1').join('\n')}'), isNotNull);
    expect(parseCsv('a\n${List.filled(10002, '1').join('\n')}\n'), isNull);
    expect(parseCsv('x' * (csvMaxText + 1)), isNull);
  });

  test('the delimiter is the first character, a comma when empty', () {
    expect(csvDelimiter(';;'), ';');
    expect(csvDelimiter(''), ',');
    expect(csvDelimiter(null), ',');
  });

  test('written as table_to_csv writes it', () {
    expect(
      writeCsv(
        ['name', 'kw', 'zone'],
        [
          ['pump', 3, 'A'],
          ['valve', null, 'B'],
        ],
      ),
      'name,kw,zone\npump,3,A\nvalve,,B\n',
    );
    expect(
      writeCsv(
        ['a'],
        [
          ['x,"y"'],
        ],
        header: false,
      ),
      '"x,""y"""\n',
    );
    expect(
      writeCsv(
        ['a'],
        [
          [
            {'k': 1},
          ],
          ['two\nlines'],
        ],
        header: false,
      ),
      '"{""k"":1}"\n"two\nlines"\n',
    );
  });

  test('read, write, read: the same table', () {
    const text = 'name;note\npump;"a; b"\nfan;"say ""hi"""\n';
    final t = parseCsv(text, delimiter: ';')!;
    final back = writeCsv(t.columns, t.rows, delimiter: ';');
    final again = parseCsv(back, delimiter: ';')!;
    expect(again.columns, t.columns);
    expect(again.rows, t.rows);
  });
}
