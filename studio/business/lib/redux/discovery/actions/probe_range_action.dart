import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';

import '../../../wyrm/discovery.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'begin_find_action.dart';
import 'check_found_gateway_action.dart';

/// *Probe a range* (ADR 0050 §2.3): an opt-in `GET /api/info` on [port] of
/// every address of [range], 16 at a time, at most 1 024 addresses, each
/// given 1.5 s. HTTPS first, plain HTTP when the port does not speak TLS.
/// The rows are made and merged as the browse's are.
class ProbeRangeAction extends Action {
  ProbeRangeAction(this.range, this.port);

  /// `10.0.7.0/24`, or one address.
  final String range;
  final int port;

  @override
  Future<AppState?> reduce() async {
    final List<String> addresses;
    try {
      addresses = rangeAddresses(range);
    } on RangeFormatException catch (e) {
      // The form checks before it dispatches (the same function); a
      // dispatch without that changes nothing and says why.
      throw StudioException.hinted(
        ErrorKind.input,
        switch (e.fault) {
          RangeFault.badText => const ErrorHint.rangeBadText(),
          RangeFault.badPart => const ErrorHint.rangeBadPart(),
          RangeFault.badPrefix => const ErrorHint.rangeBadPrefix(),
          RangeFault.tooBig => const ErrorHint.rangeTooBig(),
        },
        call: const .known(.probeRange),
        thing: range,
      ).withDialog(false);
    }
    if (port < 1 || port > 65535) {
      throw StudioException.hinted(
        ErrorKind.input,
        const ErrorHint.portOutOfRange(),
        call: const .known(.probeRange),
        thing: '$port',
      ).withDialog(false);
    }
    dispatchSync(BeginFindAction(probing: true));
    final scan = discovery.scan;
    await pooled(addresses, (ip) async {
      if (discovery.scan == scan) {
        await dispatchAndWait(
          CheckFoundGatewayAction(
            Announcement(name: ip, addresses: [ip], port: port, probed: true),
            scan,
          ),
        );
      }
    });
    if (discovery.scan != scan) {
      return null;
    }
    return state.copyWith.discovery(scanning: false, ended: true);
  }
}
