import 'package:models/catalog_item.dart';

// How a typed search matches (the official list of links): one rule, here,
// tested without a screen. What a row reads on screen is the app's to
// hand in (a known driver's title and line are `ui`'s words, in the
// language shown); what counts as a hit is decided here.

/// [text] as the search compares it: lower case, outer spaces dropped,
/// every run of spaces one space.
String searchFold(String text) =>
    text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// The words of [query], folded; empty when it holds none.
List<String> searchWords(String query) {
  final folded = searchFold(query);
  return folded.isEmpty ? const [] : folded.split(' ');
}

/// The [query] hits [texts]: each of its words is in one of them (in any
/// order, as part of a word, whatever the case). A query with no word
/// hits everything.
bool searchHit(String query, Iterable<String> texts) {
  final folded = [for (final t in texts) searchFold(t)];
  return searchWords(query).every((w) => folded.any((t) => t.contains(w)));
}

/// The words searched for ([query]) hit the item [item] of the official
/// list: in what the broker says of it (its code, name and line) or in
/// what its card reads on screen ([shown]: its title and line as drawn, in
/// the language shown).
bool catalogHit(CatalogItem item, String? query, Iterable<String> shown) =>
    searchHit(query ?? '', [
      item.code,
      item.name,
      item.description,
      ...shown,
    ]);
