import 'package:async_redux/async_redux.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:models/error_kind.dart';
import 'package:models/fault_report.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

// One error model for every failure (docs/design/specs/errors.md §1): the
// kind of a status, the exception that carries a `StudioError` through the
// store, and the plain text of *Copy details*.

/// The kind of a broker status (spec 04). A status Studio does not know
/// (user-defined `0x40–0x4F`, an unknown code) is the broker's own business:
/// kind `broker`, with its code in Details. `ok`, `initializing` and
/// `refreshed` are not failures; one that arrives as an exception all the
/// same is the broker's fault too.
ErrorKind kindOf(StatusCode? status) => switch (status?.known) {
  null => status == null ? ErrorKind.studio : ErrorKind.broker,
  Status.permissionDenied => ErrorKind.rights,
  Status.timeout ||
  Status.disconnected ||
  Status.notAvailable ||
  Status.closed => ErrorKind.reach,
  Status.invalidParameter ||
  Status.invalidMessage ||
  Status.outOfRange => ErrorKind.input,
  Status.busy ||
  Status.rateLimited ||
  Status.resourceExhausted => ErrorKind.busy,
  Status.notFound || Status.notSupported => ErrorKind.gone,
  Status.internalError ||
  Status.ok ||
  Status.initializing ||
  Status.refreshed => ErrorKind.broker,
};

/// The broker (or the gateway) gave no answer in time, rather than saying
/// that something below it is not connected.
bool isTimeout(StudioError e) => e.status?.known == Status.timeout;

/// The call is one this broker or link does not have (`not_supported`),
/// rather than a thing that is gone.
bool isUnsupported(StudioError e) => e.status?.known == Status.notSupported;

/// `permission_denied (0x21)`: the status name with its code, for Details.
String statusLine(StatusCode status) {
  final hex = status.code.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '${status.name} (0x$hex)';
}

final _named = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_.\-]*)\s*:\s+\S');

/// The parameter a refusal names at its start (`poll_rate: 0 is below the
/// minimum of 100 ms.`), or null when the message does not begin with one.
String? fieldOf(String message) => _named.firstMatch(message)?.group(1);

/// The broker's [message] without the name of [field] it starts with: the
/// line under the field (`0 is below the minimum of 100 ms.`). The whole
/// message when nothing is left.
String saidOf(String message, String field) {
  final rest = message.replaceFirst(
    RegExp('^\\s*${RegExp.escape(field)}\\s*:\\s*'),
    '',
  );
  return rest.isEmpty ? message : rest;
}

/// The site of a full key (`wy/<site>/…`), or null.
String? siteOf(String? key) {
  final parts = key?.split('/') ?? const <String>[];
  return parts.length > 1 && parts.first == 'wy' ? parts[1] : null;
}

var _nextId = 0;

/// The next id of an error or a notice: they share one counter, so toasts
/// keep the order they came in.
int nextErrorId() => ++_nextId;

/// The error of a refused broker call. [call] is the wire name of what was
/// asked (`deploy`, `set`, `list`), [key] the key it was asked on, [thing]
/// the name of its object when the key's last segment is not it. [write]
/// says the call changes something: a timeout then may have been applied.
StudioError refusalOf(
  WyrmException e, {
  String? key,
  String? call,
  String? thing,
  bool write = false,
}) {
  final kind = kindOf(e.status);
  return StudioError(
    kind: kind,
    message: e.message,
    status: e.status,
    key: key,
    call: call,
    thing: thing,
    site: siteOf(key),
    write: write,
    field: kind == ErrorKind.input ? fieldOf(e.message) : null,
  );
}

/// The error of a fault in Studio itself: anything thrown that the broker
/// did not send. [step] names what ran (an action, a panel).
StudioError faultOf(
  Object error,
  StackTrace? stack, {
  String? step,
  String? screen,
}) => StudioError(
  kind: ErrorKind.studio,
  call: step,
  report: FaultReport(
    type: '${error.runtimeType}',
    line: faultLine(error),
    where: frameOf(stack) ?? step ?? '',
    screen: screen,
    stack: stack == null ? '' : redact('$stack'),
  ),
);

/// The first line of [error]'s text, at most 160 characters, with nothing
/// that looks like a secret. A `FormatException` shows its message and
/// offset only: its `source` is the value that did not parse.
String faultLine(Object error) {
  final text = switch (error) {
    FormatException(:final message, :final offset) =>
      'FormatException: $message'
          '${offset == null ? '' : ' (at offset $offset)'}',
    _ => '$error',
  };
  final first = text.split('\n').first.trim();
  final cut = first.length > 160 ? '${first.substring(0, 160)}…' : first;
  return redact(cut);
}

