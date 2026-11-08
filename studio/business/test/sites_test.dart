// The fake streams live as long as each test.

import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/peers/actions/retrieve_peers_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/peer_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

void main() {
  test(
    'RetrievePeersAction: upstreams with values, brokers below, platforms',
    () async {
      final login = FakeLogin();
      final api = login.session.api;
      final s = fakeStore(login: login);
      await s.dispatchAndWait(SetGatewayAction('http://g'));
      await s.dispatchAndWait(SetUserAction('admin'));
      await s.dispatchAndWait(SetPasswordAction('pw'));
      await s.dispatchAndWait(LogInAction());

      api.children_['wy/central/sys/upstream'] = [Child('ops', NodeMeta())];
      api.children_['wy/central/downstream'] = [
        Child(
          'edge',
          NodeMeta(
            is_: const TText('wy:broker'),
            attr: {'site': const VStr('edge')},
          ),
        ),
        Child('uplink', NodeMeta(is_: const TText('wy:link'))),
        Child('mock', NodeMeta(is_: const TText('wy:link'))),
      ];
      api.children_['wy/central/downstream/uplink'] = [
        Child('stats', NodeMeta()),
        Child('uns', NodeMeta(display: 'MQTT (UNS)')),
      ];

      api.initial['wy/central/sys/upstream/*/*'] = [
        const ValSample(
          'wy/central/sys/upstream/ops/url',
          Sample(VStr('quic/ops:7449'), t: 1),
        ),
      ];
      api.initial['wy/central/sys/upstream_connected'] = [
        const ValSample(
          'wy/central/sys/upstream_connected',
          Sample(VInt(1), t: 1),
        ),
      ];
      final done = s.dispatchAndWait(RetrievePeersAction());
      await done;

      final byKind = {
        for (final p in s.state.peers.table.values)
          '${p.kind.name}:${p.site}': p,
      };
      expect(
        byKind.keys,
        containsAll(['upstream:ops', 'downstream:edge', 'platform:uns']),
      );
      expect(byKind['upstream:ops']!.url, 'quic/ops:7449');
      expect(byKind['upstream:ops']!.connected, isTrue);
      expect(byKind['platform:uns']!.platform, 'MQTT (UNS)');
      expect(
        byKind.values.where((p) => p.kind == PeerKind.platform),
        hasLength(1),
      );
    },
  );
}
