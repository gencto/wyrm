import 'package:app/common/forms.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/json_value.dart';
import 'package:models/param_spec.dart';
import 'package:ui/forms/param_form.dart';
import 'package:wyrm_client/wyrm_client.dart' show ParamEditor, TypeCode;

/// A parameter's `default` (spec 02, any JSON) gets its type once, where
/// its field is built, by the editor that shows it (studio-rules §8). A
/// default that does not fit its editor is none: an empty field.
void main() {
  ParamValue of(
    JsonValue? d, {
    TypeCode type = TypeCode.string,
    ParamEditor? editor,
    List<String> choices = const [],
    bool secret = false,
  }) => paramField(
    ParamSpec(
      name: 'p',
      type: type,
      editor: editor,
      choices: choices.lock,
      secret: secret,
      defaultValue: d,
    ),
  ).value;

  final map = JsonValue.of(const {'a': 1});

  test('a default that fits its editor', () {
    expect(of(const JsonText('plc1')), const TextValue('plc1'));
    expect(
      of(const JsonText('a\nb'), editor: ParamEditor.textarea),
      const TextValue('a\nb'),
    );
    expect(
      of(const JsonNumber(502), type: TypeCode.number),
      const NumberValue(502),
    );
    expect(
      of(const JsonBool(true), type: TypeCode.bool_),
      const FlagValue(on: true),
    );
    expect(
      of(const JsonText('f32'), type: TypeCode.enum_, choices: ['u16', 'f32']),
      const TextValue('f32'),
    );
    expect(
      of(const JsonText('points.csv'), editor: ParamEditor.file),
      const FileValue('points.csv'),
    );
  });

  test('missing and null are none, for every editor', () {
    for (final d in [null, const JsonNull()]) {
      expect(of(d), const NoValue());
      expect(of(d, type: TypeCode.number), const NoValue());
      expect(of(d, type: TypeCode.bool_), const NoValue());
      expect(of(d, choices: ['a']), const NoValue());
      expect(of(d, editor: ParamEditor.file), const NoValue());
      expect(of(d, editor: ParamEditor.textarea), const NoValue());
      expect(of(d, secret: true), const NoValue());
    }
  });

  test('a file editor with a default that is no text shows no file', () {
    expect(of(map, editor: ParamEditor.file), const NoValue());
    expect(of(const JsonNumber(1), editor: ParamEditor.file), const NoValue());
    expect(of(const JsonBool(true), editor: ParamEditor.file), const NoValue());
  });

  test('choices with a default that is not among them choose none', () {
    expect(of(const JsonNumber(0), choices: ['u16', 'f32']), const NoValue());
    expect(of(const JsonText('i64'), choices: ['u16', 'f32']), const NoValue());
    expect(of(map, choices: ['u16', 'f32']), const NoValue());
  });

  test('a text editor takes a text only', () {
    expect(of(const JsonNumber(5)), const NoValue());
    expect(of(const JsonBool(false)), const NoValue());
    expect(of(map), const NoValue());
    expect(of(map, type: TypeCode.map), const NoValue(), reason: 'textarea');
    expect(of(const JsonNumber(5), secret: true), const NoValue());
  });

  test('a number takes a number only, a switch a flag only', () {
    expect(of(const JsonText('5'), type: TypeCode.number), const NoValue());
    expect(of(const JsonBool(true), type: TypeCode.number), const NoValue());
    expect(of(const JsonText('true'), type: TypeCode.bool_), const NoValue());
    expect(of(const JsonNumber(1), type: TypeCode.bool_), const NoValue());
  });

  test('what the Explorer holds for a field keeps its own type', () {
    expect(heldValueOf('plc1', ParamKind.text), const TextValue('plc1'));
    expect(heldValueOf(2, ParamKind.number), const NumberValue(2));
    expect(heldValueOf(1.5, ParamKind.text), const NumberValue(1.5));
    expect(heldValueOf(false, ParamKind.toggle), const FlagValue(on: false));
    expect(heldValueOf('a.csv', ParamKind.file), const FileValue('a.csv'));
    expect(heldValueOf(null, ParamKind.text), const NoValue());
    expect(heldValueOf({'a': 1}, ParamKind.file), const NoValue());
    expect(heldValueOf([1], ParamKind.text), const NoValue());
  });
}
