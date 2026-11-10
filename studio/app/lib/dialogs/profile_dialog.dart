import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/system/actions/put_profile_action.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/panel_dialog.dart';

import '../common/forms.dart';

/// `Put profile…` (System › Maintenance): asks for a file (`.cbor` or
/// `.json`) and a name, then calls `sys/profiles ▸ put`. The name of the
/// profile it put, or null when the user left or the broker refused.
Future<String?> putProfile(BuildContext context) async {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  final picked = await FilePicker.pickFiles(
    withData: true,
    type: FileType.custom,
    allowedExtensions: const ['cbor', 'json'],
  );
  final file = picked?.files.single;
  final bytes = file?.bytes;
  if (file == null || bytes == null || !context.mounted) {
    return null;
  }
  final dot = file.name.lastIndexOf('.');
  final base = dot > 0 ? file.name.substring(0, dot) : file.name;
  String? put;
  await showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.sysPut,
      width: 520,
      note: S.current.sysProfileFile(file.name),
      child: ActionForm(
        fields: [
          ParamFieldVm(
            id: 'name',
            label: S.current.sysProfileName,
            kind: ParamKind.text,
            value: base.contains(':') ? base : null,
            hint: S.current.sysProfileNameHint,
            required: true,
            onChanged: (_) {},
          ),
        ],
        submit: S.current.sysPut,
        onSubmit: (values) {
          final name = '${values['name'] ?? ''}'.trim();
          if (name.isEmpty) {
            return null;
          }
          return sendForm(
            store.dispatchAndWait(PutProfileAction(name, file.name, bytes)),
            onOk: () {
              put = name;
              if (dialog.mounted) {
                Navigator.of(dialog).pop();
              }
            },
          );
        },
      ),
    ),
  );
  return put;
}
