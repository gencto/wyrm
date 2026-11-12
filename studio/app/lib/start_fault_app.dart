import 'dart:async';
import 'dart:io';

import 'package:business/redux/store.dart';
import 'package:business/wyrm/failures.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/error_kind.dart';
import 'package:models/fault_report.dart';
import 'package:models/studio_error.dart';
import 'package:ui/alerts/start_fault.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/theme/common.dart';

import 'errors.dart';

/// The app shown instead of Studio when its own settings do not open
/// (docs/design/specs/errors.md §6): one screen, no store, no router.
///
/// *Start with fresh settings* moves the unreadable file aside as
/// `<name>.broken` and calls [onFresh], which starts Studio normally. No
/// other condition shows this: a gateway that does not answer is the
/// log-in screen's job.
class StartFaultApp extends StatefulWidget {
  const StartFaultApp({
    required this.fault,
    required this.onFresh,
    this.onQuit,
    super.key,
  });

  final StorageFault fault;

  /// The file is aside: start again.
  final Future<void> Function() onFresh;

  /// *Quit*; leaves the app when null.
  final VoidCallback? onQuit;

  @override
  State<StartFaultApp> createState() => _StartFaultAppState();
}

class _StartFaultAppState extends State<StartFaultApp> {
  var _busy = false;
  String? _failed;

  String get _file => switch (widget.fault.path) {
    final p? => p.split(Platform.pathSeparator).last,
    null => settingsFile,
  };

  /// The path with the home directory as `~`: a report must not carry the
  /// user's name.
  String get _shownPath {
    final p = widget.fault.path ?? settingsFile;
    final home = Platform.environment['HOME'] ?? '';
    return home.isNotEmpty && p.startsWith(home)
        ? '~${p.substring(home.length)}'
        : p;
  }

  Future<void> _fresh() async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      if (widget.fault.path case final p? when File(p).existsSync()) {
        await setAsideSettings(p);
      }
      await widget.onFresh();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = S.current.fatalMoveFailed(faultLine(e));
        });
      }
    }
  }

  void _copy() {
    final e = StudioError(
      kind: ErrorKind.studio,
      title: S.current.fatalTitle,
      message: S.current.fatalBody,
      at: DateTime.now(),
      report: FaultReport(
        type: '${widget.fault.error.runtimeType}',
        line: faultLine(widget.fault.error),
        where: _shownPath,
        stack: redact('${widget.fault.stack}'),
      ),
    );
    unawaited(
      Clipboard.setData(
        ClipboardData(
          text: detailsText(
            e,
            DetailsContext(studio: studioAbout),
            report: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: lightTheme(),
    darkTheme: darkTheme(),
    themeMode: .dark,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    home: Builder(
      builder: (context) {
        final s = S.of(context);
        return Scaffold(
          body: StartFault(
            vm: StartFaultVm(
              title: s.fatalTitle,
              body: s.fatalBody,
              rows: [
                ErrorRowVm(s.errRowError, faultLine(widget.fault.error)),
                ErrorRowVm(s.fatalFile, _shownPath),
                ErrorRowVm(s.errRowStudio, studioAbout),
              ],
              note: s.fatalNote('$_file.broken'),
              noteCode: '$_file.broken',
              fresh: s.fatalFresh,
              copy: s.errCopyReport,
              quit: s.fatalQuit,
              failed: _failed,
              busy: _busy,
            ),
            onFresh: () => unawaited(_fresh()),
            onCopy: _copy,
            onQuit: widget.onQuit ?? () => exit(0),
          ),
        );
      },
    ),
  );
}
