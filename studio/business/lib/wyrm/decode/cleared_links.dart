import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// The answer of `sys ▸ clear_conns`: the ids the broker removed, as rows
/// of arrays of texts or of one text each (none: nothing was removed).
Decoded<List<String>> clearedLinksOf(List<Value> rows) {
  final ids = <String>[];
  for (final r in rows) {
    switch (r) {
      case VStr(:final v):
        ids.add(v);
      case VArray(:final v):
        for (final e in v) {
          switch (e) {
            case VStr(:final v):
              ids.add(v);
            default:
              return const Invalid('cleared links', '', 'not a text id');
          }
        }
      case VNull():
        break;
      default:
        return const Invalid('cleared links', '', 'not an id or ids');
    }
  }
  return Valid(ids);
}
