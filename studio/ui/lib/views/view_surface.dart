import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart' as a2ui;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../charts/trend.dart';
import '../overlays/confirm_dialog.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'catalog/bind.dart';
import 'catalog/wyrm_catalog.dart';
import 'view_style.dart';

/// One action of a surface, as Studio took it: its name (`wyrm.set`,
/// `wyrm.invoke`, `wyrm.open`) and its context with every path resolved.
final class ViewActionVm extends Equatable {
  const ViewActionVm({
    required this.name,
    required this.context,
    required this.part,
  });

  final String name;
  final Map<String, Object?> context;

  /// The id of the component that fired it.
  final String part;

  @override
  List<Object?> get props => [name, context, part];
}

/// One WYRM view: a genui surface drawn from stored A2UI messages with the
/// catalog `wyrm:views/0.1`, no model and no conversation behind it
/// (docs/design/specs/genui-views.md).
///
/// - [messages] are the document's lines (JSON text, `version: v0.9`).
///   While a new list starts with the one already applied, only the lines
///   added reach the surface (a refine turn); any other list starts the
///   surface again.
/// - [data] is the surface's data model as path → value. Each entry that
///   changed is one `DataModel.update`; a path that is gone is written
///   null. Only the parts bound to a written path rebuild.
/// - Every action is taken by this widget's [ActionDelegate] before genui
///   sees it: a write asks first, then [onAction] is called; nothing goes
///   to `SurfaceController.onSubmit`.
class ViewSurface extends StatefulWidget {
  const ViewSurface({
    required this.surfaceId,
    required this.messages,
    required this.data,
    required this.density,
    required this.format,
    required this.onAction,
    this.padding,
    this.confirm,
    super.key,
  });

  final String surfaceId;
  final List<String> messages;
  final Map<String, Object?> data;
  final ViewDensity density;
  final TrendFormat format;
  final ValueChanged<ViewActionVm> onAction;

  /// Around the surface; the density's padding when null.
  final EdgeInsetsGeometry? padding;

  /// Asks before a write (tests answer without a dialog); the confirm
  /// dialog of the design system when null.
  final Future<bool> Function(BuildContext context, ViewActionVm action)?
  confirm;

  @override
  State<ViewSurface> createState() => ViewSurfaceState();
}

@visibleForTesting
class ViewSurfaceState extends State<ViewSurface> implements ActionDelegate {
  late SurfaceController _controller;
  late Widget _surface;
  StreamSubscription<ChatMessage>? _submitted;
  var _applied = <String>[];
  var _written = <String, Object?>{};

  /// What genui reported to the model side: validation errors and, if an
  /// action ever got past the delegate, that action. Shown by the lab.
  final submitted = <String>[];

  /// How many `DataModel.update` calls were made (the lab's Data tab).
  var writes = 0;

  @visibleForTesting
  SurfaceController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _controller = SurfaceController(catalogs: [wyrmCatalog()]);
    _submitted = _controller.onSubmit.listen((m) {
      submitted.addAll([
        for (final p in m.parts)
          if (p is DataPart) utf8.decode(p.bytes, allowMalformed: true),
      ]);
    });
    _applied = [];
    _written = {};
    // One widget per controller: a rebuild of this state (every batch of
    // values) then leaves the surface alone, and only the parts bound to a
    // written path build again.
    _surface = Surface(
      surfaceContext: _controller.contextFor(widget.surfaceId),
      actionDelegate: this,
      defaultBuilder: (context) => Text(
        S.current.viewsEmpty,
        style: boardText(size: 13, color: context.colors.text4),
      ),
    );
    _apply(widget.messages);
    _write(widget.data);
  }

  void _stop() {
    unawaited(_submitted?.cancel());
    _controller.dispose();
  }

  void _apply(List<String> lines) {
    for (final line in lines.skip(_applied.length)) {
      try {
        _controller.handleMessage(
          a2ui.A2uiMessage.fromJson(jsonDecode(line) as Map<String, dynamic>),
        );
      } on Object catch (e) {
        submitted.add('$e');
      }
    }
    _applied = List.of(lines);
  }

  void _write(Map<String, Object?> data) {
    if (!_controller.registry.hasSurface(widget.surfaceId)) {
      return;
    }
    final model = _controller.contextFor(widget.surfaceId).dataModel;
    void put(String path, Object? value) {
      try {
        model.update(DataPath(path), value);
        writes++;
      } on Object catch (e) {
        // A node with a value and with children that have values: the
        // model keeps a leaf at `/a/b` and cannot hold `/a/b/c` too.
        submitted.add('$path: $e');
      }
    }

    for (final MapEntry(key: path, :value) in data.entries) {
      if (!_written.containsKey(path) || _written[path] != value) {
        put(path, value);
      }
    }
    for (final path in _written.keys) {
      if (!data.containsKey(path)) {
        put(path, null);
        // An instance whose last entry went leaves an empty map, which a
        // template would still draw: take the empty parents out too.
        var parent = DataPath(path).dirname;
        while (parent.segments.isNotEmpty) {
          final Object? at;
          try {
            at = model.getValue<Object?>(parent);
          } on Object {
            break;
          }
          if (at is! Map || at.isNotEmpty) {
            break;
          }
          put(parent.toString(), null);
          parent = parent.dirname;
        }
      }
    }
    _written = Map.of(data);
  }

  @override
  void didUpdateWidget(ViewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lines = widget.messages;
    final grows =
        widget.surfaceId == oldWidget.surfaceId &&
        lines.length >= _applied.length &&
        listEquals(lines.sublist(0, _applied.length), _applied);
    if (!grows) {
      _stop();
      _start();
      return;
    }
    _apply(lines);
    _write(widget.data);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  bool handleEvent(
    BuildContext context,
    UiEvent event,
    SurfaceContext genUiContext,
    Widget Function(SurfaceDefinition, Catalog, String, DataContext)
    buildWidget,
  ) {
    if (event.isUserAction) {
      final action = UserActionEvent.fromMap(event.toMap());
      unawaited(
        _run(
          ViewActionVm(
            name: action.name,
            context: action.context,
            part: action.sourceComponentId,
          ),
        ),
      );
    }
    // Nothing of a WYRM view goes to a model.
    return true;
  }

  Future<void> _run(ViewActionVm action) async {
    if (action.name != 'wyrm.open') {
      final ask = widget.confirm ?? _ask;
      if (!await ask(context, action) || !mounted) {
        return;
      }
    }
    widget.onAction(
      ViewActionVm(
        name: action.name,
        part: action.part,
        context: {...action.context}
          ..remove(confirmEntry)
          ..remove(dangerEntry),
      ),
    );
  }

  static Future<bool> _ask(BuildContext context, ViewActionVm action) {
    final s = S.current;
    final c = action.context;
    final invoke = action.name == 'wyrm.invoke';
    return ConfirmDialog.ask(
      context,
      title: invoke ? s.viewsConfirmRunTitle : s.viewsConfirmSetTitle,
      message:
          c[confirmEntry] as String? ??
          (invoke
              ? s.viewsConfirmRun('${c['action']}', '${c['key']}')
              : s.viewsConfirmSet('${c['value']}', '${c['key']}')),
      confirm: invoke ? s.viewsRun : s.viewsWrite,
      cancel: s.viewsCancel,
      danger: c[dangerEntry] == true,
    );
  }

  @override
  Widget build(BuildContext context) => ViewScope(
    density: widget.density,
    format: widget.format,
    child: SingleChildScrollView(
      padding: widget.padding ?? EdgeInsets.all(widget.density.pad),
      child: _surface,
    ),
  );
}
