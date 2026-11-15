import 'package:equatable/equatable.dart';

import '../overlays/value_viewer.dart';
import 'field_inspector.dart';

/// The viewer the flow editor has open: a field's value, or the name of a
/// block's form.
sealed class FlowViewerVm extends Equatable {
  const FlowViewerVm();

  /// What the [ValueViewer] draws.
  ValueViewerVm get vm;
}

/// The viewer of a field's value.
final class FieldViewerVm extends FlowViewerVm {
  const FieldViewerVm(this.vm);

  @override
  final ValueViewerVm vm;

  @override
  List<Object?> get props => [vm];
}

/// The viewer of the Form row of block [block]: the form's name.
final class FormViewerVm extends FlowViewerVm {
  const FormViewerVm(this.block, this.form);

  final String block;
  final BlockFormVm form;

  @override
  ValueViewerVm get vm =>
      ValueViewerVm.text(title: '$block.form', text: form.label);

  @override
  List<Object?> get props => [block, form];
}
