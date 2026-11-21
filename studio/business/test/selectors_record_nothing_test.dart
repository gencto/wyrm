import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/mappers/live_overlay_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/attention_item.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_status.dart';
import 'package:models/link_info.dart';
import 'package:models/link_state.dart';
import 'package:models/live_value.dart';
import 'package:models/quarantine_entry.dart';

class _Sel with Selectors {
  _Sel(this.state);

  @override
  final AppState state;
}

const _root = 'wy/plant';

LiveValue _live(Object? value) =>
    LiveValue(value: value, time: DateTime.utc(2026));

/// A selector runs on every rebuild and records nothing (re-audit of
/// #135): a live value that is not of its shape is recorded once, in the
/// batch it arrives in (`warnUnreadLive`), and the selector keeps the
/// last value read.
void main() {
  final warned = <String>[];
  setUpAll(() {
    Logger.root.level = Level.ALL;
    decodeLog.onRecord.listen((r) => warned.add(r.message));
  });
  setUp(warned.clear);

  final bad = <String, LiveValue>{
    '$_root/sys/links/modbus/state': _live('exploded'),
    '$_root/sys/links/modbus/restore_points': _live('none'),
    '$_root/sys/backups/b1/status': _live('melting'),
    '$_root/sys/backups/b1/progress': _live('half'),
  };

  AppState state() {
    final s = AppState.initial();
    return s.copyWith(
      site: s.site.copyWith(name: 'plant', connected: true),
      links: s.links.copyWith(
        table: const {
          'modbus': LinkInfo(id: 'modbus', state: LinkState.connected),
        }.lock,
        view: const ['modbus'].lock,
      ),
      backups: s.backups.copyWith(
        table: const {
          'b1': BackupJob(id: 'b1', status: BackupStatus.running, progress: 40),
        }.lock,
        view: const ['b1'].lock,
      ),
      live: s.live.copyWith(values: bad.lock),
    );
  }

  test('reading live values of another shape records nothing, and keeps '
      'what was read', () {
    final s = state();
    for (var i = 0; i < 5; i++) {
      // a new reader each time: nothing is kept between them
      final sel = _Sel(s.copyWith.clock(now: DateTime.utc(2026, 1, 1, 0, i)));
      expect(sel.stateOfLink(s.links.table['modbus']!), LinkState.connected);
      expect(sel.restorePointsOfLink('modbus'), isEmpty);
      final job = sel.backupJob('b1')!;
      expect((job.status, job.progress), (BackupStatus.running, 40));
      expect(sel.stagedAgentParamsOf('$_root/sys/links/agent'), isNull);
    }
    expect(warned, isEmpty);
  });

  test('the batch the values arrive in records each once, with its '
      'field', () {
    warnUnreadLive(bad, _root);
    expect(warned, [
      'sys/links/modbus/state: link state.: not a known name',
      'sys/links/modbus/restore_points: restore points.: not a list',
      '$_root/sys/backups/b1: backup.status: not a known name',
      '$_root/sys/backups/b1: backup.progress: not a whole number',
    ]);

    // values of their shape, and a value removed, record nothing
    warned.clear();
    warnUnreadLive({
      '$_root/sys/links/modbus/state': _live('connected'),
      '$_root/sys/links/modbus/restore_points': _live(const <Object?>[]),
      '$_root/sys/backups/b1/status': _live('done'),
      '$_root/sys/backups/b1/progress': null,
      // a leaf the screens do not read
      '$_root/sys/links/modbus/log_level': _live(7),
    }, _root);
    expect(warned, isEmpty);
  });

  test('a row of restore points that is none is recorded on arrival '
      'only', () {
    final rows = _live([
      {'at': 1794100000, 'size': 10, 'version': '0.4.2'},
      'a row',
      {'at': 'then', 'size': 10},
    ]);
    final s = state().copyWith.live(
      values: {'$_root/sys/links/modbus/restore_points': rows}.lock,
    );
    expect(_Sel(s).restorePointsOfLink('modbus'), hasLength(1));
    expect(warned, isEmpty);

    warnUnreadLive({'$_root/sys/links/modbus/restore_points': rows}, _root);
    expect(warned, hasLength(2));
    expect(warned.first, contains('a row is not a map'));
  });

  test('what waits in quarantine and was not read is in the attention '
      'list', () {
    final s = AppState.initial();
    final sel = _Sel(
      s.copyWith.quarantine(
        table: const {
          'plc': QuarantineEntry.link(cn: 'link:plc', node: 'plc'),
          'gw-9': QuarantineEntry.notRead(cn: 'gateway:gw-9', node: 'gw-9'),
          // an entry that was not read is not known to be held: one held
          // back is a link (or a broker) Deauthorize holds
          'held': QuarantineEntry.link(
            cn: 'x',
            node: 'held',
            deauthorized: true,
          ),
        }.lock,
        view: const ['plc', 'gw-9', 'held'].lock,
      ),
    );
    final items = sel.attention;
    expect(
      items,
      contains(const AttentionItem.quarantine(node: 'plc', cn: 'link:plc')),
    );
    expect(
      items,
      contains(
        const AttentionItem.waitingNotRead(node: 'gw-9', cn: 'gateway:gw-9'),
      ),
    );
    // it is one card, of its own kind: neither a link nor a broker
    expect(items.where((i) => _nodeOf(i) == 'gw-9'), hasLength(1));
    // one that is held back does not wait
    expect(items.where((i) => _nodeOf(i) == 'held'), isEmpty);
  });
}

/// The node under `sys/quarantine` a card is about; null for the others.
String? _nodeOf(AttentionItem item) => switch (item) {
  AttentionQuarantine(:final node) ||
  AttentionBrokerWaiting(:final node) ||
  AttentionWaitingNotRead(:final node) => node,
  AttentionStandbyBehind() ||
  AttentionLinkFailed() ||
  AttentionAclGrown() ||
  AttentionNoStandby() => null,
};