final _frame = RegExp(
  r'^#\d+\s+(.+?)\s+\(package:(?:app|business|ui|models|storage|localization)/(?:.*/)?([^/:)]+\.dart)',
  multiLine: true,
);

/// `flow_layout_mapper.dart › decode`: the first frame of [stack] inside
/// Studio's own packages, or null.
String? frameOf(StackTrace? stack) {
  final m = stack == null ? null : _frame.firstMatch('$stack');
  if (m == null) {
    return null;
  }
  final member = m
      .group(1)!
      .replaceAll(RegExp(r'<[^>]*>|\.<anonymous closure>'), '');
  return '${m.group(2)} › $member';
}

final _secretPair = RegExp(
  r'''((?:pass(?:word)?|pwd|secret|token|ptok|api[_-]?key|authorization|bearer)["']?\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;}\]]+)''',
  caseSensitive: false,
);
final _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]{8,}');
final _blob = RegExp('[A-Za-z0-9+/_-]{40,}={0,2}');

/// [text] with what looks like a secret masked: `password: …`, `token=…`,
/// `Bearer …`, and any run of 40 or more token characters. Details and
/// reports leave this computer; a value, a token or a password must not.
String redact(String text) => text
    .replaceAllMapped(_secretPair, (m) => '${m.group(1)}•••')
    .replaceAllMapped(_bearer, (m) => '${m.group(1)}•••')
    .replaceAll(_blob, '•••');

/// Who and where, for *Copy details*.
final class DetailsContext {
  const DetailsContext({
    this.user,
    this.role,
    this.gateway,
    this.studio = '',
  });

  final String? user;
  final String? role;
  final String? gateway;

  /// `0.3.0 (macOS 15.1)`.
  final String studio;
}

/// `2026-11-10 11:52:04`, local.
String stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// The plain text of *Copy details* (errors.md §3): title, key › call,
/// status (code), message, site, user (role), gateway URL, time, Studio
/// version and OS. A `StudioError` holds no value and no argument, so none
/// can be copied; the message and the report are [redact]ed. With
/// [report], the Dart type, first line and stack trace are added (*Copy
/// report*).
String detailsText(
  StudioError e,
  DetailsContext ctx, {
  bool report = false,
}) {
  final r = e.report;
  final lines = <String>[
    e.title,
    if (e.where.isNotEmpty) e.where,
    if (e.status case final s?) 'Status: ${statusLine(s)}',
    if (e.message.isNotEmpty) 'Message: ${redact(e.message)}',
    if (e.site case final s?) 'Site: $s',
    if (ctx.user case final u? when u.isNotEmpty)
      'As: $u${ctx.role == null || ctx.role!.isEmpty ? '' : ' (${ctx.role})'}',
    if (ctx.gateway case final g? when g.isNotEmpty)
      'Gateway: ${_noUserInfo(g)}',
    if (e.at case final t?) 'Time: ${stamp(t)} (local)',
    if (ctx.studio.isNotEmpty) 'Studio: ${ctx.studio}',
    if (r != null) ...[
      'Error: ${r.line}',
      if (r.where.isNotEmpty) 'In: ${r.where}',
      if (r.screen case final s?) 'Screen: $s',
    ],
    if (report && r != null && r.stack.isNotEmpty) ...['', r.stack.trimRight()],
  ];
  return lines.join('\n');
}

/// A gateway URL without `user:password@`.
String _noUserInfo(String url) {
  final u = Uri.tryParse(url);
  return u == null || u.userInfo.isEmpty
      ? url
      : u.replace(userInfo: '').toString();
}

/// Fills what only the app can say: the title (from kind, call, thing and
/// site) and, for a fault in Studio, the sentence shown as its message.
/// The app supplies it, because `business` never names a locale.
typedef ErrorWording = StudioError Function(StudioError error);

/// Words for when no [ErrorWording] is given (tests): plain English.
StudioError plainWording(StudioError e) {
  if (e.title.isNotEmpty) {
    return e;
  }
  final thing = e.thing ?? e.key?.split('/').last;
  final what = [?e.call, ?thing].join(' ');
  return e.copyWith(
    title: switch (e.kind) {
      ErrorKind.studio => 'Studio could not finish ${e.call ?? 'this'}',
      _ => what.isEmpty ? 'The call failed' : '$what failed',
    },
  );
}

