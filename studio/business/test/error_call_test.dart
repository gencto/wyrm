import 'package:flutter_test/flutter_test.dart';
import 'package:models/call_verb.dart';
import 'package:models/error_call.dart';
import 'package:models/known_call.dart';

/// The call of an error is typed where it is made; a wire name that
/// arrives as data is read once (studio-rules §2, §8).
void main() {
  test('every known call is found by its wire name, and by no other', () {
    for (final c in KnownCall.values) {
      expect(KnownCall.fromWire(c.wire), c);
      expect(ErrorCall.ofWire(c.wire), ErrorCall.known(c));
      expect(ErrorCall.ofWire(c.wire).name, c.wire);
      expect(ErrorCall.ofWire(c.wire).verb, c.verb);
    }
    expect(
      KnownCall.values.map((c) => c.wire).toSet().length,
      KnownCall.values.length,
      reason: 'no wire name twice',
    );
  });

  test('the verbs the titles are worded by', () {
    CallVerb verb(String wire) => ErrorCall.ofWire(wire).verb;
    expect(verb('deploy'), CallVerb.deploy);
    for (final w in [
      'install',
      'install_repo',
      'install_zip',
      'install_wasm',
    ]) {
      expect(verb(w), CallVerb.install);
    }
    expect(verb('set'), CallVerb.write);
    expect(verb('list'), CallVerb.list);
    for (final w in ['meta', 'subscribe', 'history', 'get_log', 'me']) {
      expect(verb(w), CallVerb.read);
    }
    for (final w in ['remove', 'remove_user', 'reject']) {
      expect(verb(w), CallVerb.remove);
    }
    for (final w in ['put', 'edit', 'update', 'save_user', 'grant', 'add']) {
      expect(verb(w), CallVerb.save);
    }
    expect(verb('start'), CallVerb.start);
    expect(verb('stop'), CallVerb.stop);
    expect(verb('open'), CallVerb.open);
    expect(verb('log_in'), CallVerb.logIn);
  });

  test('any other action is carried by its name and is run', () {
    final c = ErrorCall.ofWire('add_device');
    expect(c, const ErrorCall.named('add_device'));
    expect((c.name, c.verb, c.known), ('add_device', CallVerb.run, null));
    // a wire name is exact: no case folding, no trimming
    expect(ErrorCall.ofWire('Deploy').known, isNull);
    expect(ErrorCall.ofWire(' set').known, isNull);
  });
}
