// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'window_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WindowState {

 bool get maximized; bool get fullScreen; double? get left; double? get top; double? get width; double? get height;
/// Create a copy of WindowState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WindowStateCopyWith<WindowState> get copyWith => _$WindowStateCopyWithImpl<WindowState>(this as WindowState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WindowState&&(identical(other.maximized, maximized) || other.maximized == maximized)&&(identical(other.fullScreen, fullScreen) || other.fullScreen == fullScreen)&&(identical(other.left, left) || other.left == left)&&(identical(other.top, top) || other.top == top)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode => Object.hash(runtimeType,maximized,fullScreen,left,top,width,height);

@override
String toString() {
  return 'WindowState(maximized: $maximized, fullScreen: $fullScreen, left: $left, top: $top, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class $WindowStateCopyWith<$Res>  {
  factory $WindowStateCopyWith(WindowState value, $Res Function(WindowState) _then) = _$WindowStateCopyWithImpl;
@useResult
$Res call({
 bool maximized, bool fullScreen, double? left, double? top, double? width, double? height
});




}
/// @nodoc
class _$WindowStateCopyWithImpl<$Res>
    implements $WindowStateCopyWith<$Res> {
  _$WindowStateCopyWithImpl(this._self, this._then);

  final WindowState _self;
  final $Res Function(WindowState) _then;

/// Create a copy of WindowState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? maximized = null,Object? fullScreen = null,Object? left = freezed,Object? top = freezed,Object? width = freezed,Object? height = freezed,}) {
  return _then(_self.copyWith(
maximized: null == maximized ? _self.maximized : maximized // ignore: cast_nullable_to_non_nullable
as bool,fullScreen: null == fullScreen ? _self.fullScreen : fullScreen // ignore: cast_nullable_to_non_nullable
as bool,left: freezed == left ? _self.left : left // ignore: cast_nullable_to_non_nullable
as double?,top: freezed == top ? _self.top : top // ignore: cast_nullable_to_non_nullable
as double?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}



/// @nodoc


class _WindowState implements WindowState {
  const _WindowState({this.maximized = false, this.fullScreen = false, this.left, this.top, this.width, this.height});
  

@override@JsonKey() final  bool maximized;
@override@JsonKey() final  bool fullScreen;
@override final  double? left;
@override final  double? top;
@override final  double? width;
@override final  double? height;

/// Create a copy of WindowState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WindowStateCopyWith<_WindowState> get copyWith => __$WindowStateCopyWithImpl<_WindowState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WindowState&&(identical(other.maximized, maximized) || other.maximized == maximized)&&(identical(other.fullScreen, fullScreen) || other.fullScreen == fullScreen)&&(identical(other.left, left) || other.left == left)&&(identical(other.top, top) || other.top == top)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode => Object.hash(runtimeType,maximized,fullScreen,left,top,width,height);

@override
String toString() {
  return 'WindowState(maximized: $maximized, fullScreen: $fullScreen, left: $left, top: $top, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class _$WindowStateCopyWith<$Res> implements $WindowStateCopyWith<$Res> {
  factory _$WindowStateCopyWith(_WindowState value, $Res Function(_WindowState) _then) = __$WindowStateCopyWithImpl;
@override @useResult
$Res call({
 bool maximized, bool fullScreen, double? left, double? top, double? width, double? height
});




}
/// @nodoc
class __$WindowStateCopyWithImpl<$Res>
    implements _$WindowStateCopyWith<$Res> {
  __$WindowStateCopyWithImpl(this._self, this._then);

  final _WindowState _self;
  final $Res Function(_WindowState) _then;

/// Create a copy of WindowState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? maximized = null,Object? fullScreen = null,Object? left = freezed,Object? top = freezed,Object? width = freezed,Object? height = freezed,}) {
  return _then(_WindowState(
maximized: null == maximized ? _self.maximized : maximized // ignore: cast_nullable_to_non_nullable
as bool,fullScreen: null == fullScreen ? _self.fullScreen : fullScreen // ignore: cast_nullable_to_non_nullable
as bool,left: freezed == left ? _self.left : left // ignore: cast_nullable_to_non_nullable
as double?,top: freezed == top ? _self.top : top // ignore: cast_nullable_to_non_nullable
as double?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
