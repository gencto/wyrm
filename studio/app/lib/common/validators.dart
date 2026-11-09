import 'package:business/wyrm/session.dart';
import 'package:localization/localization.dart';
import 'package:pro_validator/pro_validator.dart';

S get s => S.current;

/// A value must be there.
RequiredValidator get requiredValidator =>
    RequiredValidator(error: s.requiredField);

/// One gateway URL, or several separated by commas (a standby, ADR 0036).
String? gatewayValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return s.requiredField;
  }
  return parseGateways(value).isEmpty ? s.invalidGatewayUrl : null;
}
