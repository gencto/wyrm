import 'package:business/redux/app_state.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/grant.dart';

class _Reader with Selectors {
  _Reader(this.state);

  @override
  final AppState state;
}

void main() {
  group('SelectSite rights', () {
    final r = _Reader(
      AppState.initial().copyWith.site(
        name: 'central',
        grants: const [
          Grant(key: 'wy/central/downstream/**', level: 'write'),
          Grant(key: 'wy/central/sys/links', level: 'read'),
          Grant(key: 'wy/edge/**', level: 'config'),
        ].lock,
      ),
    );

    test('the highest matching grant wins', () {
      expect(r.site.levelOn('wy/central/downstream/modbus/a'), 'write');
      expect(r.site.levelOn('wy/central/sys/links'), 'read');
      expect(r.site.levelOn('wy/edge/sys'), 'config');
      expect(r.site.levelOn('wy/central/sys'), 'none');
    });

    test('a missing level is a reason, never a hidden control', () {
      expect(
        r.site.needs('config', 'wy/central/sys/links'),
        'needs config on sys/links',
      );
      expect(r.site.needs('write', 'wy/central/downstream/x'), isNull);
    });

    test('the viewed site defaults to the one logged into', () {
      expect(r.site.root, 'wy/central');
      final there = _Reader(r.state.copyWith.site(current: 'plant'));
      expect(there.site.root, 'wy/plant');
      expect(there.site.home, 'wy/central');
    });
  });
}
