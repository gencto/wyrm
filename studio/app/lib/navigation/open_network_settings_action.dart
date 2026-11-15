import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:models/host_platform.dart';
import 'package:url_launcher/url_launcher.dart';

/// *Open settings* under *Nothing found* (unlock-discover.md §4): the
/// system's page where the person lets Studio see the local network —
/// macOS's Local Network privacy pane, iOS's settings of the app. Nothing
/// on the other platforms (the link is not offered there). Changes no
/// state.
class OpenNetworkSettingsAction extends ReduxAction<AppState> {
  /// The system page for [platform]; null where there is none.
  static Uri? pageOf(HostPlatform platform) => switch (platform) {
    HostPlatform.macos => Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security'
      '?Privacy_LocalNetwork',
    ),
    HostPlatform.ios => Uri.parse('app-settings:'),
    HostPlatform.windows ||
    HostPlatform.android ||
    HostPlatform.linux ||
    HostPlatform.web => null,
  };

  @override
  Future<AppState?> reduce() async {
    if (pageOf(hostPlatform()) case final page?) {
      await launchUrl(page);
    }
    return null;
  }
}
