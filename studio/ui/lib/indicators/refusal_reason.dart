import 'package:localization/localization.dart';

/// A reason the gateway named for a refusal, as Studio says it in a
/// sentence (the lock card, the step-up): a `ui` enum (studio-rules §3);
/// the domain's code reaches it through one mapper in `app/lib/mappers/`.
enum RefusalReason {
  deviceRemoved,
  passwordChanged,
  passwordDue,
  devicesOff,
  confirmRequired,
  passwordRequired,
  tooManyDevices,
  badPassword;

  String get text => switch (this) {
    deviceRemoved => S.current.refusalDeviceRemoved,
    passwordChanged => S.current.refusalPasswordChanged,
    passwordDue => S.current.refusalPasswordDue,
    devicesOff => S.current.refusalDevicesOff,
    confirmRequired => S.current.refusalConfirmRequired,
    passwordRequired => S.current.refusalPasswordRequired,
    tooManyDevices => S.current.refusalTooManyDevices,
    badPassword => S.current.refusalBadPassword,
  };
}
