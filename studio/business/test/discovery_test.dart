import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/persistor.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/discovery/actions/close_discovery_action.dart';
import 'package:business/redux/discovery/actions/find_gateways_action.dart';
import 'package:business/redux/discovery/actions/pick_found_gateway_action.dart';
import 'package:business/redux/discovery/actions/probe_range_action.dart';
import 'package:business/redux/discovery/actions/trust_gateway_action.dart';
import 'package:business/redux/services/gateway_browser/gateway_browser.dart';
import 'package:business/wyrm/discovery.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/ca_pin.dart';
import 'package:models/found_gateway.dart';
import 'package:models/found_problem.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';
import 'support/test_tls.dart';

/// Finding a gateway on the local network (ADR 0050 §2,
/// docs/design/specs/unlock-discover.md §4): rows from the browse and from
/// a range probe, their tags and reasons, and the trust step.
void main() {
  final plantCa = Uint8List.fromList(List.generate(300, (i) => i % 251));
  final labCa = Uint8List.fromList(List.generate(300, (i) => (i * 7) % 253));
  final plantCode = caCode(plantCa);
  final labCode = caCode(labCa);

  GatewayInfo info(
    String site, {
    Uint8List? ca,
    List<String> names = const [],
    String role = 'active',
    String? pair,
    List<String> up = const [],
    String minStudio = '1.0.0',
    String? caFp,
    bool tls = true,
  }) => GatewayInfo(
    site: site,
    version: '0.1.0',
    tls: tls,
    role: role,
    pair: pair,
    up: up,
    minStudio: minStudio,
    ca: ca,
    caFp: caFp ?? (ca == null ? null : caCode(ca)),
    names: names,
  );

  Announcement announce(
    String site,
    String address, {
    int port = 8446,
    String? hostname,
    Map<String, String> txt = const {},
  }) => Announcement(
    name: site,
    hostname: hostname,
    addresses: [address],
    port: port,
    txt: {'site': site, 'tls': '1', 'v': '0.1.0', ...txt},
  );

  group('rows', () {
    test('an active with pair is one row with its standby', () async {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.10:8446'],
          info(
            'plant',
            ca: plantCa,
            names: ['10.0.7.10'],
            pair: 'edge.local:8444',
          ),
        )
        ..trusted.add('https://10.0.7.10:8446');
      final s = discoveryStore(
        info: net,
        found: [
          announce(
            'plant',
            '10.0.7.10',
            txt: {'pair': 'edge.local:8444', 'fp': plantCode},
          ),
        ],
      );

      await s.dispatchAndWait(FindGatewaysAction());
      await s.waitAllActions([], completeImmediately: true);

      final row = s.state.discovery.found['plant']!;
      expect(row.url, 'https://10.0.7.10:8446');
      expect(row.standby, 'https://edge.local:8444');
      expect(row.known, isTrue);
      expect(tagsOf(row, const []), [FoundTag.activeStandby]);
      expect(s.state.discovery.scanning, isFalse);
      expect(s.state.discovery.ended, isTrue);
      expect(s.state.discovery.network, 'en0');
      expect(s.state.discovery.subnet, '10.0.7.0/24');
    });

    test('two hosts of one site merge, the active first', () {
      const standby = FoundGateway(
        site: 'plant',
        hosts: IListConst(['10.0.7.11:8446']),
        url: 'https://10.0.7.11:8446',
        role: 'standby',
        seen: 1,
      );
      const active = FoundGateway(
        site: 'plant',
        hosts: IListConst(['10.0.7.10:8446']),
        url: 'https://10.0.7.10:8446',
        seen: 2,
      );

      final merged = mergeFound(
        mergeFound(const IMapConst({}), standby),
        active,
      );

      expect(merged.length, 1);
      final row = merged['plant']!;
      expect(row.url, 'https://10.0.7.10:8446');
      expect(row.standby, 'https://10.0.7.11:8446');
      expect(row.hosts, ['10.0.7.10:8446', '10.0.7.11:8446']);
      expect(row.seen, 2);
      // The same host again replaces its row and keeps the standby.
      final again = mergeFound(merged, active.copyWith(seen: 3));
      expect(again['plant']!.standby, 'https://10.0.7.11:8446');
      expect(again['plant']!.seen, 3);
    });

    test('tags: used before, downstream, new', () {
      const row = FoundGateway(
        site: 'line3',
        url: 'https://10.0.7.31:8446',
        up: IListConst(['plant']),
      );

      expect(tagsOf(row, ['https://10.0.7.31:8446, https://b:1']), [
        FoundTag.usedBefore,
        FoundTag.downstream,
        FoundTag.fresh,
      ]);
      expect(tagsOf(row.copyWith(knownAs: 'plant'), const []), [
        FoundTag.downstream,
      ]);
      expect(
        tagsOf(row.copyWith(known: true), ['https://10.0.7.31:9999']),
        [FoundTag.downstream],
        reason: 'another port is another origin',
      );
    });

    test(
      'plain http off loopback is disabled, on loopback it is not',
      () async {
        final net = FakeInfo()
          ..serve(['http://10.0.7.88:8080'], info('test-rig', tls: false))
          ..serve(['http://127.0.0.1:8445'], info('demo', tls: false));

        final far = await checkFound(
          announce('test-rig', '10.0.7.88', port: 8080, txt: {'tls': '0'}),
          reader: net,
          trust: const GatewayTrust(),
          now: 0,
        );
        final near = await checkFound(
          announce('demo', '127.0.0.1', port: 8445, txt: {'tls': '0'}),
          reader: net,
          trust: const GatewayTrust(),
          now: 0,
        );

        expect(far!.problem, FoundProblem.plainHttp);
        expect(far.url, isNull);
        expect(tagsOf(far, const []), [FoundTag.plainHttp]);
        expect(near!.problem, isNull);
        expect(near.url, 'http://127.0.0.1:8445');
      },
    );

    test('a Studio older than min_studio, and no /api/info', () async {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.20:8446'],
          info('lab', ca: labCa, names: ['10.0.7.20'], minStudio: '2.1.0'),
        )
        ..fail('https://10.0.7.21:8446', InfoFault.missing);

      final newer = await checkFound(
        announce('lab', '10.0.7.20'),
        reader: net,
        trust: const GatewayTrust(),
        now: 0,
      );
      final older = await checkFound(
        announce('old', '10.0.7.21'),
        reader: net,
        trust: const GatewayTrust(),
        now: 0,
      );

      expect(newer!.problem, FoundProblem.studioTooOld);
      expect(newer.detail, '2.1.0');
      expect(older!.problem, FoundProblem.noInfo);
      expect(older.url, isNull);
    });

    test('a TXT fp or ca_fp that is not the CA code is refused', () async {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.20:8446'],
          info('lab', ca: labCa, names: ['10.0.7.20']),
        )
        ..serve(
          ['https://10.0.7.22:8446'],
          info('lab2', ca: labCa, names: ['10.0.7.22'], caFp: plantCode),
        );

      final txt = await checkFound(
        announce('lab', '10.0.7.20', txt: {'fp': plantCode}),
        reader: net,
        trust: const GatewayTrust(),
        now: 0,
      );
      final claimed = await checkFound(
        announce('lab2', '10.0.7.22'),
        reader: net,
        trust: const GatewayTrust(),
        now: 0,
      );

      expect(txt!.problem, FoundProblem.codeMismatch);
      expect(claimed!.problem, FoundProblem.codeMismatch);
      expect(txt.code, labCode, reason: 'the code is computed, not taken');
    });

    test(
      'Look again starts over; late answers of the last browse go',
      () async {
        final net = FakeInfo()
          ..serve(
            ['https://10.0.7.10:8446'],
            info('plant', ca: plantCa, names: ['10.0.7.10']),
          )
          ..delay = const Duration(milliseconds: 30);
        final s = discoveryStore(
          info: net,
          found: [announce('plant', '10.0.7.10')],
        );

        await s.dispatchAndWait(FindGatewaysAction());
        // The row is still being checked when the person looks again.
        final first = s.state.discovery.scan;
        expect(s.state.discovery.found, isEmpty);
        await s.dispatchAndWait(FindGatewaysAction());
        await s.waitAllActions([], completeImmediately: true);

        expect(s.state.discovery.scan, first + 1);
        expect(s.state.discovery.found.keys, ['plant'], reason: 'one row');

        s.dispatchSync(CloseDiscoveryAction());
        expect(s.state.discovery.open, isFalse);
        expect(s.state.discovery.scan, first + 2);
      },
    );

    test('the URL comes from the certificate names', () async {
      Future<bool> resolves(String h) async => h == 'plant.example';

      final byAddress = await urlFromNames(
        address: '10.0.7.10',
        port: 8446,
        names: ['plant.example', '10.0.7.10'],
        resolves: resolves,
      );
      final byMdns = await urlFromNames(
        address: '10.0.7.10',
        port: 8446,
        names: ['plant.local', 'plant.example'],
        hostname: 'plant.local.',
        resolves: resolves,
      );
      final byDns = await urlFromNames(
        address: '10.0.7.10',
        port: 8446,
        names: ['plant.example'],
        resolves: resolves,
      );
      final unresolved = await urlFromNames(
        address: '10.0.7.10',
        port: 8446,
        names: ['plant.corp', '*.corp'],
        resolves: resolves,
      );
      final none = await urlFromNames(
        address: '10.0.7.10',
        port: 8446,
        names: ['10.9.9.9'],
        resolves: resolves,
      );

      expect('${byAddress!.url}', 'https://10.0.7.10:8446');
      expect(byAddress.connectTo, isNull);
      expect('${byMdns!.url}', 'https://plant.local:8446');
      expect(byMdns.connectTo, '10.0.7.10', reason: 'it does not resolve');
      expect('${byDns!.url}', 'https://plant.example:8446');
      expect(byDns.connectTo, isNull);
      expect('${unresolved!.url}', 'https://plant.corp:8446');
      expect(unresolved.connectTo, '10.0.7.10');
      expect(none, isNull);
    });
  });

  group('probe a range', () {
    test('reads a CIDR, at most 1024 addresses', () {
      expect(rangeAddresses('10.0.7.0/24'), hasLength(254));
      expect(rangeAddresses('10.0.7.0/24').first, '10.0.7.1');
      expect(rangeAddresses('10.0.7.0/24').last, '10.0.7.254');
      expect(rangeAddresses('10.0.7.77/24').first, '10.0.7.1');
      expect(rangeAddresses('10.0.4.0/22'), hasLength(1022));
      expect(rangeAddresses('10.0.7.9'), ['10.0.7.9']);
      expect(rangeAddresses('10.0.7.8/31'), ['10.0.7.8', '10.0.7.9']);
      for (final bad in ['10.0.0.0/21', '10.0.7/24', '10.0.7.300', 'x', '']) {
        expect(
          () => rangeAddresses(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('16 at a time, rows from the addresses that answer', () async {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.31:8446'],
          info('line3', ca: plantCa, names: ['10.0.7.31'], up: ['plant']),
        )
        ..delay = const Duration(milliseconds: 2);
      final s = discoveryStore(info: net);

      await s.dispatchAndWait(ProbeRangeAction('10.0.7.0/26', 8446));

      expect(net.unverified, hasLength(62), reason: 'each address once');
      expect(net.most, 16);
      expect(s.state.discovery.found.keys, ['line3']);
      final row = s.state.discovery.found['line3']!;
      expect(row.probed, isTrue);
      expect(row.up, ['plant']);
      expect(s.state.discovery.scanning, isFalse);
    });

    test('a bad range is refused before anything is sent', () async {
      final net = FakeInfo();
      final s = discoveryStore(info: net);

      final status = await s.dispatchAndWait(
        ProbeRangeAction('10.0.0.0/16', 8446),
      );

      expect(status.isCompletedFailed, isTrue);
      expect(net.unverified, isEmpty);
    });

    test('a wyrm:// code gives the URL and the CA code', () {
      final code = parseGatewayCode(
        'wyrm://plant.local:8446?fp=4F2A91C0D7E35B18A0C47E293D6FB812',
      );
      expect('${code!.url}', 'https://plant.local:8446');
      expect(code.code, '4f2a91c0d7e35b18a0c47e293d6fb812');
      expect(parseGatewayCode('wyrm://plant.local:8446?fp=12'), isNull);
      expect(parseGatewayCode('https://plant.local:8446?fp=$labCode'), isNull);
      expect(parseGatewayCode('wyrm://plant.local?fp=$labCode'), isNull);
      expect(codeGroups(code.code), [
        '4F2A',
        '91C0',
        'D7E3',
        '5B18',
        'A0C4',
        '7E29',
        '3D6F',
        'B812',
      ]);
    });
  });

  group('trust', () {
    FakeInfo lab() => FakeInfo()
      ..serve(
        ['https://10.0.7.20:8446'],
        info('lab', ca: labCa, names: ['10.0.7.20'], pair: '10.0.7.21:8446'),
      );

    Future<Store<AppState>> found(FakeInfo net) async {
      final s = discoveryStore(
        info: net,
        found: [
          announce('lab', '10.0.7.20', txt: {'fp': labCode}),
        ],
      );
      await s.dispatchAndWait(FindGatewaysAction());
      await s.waitAllActions([], completeImmediately: true);
      return s;
    }

    test('a new CA asks first, then pins it per origin', () async {
      final net = lab();
      final s = await found(net);
      final row = s.state.discovery.found['lab']!;
      expect(row.known, isFalse);
      expect(tagsOf(row, const []), contains(FoundTag.fresh));

      await s.dispatchAndWait(PickFoundGatewayAction('lab'));
      expect(s.state.discovery.trustPending, 'lab');
      expect(
        s.state.login.gateway,
        'https://10.0.7.20:8446, https://10.0.7.21:8446',
      );

      await s.dispatchAndWait(TrustGatewayAction('lab'));

      final pins = s.state.discovery.pins;
      expect(pins.keys.toSet(), {
        'https://10.0.7.20:8446',
        'https://10.0.7.21:8446',
      });
      expect(pins['https://10.0.7.20:8446']!.code, labCode);
      expect(pins['https://10.0.7.20:8446']!.ca, base64Encode(labCa));
      expect(s.state.discovery.trustPending, isNull);
      expect(s.state.discovery.found['lab']!.known, isTrue);
      // The pin decides for that origin only.
      final trust = GatewayTrust(pins);
      expect(trust.pinOf(Uri.parse('https://10.0.7.20:8446')), isNotNull);
      expect(trust.pinOf(Uri.parse('https://10.0.7.20:9999')), isNull);
    });

    test('a ca_fp that changed before the trust is refused', () async {
      final net = lab();
      final s = await found(net);
      await s.dispatchAndWait(PickFoundGatewayAction('lab'));
      net.serve(
        ['https://10.0.7.20:8446'],
        info('lab', ca: labCa, names: ['10.0.7.20'], caFp: plantCode),
      );

      await s.dispatchAndWait(TrustGatewayAction('lab'));

      expect(s.state.discovery.pins, isEmpty);
      expect(s.state.discovery.trustRefused, TrustRefusal.mismatch);
      expect(s.state.discovery.trustPending, 'lab');
    });

    test('another CA than the one shown is refused', () async {
      final net = lab();
      final s = await found(net);
      net.serve(
        ['https://10.0.7.20:8446'],
        info('lab', ca: plantCa, names: ['10.0.7.20']),
      );

      await s.dispatchAndWait(TrustGatewayAction('lab'));

      expect(s.state.discovery.pins, isEmpty);
      expect(s.state.discovery.trustRefused, TrustRefusal.changed);
    });

    test('a certificate that does not chain to the CA is refused', () async {
      final net = lab()..chainsTo['https://10.0.7.20:8446'] = plantCode;
      final s = await found(net);

      await s.dispatchAndWait(TrustGatewayAction('lab'));

      expect(s.state.discovery.pins, isEmpty);
      expect(s.state.discovery.trustRefused, TrustRefusal.chain);
    });

    test('a row whose code mismatches cannot be picked', () async {
      final net = lab();
      final s = discoveryStore(
        info: net,
        found: [
          announce('lab', '10.0.7.20', txt: {'fp': plantCode}),
        ],
      );
      await s.dispatchAndWait(FindGatewaysAction());
      await s.waitAllActions([], completeImmediately: true);

      await s.dispatchAndWait(PickFoundGatewayAction('lab'));

      expect(s.state.login.gateway, isNull);
      expect(s.state.discovery.trustPending, isNull);
    });

    test('a CA pinned for another site is known without the code', () async {
      final net = FakeInfo()
        ..serve(
          ['https://10.0.7.31:8446'],
          info('line3', ca: plantCa, names: ['10.0.7.31'], up: ['plant']),
        );
      final s = discoveryStore(
        info: net,
        found: [announce('line3', '10.0.7.31')],
        initial: AppState.initial().copyWith.discovery(
          pins: {
            'https://plant.local:8446': CaPin(
              origin: 'https://plant.local:8446',
              ca: base64Encode(plantCa),
              code: plantCode,
              site: 'plant',
            ),
          }.lock,
        ),
      );
      await s.dispatchAndWait(FindGatewaysAction());
      await s.waitAllActions([], completeImmediately: true);
      expect(s.state.discovery.found['line3']!.knownAs, 'plant');

      await s.dispatchAndWait(PickFoundGatewayAction('line3'));

      expect(s.state.discovery.trustPending, isNull);
      expect(s.state.discovery.pins.keys, contains('https://10.0.7.31:8446'));
    });

    test('the pins are stored whatever Remember says', () async {
      final storage = InMemoryKeyValueStorage();
      final persistor = AppPersistor(storage);
      final pins = {
        'https://gw.test:8446': const CaPin(
          origin: 'https://gw.test:8446',
          ca: 'AAEC',
          code: '00112233445566778899aabbccddeeff',
          site: 'lab',
          connectTo: '10.0.7.20',
        ),
      }.lock;
      final state = AppState.initial().copyWith
          .login(remember: false)
          .copyWith
          .discovery(pins: pins);

      await persistor.persistDifference(newState: state);
      final back = await persistor.readState();

      expect(back!.discovery.pins, pins);
      expect(back.login.gateway, isNull);
    });
  });

  group('over TLS', () {
    late HttpServer server;
    late Uri byName;
    late Uri byAddress;
    final caDer = derOf(testCaPem);

    setUp(() async {
      final ctx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(testChainPem))
        ..usePrivateKeyBytes(utf8.encode(testKeyPem));
      server = await HttpServer.bindSecure('127.0.0.1', 0, ctx)
        ..listen((r) {
          if (r.uri.path == '/api/info') {
            r.response
              ..headers.contentType = ContentType('application', 'cbor')
              ..add(
                VMap({
                  'site': const VStr('lab'),
                  'version': const VStr('0.1.0'),
                  'tls': const VBool(true),
                  'ca': VBytes(caDer),
                  'ca_fp': VStr(caCode(caDer)),
                  'names': const VArray([VStr('gw.test'), VStr('127.0.0.1')]),
                  'min_studio': const VStr('1.0.0'),
                }).toCbor(),
              );
          } else {
            r.response.statusCode = HttpStatus.unauthorized;
          }
          unawaited(r.response.close());
        });
      byName = Uri.parse('https://gw.test:${server.port}');
      byAddress = Uri.parse('https://127.0.0.1:${server.port}');
    });

    tearDown(() => server.close(force: true));

    CaPin pin(Uri at, {String? connectTo}) => CaPin(
      origin: at.origin,
      ca: base64Encode(caDer),
      code: caCode(caDer),
      site: 'lab',
      connectTo: connectTo,
    );

    test('an unknown CA is untrusted until it is pinned', () async {
      const reader = HttpInfoReader();

      await expectLater(
        reader.read(byAddress, trust: const GatewayTrust()),
        throwsA(
          isA<InfoFailure>().having(
            (f) => f.fault,
            'fault',
            InfoFault.untrusted,
          ),
        ),
      );
      final seen = await reader.readUnverified(byAddress);
      expect(seen.site, 'lab');
      expect(caCode(seen.ca!), caCode(caDer));

      final pinned = const GatewayTrust().plus([pin(byAddress)]);
      final ok = await reader.read(byAddress, trust: pinned);
      expect(ok.names, contains('127.0.0.1'));
    });

    test('a name that does not resolve connects to the address', () async {
      const reader = HttpInfoReader();
      final trust = const GatewayTrust().plus([
        pin(byName, connectTo: '127.0.0.1'),
      ]);

      final ok = await reader.read(byName, trust: trust);
      expect(ok.site, 'lab');

      // The name is checked: the address under another name is refused.
      final wrong = Uri.parse('https://other.test:${server.port}');
      await expectLater(
        reader.read(
          wrong,
          trust: const GatewayTrust().plus([
            pin(wrong, connectTo: '127.0.0.1'),
          ]),
        ),
        throwsA(isA<InfoFailure>()),
      );
    });

    test('a pin of another CA is refused', () async {
      const reader = HttpInfoReader();
      final other = derOf(otherCaPem);
      final trust = GatewayTrust(
        {
          byAddress.origin: CaPin(
            origin: byAddress.origin,
            ca: base64Encode(other),
            code: caCode(other),
          ),
        }.lock,
      );

      await expectLater(
        reader.read(byAddress, trust: trust),
        throwsA(
          isA<InfoFailure>().having(
            (f) => f.fault,
            'fault',
            InfoFault.untrusted,
          ),
        ),
      );
    });

    test('the log-in probe uses the pin of its origin', () async {
      final none = GatewayLogin(trust: () => const GatewayTrust());
      final pinned = GatewayLogin(
        trust: () => const GatewayTrust().plus([pin(byAddress)]),
      );

      final refused = await none.probe(byAddress);
      final answered = await pinned.probe(byAddress);

      expect(refused.answered, isFalse);
      expect(refused.reason, 'certificate is not trusted');
      expect(answered.answered, isTrue);
    });

    test('a found row over TLS is new until trusted', () async {
      final row = await checkFound(
        Announcement(
          name: 'lab',
          addresses: const ['127.0.0.1'],
          port: server.port,
          txt: {'site': 'lab', 'tls': '1', 'fp': caCode(caDer)},
        ),
        reader: const HttpInfoReader(),
        trust: const GatewayTrust(),
        now: 0,
      );

      expect(row!.problem, isNull);
      expect(row.url, byAddress.toString());
      expect(row.known, isFalse);
      expect(row.code, caCode(caDer));
    });
  });
}

/// The DER of the one certificate in [pem].
Uint8List derOf(String pem) => base64Decode(
  pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join(),
);

/// A store with the fake network and browse.
Store<AppState> discoveryStore({
  FakeInfo? info,
  List<Announcement> found = const [],
  AppState? initial,
}) => Store<AppState>(
  initialState: initial ?? AppState.initial(),
  dependencies: (s) => AppDependencies(
    s,
    InMemoryKeyValueStorage(),
    login: FakeLogin(),
    gatewayInfo: info ?? FakeInfo(),
    browser: FakeBrowser(found),
    browseDuration: Duration.zero,
  ),
);

/// A browse that finds [found] at once.
final class FakeBrowser implements GatewayBrowserBackend {
  FakeBrowser(this.found);

  final List<Announcement> found;

  @override
  Stream<Announcement> browse() {
    // Closed when the browse cancels it.
    // ignore: close_sinks
    late final StreamController<Announcement> c;
    c = StreamController<Announcement>(
      onListen: () {
        found.forEach(c.add);
      },
    );
    return c.stream;
  }
}

/// `/api/info` as a test sets it up, by origin.
final class FakeInfo implements GatewayInfoReader {
  final _infos = <String, GatewayInfo>{};
  final _failures = <String, InfoFailure>{};

  /// Origins whose certificate the system trusts without a pin.
  final trusted = <String>{};

  /// Origins whose certificate chains to a CA of another code than the one
  /// it sends.
  final chainsTo = <String, String>{};

  /// Every unverified read, by URL.
  final unverified = <Uri>[];

  Duration delay = Duration.zero;
  var _now = 0;

  /// The most reads at once.
  var most = 0;

  void serve(List<String> origins, GatewayInfo info) {
    for (final o in origins) {
      _infos[o] = info;
    }
  }

  void fail(String origin, InfoFault fault) =>
      _failures[origin] = InfoFailure(fault, fault.name);

  Future<GatewayInfo> _answer(Uri base) async {
    _now++;
    if (_now > most) {
      most = _now;
    }
    try {
      await Future<void>.delayed(delay);
      if (_failures[base.origin] case final f?) {
        throw f;
      }
      return _infos[base.origin] ??
          (throw const InfoFailure(InfoFault.noAnswer, 'timed out'));
    } finally {
      _now--;
    }
  }

  @override
  Future<GatewayInfo> read(
    Uri base, {
    required GatewayTrust trust,
    String? connectTo,
    Duration timeout = infoTimeout,
  }) async {
    final info = await _answer(base);
    final pin = trust.pinOf(base);
    final chain =
        chainsTo[base.origin] ?? (info.ca == null ? null : caCode(info.ca!));
    if (pin != null ? pin.code == chain : trusted.contains(base.origin)) {
      return info;
    }
    throw const InfoFailure(InfoFault.untrusted, 'CERTIFICATE_VERIFY_FAILED');
  }

  @override
  Future<GatewayInfo> readUnverified(
    Uri base, {
    String? connectTo,
    Duration timeout = infoTimeout,
  }) {
    unverified.add(base);
    return _answer(base);
  }

  @override
  Future<bool> resolves(String host) async => true;

  @override
  Future<LocalNetwork?> localNetwork() async =>
      const LocalNetwork('en0', '10.0.7.12');
}
