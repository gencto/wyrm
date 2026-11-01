// `ptok v1` claims (spec 04). Signing and checking stay on the Rust side;
// clients only need to read them.

import 'dart:typed_data';

import 'cbor.dart';
import 'tables.dart';
import 'value.dart';

class Grant {
  final String k;
  final Perm p;
  const Grant(this.k, this.p);
}

class PtokClaims {
  final String sub;
  final List<String> roles;
  final List<Grant> grants;
  final Perm max;
  final int iat;
  final int exp;

  /// 16 bytes.
  final Uint8List jti;
  final String site;

  /// The caller's full grant set (spec 04 0.2.10), on action tokens only; it never authorizes the
  /// request. `null` = not sent.
  final List<Grant>? auth;

  /// SHA-256 (32 bytes) of the one request payload the token is good for (spec 04 0.2.14).
  /// `null` = any payload.
  final Uint8List? args;

  const PtokClaims({
    required this.sub,
    required this.roles,
    required this.grants,
    required this.max,
    required this.iat,
    required this.exp,
    required this.jti,
    required this.site,
    this.auth,
    this.args,
  });

  Value toValue() => VMap({
        'sub': VStr(sub),
        'roles': VArray([for (final r in roles) VStr(r)]),
        'grants': VArray([
          for (final g in grants) VMap({'k': VStr(g.k), 'p': VInt(g.p.code)})
        ]),
        'max': VInt(max.code),
        'iat': VInt(iat),
        'exp': VInt(exp),
        'jti': VBytes(jti),
        'site': VStr(site),
        if (args case final args?) 'args': VBytes(args),
        if (auth case final auth?)
          'auth': VArray([
            for (final g in auth) VMap({'k': VStr(g.k), 'p': VInt(g.p.code)})
          ]),
      });

  static PtokClaims fromValue(Value v) {
    Never bad(String f) => throw CborError('ptok claims: bad $f');
    String text(String f) => switch (v[f]) { VStr(:final v) => v, _ => bad(f) };
    int uint(String f) => switch (v[f]) { VInt(:final v) when v >= 0 => v, _ => bad(f) };
    Perm perm(Value? x, String f) => switch (x) {
          VInt(:final v) => Perm.fromCode(v) ?? bad(f),
          _ => bad(f),
        };
    final roles = switch (v['roles']) {
      VArray(:final v) => [for (final r in v) r is VStr ? r.v : bad('roles')],
      _ => bad('roles'),
    };
    List<Grant> grantList(Value? x, String f) => switch (x) {
          VArray(:final v) => [
              for (final g in v)
                Grant(switch (g['k']) { VStr(:final v) => v, _ => bad('$f.k') }, perm(g['p'], '$f.p'))
            ],
          _ => bad(f),
        };
    final grants = grantList(v['grants'], 'grants');
    final auth = v['auth'] == null ? null : grantList(v['auth'], 'auth');
    final jti = switch (v['jti']) { VBytes(:final v) when v.length == 16 => v, _ => bad('jti') };
    final args = switch (v['args']) {
      null => null,
      VBytes(:final v) when v.length == 32 => v,
      _ => bad('args'),
    };
    return PtokClaims(
      sub: text('sub'),
      roles: roles,
      grants: grants,
      max: perm(v['max'], 'max'),
      iat: uint('iat'),
      exp: uint('exp'),
      jti: jti,
      site: text('site'),
      auth: auth,
      args: args,
    );
  }

  Uint8List toCbor() => toValue().toCbor();
  static PtokClaims fromCbor(List<int> b) => fromValue(Value.fromCbor(b));
}
