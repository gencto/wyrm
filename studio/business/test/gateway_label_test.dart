import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/probe_gateway_action.dart';
import 'package:business/wyrm/gateway_label.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_wyrm.dart';

/// The gateway labels of the log-in page (docs/design/specs/login.md §3.2
/// "Gateway labels").
void main() {
  List<String> labels(List<String> gateways) {
    final all = [for (final g in gateways) Uri.parse(g)];
    return [for (final g in all) gatewayLabel(g, all)];
  }

  test('Uri drops a default port: hasPort is false', () {
    expect(Uri.parse('https://plant.local:443').hasPort, isFalse);
    expect(Uri.parse('http://plant.local:80').hasPort, isFalse);
    expect(Uri.parse('https://plant.local:8443').hasPort, isTrue);
    expect(Uri.parse('https://plant.local:443').port, 443);
  });

  test('five gateways on one address get five labels', () {
    final got = labels([
      'http://127.0.0.1:8444',
      'http://127.0.0.1:8445',
      'http://127.0.0.1:8446',
      'http://127.0.0.1:18448',
      'http://127.0.0.1:18449',
    ]);
    expect(got, [
      '127.0.0.1:8444',
      '127.0.0.1:8445',
      '127.0.0.1:8446',
      '127.0.0.1:18448',
      '127.0.0.1:18449',
    ]);
  });

  test('a lone gateway shows a port that is not the default', () {
    expect(labels(['https://plant.local:8446']), ['plant:8446']);
    expect(labels(['http://127.0.0.1:8445']), ['127.0.0.1:8445']);
  });

  test('a lone gateway on the default port is its short host', () {
    expect(labels(['https://plant.local']), ['plant']);
    expect(labels(['https://plant.local:443']), ['plant']);
    expect(labels(['https://edge.local', 'https://central.example']), [
      'edge',
      'central',
    ]);
  });

  test('a shared host shows the default port too', () {
    expect(labels(['https://plant.local', 'https://plant.local:8443']), [
      'plant:443',
      'plant:8443',
    ]);
  });

  test('the same short name on two hosts is the whole host name', () {
    expect(labels(['https://plant.local', 'https://plant.example']), [
      'plant.local',
      'plant.example',
    ]);
  });

  test('the same host and port with two schemes shows the scheme', () {
    expect(labels(['http://plant.local:8445', 'https://plant.local:8445']), [
      'http://plant:8445',
      'https://plant:8445',
    ]);
  });

  test('an IPv6 address with a port is in brackets', () {
    expect(labels(['http://[::1]:8445']), ['[::1]:8445']);
  });

  test('one origin written twice is one gateway', () {
    final all = [Uri.parse('http://127.0.0.1'), Uri.parse('http://127.0.0.1')];
    expect(gatewayLabel(all.first, all), '127.0.0.1');
  });

  test('the field and the recent gateways are labelled together', () {
    final state = AppState.initial().copyWith.login(
      recent: const ['http://127.0.0.1:8444', 'http://127.0.0.1'].lock,
      gateway: 'https://plant.local, https://edge.local:8444',
    );
    final got = SelectLogin(state).gatewayLabels;
    expect(
      got,
      {
        'http://127.0.0.1:8444': '127.0.0.1:8444',
        'http://127.0.0.1': '127.0.0.1:80',
        'https://plant.local': 'plant',
      }.lock,
    );
    expect(
      got[gatewayKey(addressOf(Uri.parse('https://plant.local')))],
      'plant',
    );
  });

  test('without a gateway written, the default is labelled', () {
    final state = AppState.initial().copyWith.login(
      recent: const ['http://127.0.0.1:8446'].lock,
    );
    expect(
      SelectLogin(state).gatewayLabels,
      {
        'http://127.0.0.1:8446': '127.0.0.1:8446',
        'http://127.0.0.1:8445': '127.0.0.1:8445',
      }.lock,
    );
    expect(defaultGateway, 'http://127.0.0.1:8445');
  });
}
