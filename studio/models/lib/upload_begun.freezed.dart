// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'upload_begun.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UploadBegun {

 String get upload; int get partSize;
/// Create a copy of UploadBegun
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UploadBegunCopyWith<UploadBegun> get copyWith => _$UploadBegunCopyWithImpl<UploadBegun>(this as UploadBegun, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UploadBegun;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UploadBegun&&(identical(other.upload, _this.upload) || other.upload == _this.upload)&&(identical(other.partSize, _this.partSize) || other.partSize == _this.partSize));
}


@override
int get hashCode {
  final _this = this as UploadBegun;
  return Object.hash(runtimeType,_this.upload,_this.partSize);
}

@override
String toString() {
  final _this = this as UploadBegun;
  return 'UploadBegun(upload: ${_this.upload}, partSize: ${_this.partSize})';
}


}

/// @nodoc
abstract mixin class $UploadBegunCopyWith<$Res>  {
  factory $UploadBegunCopyWith(UploadBegun value, $Res Function(UploadBegun) _then) = _$UploadBegunCopyWithImpl;
@useResult
$Res call({
 String upload, int partSize
});




}
/// @nodoc
class _$UploadBegunCopyWithImpl<$Res>
    implements $UploadBegunCopyWith<$Res> {
  _$UploadBegunCopyWithImpl(this._self, this._then);

  final UploadBegun _self;
  final $Res Function(UploadBegun) _then;

/// Create a copy of UploadBegun
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? upload = null,Object? partSize = null,}) {
  return _then(UploadBegun(
upload: null == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as String,partSize: null == partSize ? _self.partSize : partSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _UploadBegun implements UploadBegun {
  const _UploadBegun({required this.upload, required this.partSize});
  

@override final  String upload;
@override final  int partSize;

/// Create a copy of UploadBegun
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UploadBegunCopyWith<_UploadBegun> get copyWith => __$UploadBegunCopyWithImpl<_UploadBegun>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UploadBegun&&(identical(other.upload, upload) || other.upload == upload)&&(identical(other.partSize, partSize) || other.partSize == partSize));
}


@override
int get hashCode {
    return Object.hash(runtimeType,upload,partSize);
}

@override
String toString() {
    return 'UploadBegun(upload: $upload, partSize: $partSize)';
}


}

/// @nodoc
abstract mixin class _$UploadBegunCopyWith<$Res> implements $UploadBegunCopyWith<$Res> {
  factory _$UploadBegunCopyWith(_UploadBegun value, $Res Function(_UploadBegun) _then) = __$UploadBegunCopyWithImpl;
@override @useResult
$Res call({
 String upload, int partSize
});




}
/// @nodoc
class __$UploadBegunCopyWithImpl<$Res>
    implements _$UploadBegunCopyWith<$Res> {
  __$UploadBegunCopyWithImpl(this._self, this._then);

  final _UploadBegun _self;
  final $Res Function(_UploadBegun) _then;

/// Create a copy of UploadBegun
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? upload = null,Object? partSize = null,}) {
  return _then(_UploadBegun(
upload: null == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as String,partSize: null == partSize ? _self.partSize : partSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
