import 'package:freezed_annotation/freezed_annotation.dart';

part 'schema_pair.freezed.dart';

@freezed
abstract class SchemaPair with _$SchemaPair {
  /// The SCHEMA of one store in a backup and on this broker (`schemas` of
  /// the answer of `restore_check`).
  const factory SchemaPair({required int backup, required int here}) =
      _SchemaPair;
}
