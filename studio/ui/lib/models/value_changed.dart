import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';

// The shared shapes of what a widget reports (studio-rules §7). A widget or
// a view-model takes one of these instead of declaring its own
// `void Function(…)` field, so every callback of one meaning has one
// parameter order, one null meaning and one equality.
//
// The equality rule, once for all of them: a callback is behaviour, not
// data. A view-model leaves a callback that is always there out of `props`,
// and puts an optional one in as `onX != null` (whether the thing reacts is
// visible). The value a callback reports about — the selection of a
// [ToggleVm], the value of a [FieldVm] — is in `props`.

/// [item] changed to [value]: a field of a row (`onFieldChanged(id, text)`),
/// a panel's width (`onPanelWidth(side, width)`), the answer to a question
/// (`onPick(question, option)`). Use [ValueChanged] when there is no item.
typedef ItemChanged<K, V> = void Function(K item, V value);

/// [item] was turned [on] or off: a tick of a step, a pin of a field, a row
/// in or out of a set. With the set itself, take a [ToggleVm].
typedef Toggled<T> = void Function(T item, {required bool on});

/// The span from [start] to [end] was picked: a trend's or a timeline's
/// window (µs since the epoch).
typedef RangeChanged<T> = void Function(T start, T end);

/// An action on [row] of [owner]: a row of a flow block (`onRowAction(block,
/// row)`), a field of a node. The row is named by its id.
typedef RowAction<O, R> = void Function(O owner, R row);

/// [item] asks for its menu at [at] (global): a tree row's `⋯`, a right
/// click.
typedef ItemAt<T> = void Function(T item, Offset at);

/// Why [value] is refused, or null when it is taken: a check a widget runs
/// as the user types. [FormFieldValidator] is the same for a form field,
/// where the value may be null.
typedef Validate<T> = String? Function(T value);

/// A set the user ticks items in and out of: the [selected] items and the
/// [onToggle] that reports one change. The widget never changes the set
/// itself; the next [ToggleVm] carries the new one.
///
/// [selected] is in [props]; [onToggle] is behaviour and is not.
final class ToggleVm<T> extends Equatable {
  const ToggleVm({required this.selected, required this.onToggle});

  final ISet<T> selected;
  // Written out, not [Toggled]: `frx doctor` reads only Flutter's own
  // callback typedefs as behaviour in a view-model. Contravariant T in a
  // callback param, safe here — same as FieldVm.
  // ignore: unsafe_variance
  final void Function(T item, {required bool on}) onToggle;

  /// Whether [item] is ticked.
  bool contains(T item) => selected.contains(item);

  /// Reports [item] flipped.
  void toggle(T item) => onToggle(item, on: !selected.contains(item));

  // Equatable compares an `ISet` as an iterable, in order: the same items
  // added in another order compare unequal. That costs at most one extra
  // rebuild, never a lost one, and a selector builds a set in one order.
  @override
  List<Object?> get props => [selected];
}

/// View-model for a form field: the current [value], a fire-and-forget
/// [onChanged], an optional [validator] (the form runs it on submit), and an
/// optional [error] for server/async errors injected onto the field.
///
/// [onChanged] and [validator] are excluded from [props] — they are behavior,
/// not display, and are fresh closures each build; including them would break
/// VM equality and cause the connector to rebuild on every dispatch.
final class FieldVm<T> extends Equatable {
  const FieldVm({
    required this.value,
    required this.onChanged,
    this.validator,
    this.error,
    this.enabled = true,
  });

  final T value;
  // T in a callback param is contravariant; safe here — the VM is built and
  // passed through, never stored covariantly.
  // ignore: unsafe_variance
  final ValueChanged<T> onChanged;
  // Same as onChanged: contravariant T in a callback param, safe here.
  // ignore: unsafe_variance
  final FormFieldValidator<T>? validator;

  /// Server/async error shown on the field (via `forceErrorText`). Format
  /// validation stays in [validator].
  final String? error;
  final bool enabled;

  @override
  List<Object?> get props => [value, error, enabled];
}

/// One option in a [ChoiceVm].
///
/// [label] is data, not design: it is resolved where the locale and the domain
/// live — the connector — so `ui` never reaches for either.
final class ChoiceItemVm<T> extends Equatable {
  const ChoiceItemVm({required this.value, required this.label});

  final T value;
  final String label;

  @override
  List<Object?> get props => [value, label];
}

/// View-model for a field whose value is picked from a finite set.
///
/// Same contract as [FieldVm], plus the [items] to pick from. Use it when the
/// set is data (loaded, localized, user-specific); when the set is fixed by
/// design, the widget declares it instead — see `SegmentedControl.segments`.
///
/// [value] must be one of [items]; anything else renders as "nothing selected".
final class ChoiceVm<T> extends Equatable {
  const ChoiceVm({
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.error,
    this.enabled = true,
  });

  final T value;
  final List<ChoiceItemVm<T>> items;
  // Contravariant T in a callback param, safe here — same as FieldVm.
  // ignore: unsafe_variance
  final ValueChanged<T> onChanged;
  // Same as onChanged.
  // ignore: unsafe_variance
  final FormFieldValidator<T>? validator;
  final String? error;
  final bool enabled;

  @override
  List<Object?> get props => [value, items, error, enabled];
}
