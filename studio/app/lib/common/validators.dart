import 'package:business/wyrm/session.dart';
import 'package:localization/localization.dart';
import 'package:pro_validator/pro_validator.dart';

import '../mappers/log_in_mappers.dart';

S get s => S.current;

/// A value must be there.
RequiredValidator get requiredValidator =>
    RequiredValidator(error: s.requiredField);

/// One gateway URL, or several separated by commas (a standby, ADR 0036),
/// none with `user:password@` (the user and the password have their own
/// fields).
String? gatewayValidator(String? value) => gatewayProblemOf(value)?.ui.label;
