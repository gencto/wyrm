/// What a call was about, when that is a thing Studio names itself and not
/// a name from the broker (`StudioError.thing`): the app says it in the
/// user's language.
enum ErrorSubject {
  /// The assistant (the agent link).
  assistant,

  /// A profile being written.
  profile,

  /// A device key, by its id in `StudioError.thing`.
  device,

  /// This computer's unlock method, when the system names none.
  biometrics,
}
