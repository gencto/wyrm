/// What unlocks the device key here (`device_key`'s `DeviceKeyKind`): the
/// log-in page picks the name, the icon and the prompt by it
/// (studio/docs/design/specs/unlock-discover.md §1).
enum KeyKind {
  none,
  touchId,
  faceId,
  opticId,
  windowsHello,
  fingerprint,
  face,
  iris,
  biometric,
}
