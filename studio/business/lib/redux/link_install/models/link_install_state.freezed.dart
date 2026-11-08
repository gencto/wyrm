// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'link_install_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinkInstallState {

 int get step; InstallSource? get source; String? get item; String? get broker; LinkMode? get mode; String? get name; bool get acceptRights; IList<PackageCheck> get checks; String? get message;
/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkInstallStateCopyWith<LinkInstallState> get copyWith => _$LinkInstallStateCopyWithImpl<LinkInstallState>(this as LinkInstallState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkInstallState&&(identical(other.step, step) || other.step == step)&&(identical(other.source, source) || other.source == source)&&(identical(other.item, item) || other.item == item)&&(identical(other.broker, broker) || other.broker == broker)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.name, name) || other.name == name)&&(identical(other.acceptRights, acceptRights) || other.acceptRights == acceptRights)&&const DeepCollectionEquality().equals(other.checks, checks)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,step,source,item,broker,mode,name,acceptRights,const DeepCollectionEquality().hash(checks),message);

@override
String toString() {
  return 'LinkInstallState(step: $step, source: $source, item: $item, broker: $broker, mode: $mode, name: $name, acceptRights: $acceptRights, checks: $checks, message: $message)';
}


}

/// @nodoc
abstract mixin class $LinkInstallStateCopyWith<$Res>  {
  factory $LinkInstallStateCopyWith(LinkInstallState value, $Res Function(LinkInstallState) _then) = _$LinkInstallStateCopyWithImpl;
@useResult
$Res call({
 int step, InstallSource? source, String? item, String? broker, LinkMode? mode, String? name, bool acceptRights, IList<PackageCheck> checks, String? message
});


$InstallSourceCopyWith<$Res>? get source;

}
/// @nodoc
class _$LinkInstallStateCopyWithImpl<$Res>
    implements $LinkInstallStateCopyWith<$Res> {
  _$LinkInstallStateCopyWithImpl(this._self, this._then);

  final LinkInstallState _self;
  final $Res Function(LinkInstallState) _then;

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? step = null,Object? source = freezed,Object? item = freezed,Object? broker = freezed,Object? mode = freezed,Object? name = freezed,Object? acceptRights = null,Object? checks = null,Object? message = freezed,}) {
  return _then(_self.copyWith(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as InstallSource?,item: freezed == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as String?,broker: freezed == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String?,mode: freezed == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,acceptRights: null == acceptRights ? _self.acceptRights : acceptRights // ignore: cast_nullable_to_non_nullable
as bool,checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as IList<PackageCheck>,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstallSourceCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $InstallSourceCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}



/// @nodoc


class _LinkInstallState implements LinkInstallState {
  const _LinkInstallState({this.step = 1, this.source, this.item, this.broker, this.mode, this.name, this.acceptRights = false, this.checks = const IListConst([]), this.message});
  

@override@JsonKey() final  int step;
@override final  InstallSource? source;
@override final  String? item;
@override final  String? broker;
@override final  LinkMode? mode;
@override final  String? name;
@override@JsonKey() final  bool acceptRights;
@override@JsonKey() final  IList<PackageCheck> checks;
@override final  String? message;

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LinkInstallStateCopyWith<_LinkInstallState> get copyWith => __$LinkInstallStateCopyWithImpl<_LinkInstallState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LinkInstallState&&(identical(other.step, step) || other.step == step)&&(identical(other.source, source) || other.source == source)&&(identical(other.item, item) || other.item == item)&&(identical(other.broker, broker) || other.broker == broker)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.name, name) || other.name == name)&&(identical(other.acceptRights, acceptRights) || other.acceptRights == acceptRights)&&const DeepCollectionEquality().equals(other.checks, checks)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,step,source,item,broker,mode,name,acceptRights,const DeepCollectionEquality().hash(checks),message);

@override
String toString() {
  return 'LinkInstallState(step: $step, source: $source, item: $item, broker: $broker, mode: $mode, name: $name, acceptRights: $acceptRights, checks: $checks, message: $message)';
}


}

/// @nodoc
abstract mixin class _$LinkInstallStateCopyWith<$Res> implements $LinkInstallStateCopyWith<$Res> {
  factory _$LinkInstallStateCopyWith(_LinkInstallState value, $Res Function(_LinkInstallState) _then) = __$LinkInstallStateCopyWithImpl;
@override @useResult
$Res call({
 int step, InstallSource? source, String? item, String? broker, LinkMode? mode, String? name, bool acceptRights, IList<PackageCheck> checks, String? message
});


@override $InstallSourceCopyWith<$Res>? get source;

}
/// @nodoc
class __$LinkInstallStateCopyWithImpl<$Res>
    implements _$LinkInstallStateCopyWith<$Res> {
  __$LinkInstallStateCopyWithImpl(this._self, this._then);

  final _LinkInstallState _self;
  final $Res Function(_LinkInstallState) _then;

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? step = null,Object? source = freezed,Object? item = freezed,Object? broker = freezed,Object? mode = freezed,Object? name = freezed,Object? acceptRights = null,Object? checks = null,Object? message = freezed,}) {
  return _then(_LinkInstallState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as InstallSource?,item: freezed == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as String?,broker: freezed == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String?,mode: freezed == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,acceptRights: null == acceptRights ? _self.acceptRights : acceptRights // ignore: cast_nullable_to_non_nullable
as bool,checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as IList<PackageCheck>,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of LinkInstallState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstallSourceCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $InstallSourceCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

// dart format on
