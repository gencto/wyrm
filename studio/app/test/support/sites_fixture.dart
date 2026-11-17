import 'package:business/redux/app_state.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/site_choice.dart';
import 'package:models/site_pick.dart';
import 'package:models/site_relation.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'screen_app.dart';

const _sys = '$plant/sys';

/// What the broker of `plant` holds for Sites: the upstream `central`, the
/// broker `line1` below (relaying `line3`), the platform upstream of the
/// `uplink` link, the external link `field-gw` on another device, the
/// broker `line2` and the link `field-x` waiting in quarantine, and the
/// actions Sites calls.
void sitesBroker(FakeWyrmApi api) {
  ValSample at(String key, Value v) => ValSample(key, Sample(v, t: 1));
  api
    // the upstream (sys/upstream/<u> and its values)
    ..children_['$_sys/upstream'] = [
      Child(
        'central',
        NodeMeta(
          attr: {
            'url': const VStr('quic://central.example:7447'),
            'status': const VStr('connected'),
            'allow_config': const VBool(true),
          },
        ),
      ),
    ]
    ..initial['$_sys/upstream_connected'] = [
      at('$_sys/upstream_connected', const VInt(1)),
    ]
    ..initial['$_sys/version'] = [at('$_sys/version', const VStr('0.1.0'))]
    // the brokers and links below
    ..children_['$plant/downstream'] = [
      Child(
        'line1',
        NodeMeta(
          is_: const TText('wy:broker'),
          attr: {'site': const VStr('line1')},
        ),
      ),
      Child('modbus', NodeMeta()),
      Child('uplink', NodeMeta()),
    ]
    ..children_['$plant/downstream/uplink'] = [
      Child('mqtt-cloud', NodeMeta(display: 'MQTT · UNS')),
      Child('stats', NodeMeta()),
    ]
    // the links (field-gw runs on another device)
    ..children_['$_sys/links'] = [
      Child('modbus', NodeMeta()),
      Child('field-gw', NodeMeta()),
    ]
    ..metas['$_sys/links/modbus'] = NodeMeta(
      attr: {'driver': const VStr('modbus')},
    )
    ..metas['$_sys/links/field-gw'] = NodeMeta(
      attr: {
        'mode': const VStr('external'),
        'device': const VStr('10.0.0.7:7447'),
      },
    )
    ..metas['$_sys/links'] = NodeMeta()
    // quarantine
    ..children_['$_sys/quarantine'] = [
      Child('line2', NodeMeta()),
      Child('field-x', NodeMeta()),
    ]
    ..metas['$_sys/quarantine/line2'] = NodeMeta(
      display: 'broker:line2',
      attr: {
        'kind': const VStr('broker'),
        'from': const VStr('10.0.0.9:51234'),
        'via': const VArray([VStr('line4')]),
        'key': const VStr('SHA256:ab12…'),
      },
      actions: {
        'approve': ActionMeta(
          level: Perm.config,
          params: {
            'key': ParamMeta(ty: TypeCode.string, required: true),
            'via': ParamMeta(ty: TypeCode.string),
          },
        ),
      },
    )
    ..metas['$_sys/quarantine/field-x'] = NodeMeta(
      display: 'link:field-x',
      attr: {'from': const VStr('10.0.0.12:40001')},
    )
    // the action forms and answers
    ..metas['$_sys/upstream'] = NodeMeta(
      actions: {
        'add': ActionMeta(
          level: Perm.config,
          params: {
            'url': ParamMeta(ty: TypeCode.string, required: true),
            'token': ParamMeta(ty: TypeCode.string),
          },
        ),
      },
    )
    ..invokes['$_sys/upstream ▸ add'] = const [VNull()]
    ..invokes['$_sys/tokens ▸ add'] = const [VStr('wyt_1a2b3c')]
    ..invokes['$_sys/quarantine ▸ deauthorize'] = const [VNull()]
    ..invokes['$_sys/quarantine/field-x ▸ reject'] = const [VNull()]
    ..invokes['$_sys/quarantine/line2 ▸ reject'] = const [VNull()]
    ..invokes['$_sys/quarantine/line2 ▸ approve'] = const [VNull()];
}

/// [s] with the sites `plant` reaches: `line3` relayed below `line1`.
AppState withSites(AppState s, {SitePick? selected}) => s.copyWith(
  site: s.site.copyWith(
    connected: true,
    choices: IList(const [
      SiteChoice(site: 'plant'),
      SiteChoice(site: 'central', relation: SiteRelation.upstream),
      SiteChoice(site: 'line1', relation: SiteRelation.downstream),
      SiteChoice(
        site: 'line3',
        relation: SiteRelation.downstream,
        via: 'line1',
      ),
    ]),
  ),
  peers: s.peers.copyWith(selectedPeer: selected),
);