/// A [StudioError] on its way through the store: a [UserException], so the
/// observer, the error queue and `onOk` / `onCancel` work as before, with
/// the error as data instead of text (`UserException.code` is an `int` and
/// cannot hold it).
class StudioException extends UserException {
  StudioException(
    this.error, {
    super.ifOpenDialog,
    super.errorText,
    this.onOk,
    this.onCancel,
  }) : super(
         error.title.isEmpty ? null : error.title,
         reason: error.message.isEmpty ? null : error.message,
       );

  /// A refused broker call.
  StudioException.refused(
    WyrmException e, {
    String? key,
    String? call,
    String? thing,
    bool write = false,
  }) : this(refusalOf(e, key: key, call: call, thing: thing, write: write));

  /// Something Studio itself found wrong before or after a call, said in
  /// [title] (what did not happen) and [message].
  StudioException.studio(String title, {String message = '', String? call})
    : this(
        StudioError(
          kind: ErrorKind.studio,
          title: title,
          message: message,
          call: call,
        ),
      );

  /// Something that is wrong without a status from the broker, in its own
  /// words: an answer that says no, a file Studio cannot read, a thing that
  /// is not there. The title comes from [kind], [call] and [thing] like any
  /// other.
  StudioException.said(
    ErrorKind kind,
    String message, {
    String? key,
    String? call,
    String? thing,
    bool write = false,
  }) : this(
         StudioError(
           kind: kind,
           message: message,
           key: key,
           call: call,
           thing: thing,
           site: siteOf(key),
           write: write,
         ),
       );

  final StudioError error;

  /// Run when the dialog's main button closes it, or its Cancel.
  final VoidCallback? onOk;
  final VoidCallback? onCancel;

  /// The same exception around a changed [error].
  StudioException withError(StudioError error, {bool? ifOpenDialog}) =>
      StudioException(
        error,
        ifOpenDialog: ifOpenDialog ?? this.ifOpenDialog,
        errorText: errorText,
        onOk: onOk,
        onCancel: onCancel,
      );

  @override
  UserException addReason(String? reason) => reason == null
      ? this
      : withError(
          error.copyWith(
            message: UserException.joinCauses(error.message, reason),
          ),
        );

  @override
  UserException mergedWith(UserException? anotherUserException) {
    final other = anotherUserException;
    if (other == null) {
      return this;
    }
    final (title, content) = other.titleAndContent();
    final merged =
        addReason(UserException.joinCauses(title, content)) as StudioException;
    return merged.withError(
      merged.error,
      ifOpenDialog: ifOpenDialog && other.ifOpenDialog,
    );
  }

  /// No dialog: the screen that started the call shows the failure itself
  /// (the log-in page). It is still a line in Problems; it is not `quiet`,
  /// so it raises no toast.
  @override
  UserException withDialog(bool ifOpenDialog) =>
      withError(error, ifOpenDialog: ifOpenDialog);

  @override
  UserException withErrorText(String? newErrorText) => StudioException(
    error,
    ifOpenDialog: ifOpenDialog,
    errorText: newErrorText,
    onOk: onOk,
    onCancel: onCancel,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioException &&
          error == other.error &&
          ifOpenDialog == other.ifOpenDialog &&
          errorText == other.errorText;

  @override
  int get hashCode => Object.hash(error, ifOpenDialog, errorText);

  @override
  String toString() =>
      'StudioException(${error.kind.name}'
      '${error.status == null ? '' : ' ${error.status!.name}'}: '
      '${error.title}${error.where.isEmpty ? '' : ' [${error.where}]'}'
      '${error.message.isEmpty ? '' : ': ${redact(error.message)}'})';
}

/// [error] as a [StudioException], whatever it was: a refusal thrown raw by
/// the client, a plain `UserException` of a package (kind `studio`, its
/// title and reason kept, no report), or any other object (a fault, with
/// its report). [step] names what ran.
StudioException studioExceptionOf(
  Object error,
  StackTrace? stack, {
  String? step,
}) => switch (error) {
  final StudioException e => e,
  final WyrmException e => StudioException.refused(e),
  final UserException e => _plain(e),
  _ => StudioException(faultOf(error, stack, step: step)),
};

StudioException _plain(UserException e) {
  final (title, content) = e.titleAndContent();
  return StudioException(
    StudioError(
      kind: ErrorKind.studio,
      title: title.isEmpty ? content : title,
      message: title.isEmpty ? '' : content,
    ),
    ifOpenDialog: e.ifOpenDialog,
    errorText: e.errorText,
    onOk: e.onOk,
    onCancel: e.onCancel,
  );
}
