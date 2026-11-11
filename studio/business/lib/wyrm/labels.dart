/// The words Studio shows for the names the broker uses (owner
/// 2026-11-11): an action, a parameter, a column, a value name or an enum
/// choice reads as the meta's `display` when it has one, else its name in
/// sentence case. The raw name stays reachable where it is shown (a
/// tooltip, a mono line); keys and the tree never change.
library;

/// Unit suffixes of engine names: `size_s` → `Size (s)`.
const _units = {'s': 's', 'ms': 'ms', 'mb': 'MB', 'hz': 'Hz'};

/// `input_min` → `Input min`: words split at `_` and `.`, the first with a
/// capital, a unit suffix in brackets.
String humanize(String name) {
  final words = name.split(RegExp('[_.]')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return name;
  }
  String? unit;
  if (words.length > 1 && _units.containsKey(words.last.toLowerCase())) {
    unit = _units[words.removeLast().toLowerCase()];
  }
  final text = [
    for (final (i, w) in words.indexed)
      if (i == 0) '${w[0].toUpperCase()}${w.substring(1)}' else w.toLowerCase(),
  ].join(' ');
  return unit == null ? text : '$text ($unit)';
}

/// What a human reads for [name]: [display] when it says something, else
/// [humanize]d [name].
String labelOf(String name, {String? display}) =>
    display != null && display.trim().isNotEmpty ? display : humanize(name);

/// Snake_case words of letters only (`a_ab`, `read_back`); a code with
/// digits (`f32_wbswap`, `u16_swapped`) is an id, not words.
final _snake = RegExp(r'^[a-z]+(_[a-z]+)+$');

/// What a human reads for the enum choice [value]: a snake_case word in
/// sentence case; anything else as it is (an id, a name, a key, a unit
/// like `1m`, a word the broker already wrote for people). The value sent
/// is always [value].
String choiceLabel(String value) =>
    _snake.hasMatch(value) ? humanize(value) : value;

/// The labels of [choices] that differ from the choice itself.
Map<String, String> choiceLabels(Iterable<String> choices) => {
  for (final c in choices)
    if (choiceLabel(c) != c) c: choiceLabel(c),
};
