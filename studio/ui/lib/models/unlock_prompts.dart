import 'package:localization/localization.dart';

// The words of the device key's OS prompts (unlock-discover.md §2), in the
// language on screen: `app` hands them to `business` as its
// `DevicePrompts`, which calls them with the site and the user at the
// moment a prompt opens (studio-rules §5).

/// `sign in to <site> as <user>`: a device login or an idle unlock.
String promptUnlock(String site, String user) =>
    S.current.unlockPrompt(site, user);

/// `turn on unlocking <site> as <user>`: a new key.
String promptEnable(String site, String user) =>
    S.current.unlockEnablePrompt(site, user);

/// `confirm changes on <site>`: a step-up.
String promptConfirm(String site) => S.current.unlockConfirmPrompt(site);
