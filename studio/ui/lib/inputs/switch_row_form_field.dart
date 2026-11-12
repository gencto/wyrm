import 'package:material_ui/material_ui.dart';

import '../models/value_changed.dart';
import 'choice_form_field.dart';

// TODO(frx): describe what this picks. Its items are data — the connector
// resolves their labels, where the locale and the domain live.
class SwitchRowFormField extends StatelessWidget {
  const SwitchRowFormField({required this.vm, super.key});

  final ChoiceVm<String?> vm;

  @override
  Widget build(BuildContext context) => ChoiceFormField<String?>(
    vm: vm,
    // TODO(frx): the label belongs in localization — S.current.
    labelText: 'SwitchRow',
  );
}
