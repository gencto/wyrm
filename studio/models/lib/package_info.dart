import 'package:freezed_annotation/freezed_annotation.dart';

part 'package_info.freezed.dart';

@freezed
abstract class PackageInfo with _$PackageInfo {
  /// A package installed under `sys/packages/<name>`.
  const factory PackageInfo({
    required String name,
    @Default('') String version,

    /// `process` or `wasm`.
    @Default('process') String kind,
    String? source,
    String? sha256,
  }) = _PackageInfo;
}
