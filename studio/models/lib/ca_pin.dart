import 'package:freezed_annotation/freezed_annotation.dart';

part 'ca_pin.freezed.dart';

/// A CA the person checked and trusted for one gateway origin (ADR 0050
/// §2.3, *Trust*): every connection to that origin trusts this CA and no
/// other.
@freezed
abstract class CaPin with _$CaPin {
  const factory CaPin({
    /// `https://host:port`.
    required String origin,

    /// The CA certificate, DER in base64.
    required String ca,

    /// The CA code (32 hex digits) the person compared.
    required String code,

    /// The site it was trusted for.
    @Default('') String site,

    /// The address to connect to when the origin's name does not resolve
    /// on this computer (ADR 0050 decision 10).
    String? connectTo,
  }) = _CaPin;
}
