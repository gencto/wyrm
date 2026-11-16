/// What a field of a flow block is in the engine (flow-editor.md §3).
enum FieldKind {
  /// A parameter of the node's config (`cfg.<name>`).
  param('p'),

  /// An input port that is not a parameter's port (`in`, `in.0`, `reset`).
  input('in'),

  /// An output port (`out`, `remainder`, …).
  output('out'),

  /// An argument of an `invoke` block's `args` map.
  arg('arg');

  const FieldKind(this.prefix);

  /// The prefix of the field's [FieldId.key].
  final String prefix;

  static FieldKind? fromPrefix(String s) => switch (s) {
    _ when s == param.prefix => param,
    _ when s == input.prefix => input,
    _ when s == output.prefix => output,
    _ when s == arg.prefix => arg,
    _ => null,
  };
}

/// A row of the flow editor's inspector: a field of the block
/// ([FieldId]), or the choice of the block's form ([FormRow]). [key] is the
/// row's text identity: a `ui` row's id and a pin's key in the
/// definition's `layout`; nothing compares it.
sealed class RowId {
  const RowId();

  /// `p:<name>`, `in:<port>`, `out:<port>`, `arg:<name>`, `form`.
  String get key;

  /// The row of [key], or null when it names none.
  static RowId? fromKey(String key) =>
      key == FormRow.formKey ? const FormRow() : FieldId.fromKey(key);

  @override
  String toString() => key;
}

/// One field of a flow block, unique within the block: its [kind] and the
/// engine's [name] for it (the parameter, the port or the argument).
final class FieldId extends RowId {
  const FieldId(this.kind, this.name);

  const FieldId.param(this.name) : kind = FieldKind.param;
  const FieldId.input(this.name) : kind = FieldKind.input;
  const FieldId.output(this.name) : kind = FieldKind.output;
  const FieldId.arg(this.name) : kind = FieldKind.arg;

  final FieldKind kind;
  final String name;

  @override
  String get key => '${kind.prefix}:$name';

  /// The field of [key] (`p:k`, `in:in.0`); null for any other text.
  static FieldId? fromKey(String key) {
    final i = key.indexOf(':');
    if (i <= 0 || i == key.length - 1) {
      return null;
    }
    final kind = FieldKind.fromPrefix(key.substring(0, i));
    return kind == null ? null : FieldId(kind, key.substring(i + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is FieldId && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);
}

/// The inspector's choice of a block's form (`scale`: linear or range).
final class FormRow extends RowId {
  const FormRow();

  static const formKey = 'form';

  @override
  String get key => formKey;

  @override
  bool operator ==(Object other) => other is FormRow;

  @override
  int get hashCode => (FormRow).hashCode;
}

/// A row [row] of block [block]: the field the value viewer shows
/// (`flowEditor.viewedField`). Reads `<block>/<row key>` (`pct/p:k`).
final class FieldAt {
  const FieldAt(this.block, this.row);

  final String block;
  final RowId row;

  @override
  bool operator ==(Object other) =>
      other is FieldAt && other.block == block && other.row == row;

  @override
  int get hashCode => Object.hash(block, row);

  @override
  String toString() => '$block/${row.key}';
}
