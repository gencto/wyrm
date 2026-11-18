// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file_part.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FilePart {

 Uint8List get data; int get size; bool get eof;
/// Create a copy of FilePart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FilePartCopyWith<FilePart> get copyWith => _$FilePartCopyWithImpl<FilePart>(this as FilePart, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FilePart;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FilePart&&const DeepCollectionEquality().equals(other.data, _this.data)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.eof, _this.eof) || other.eof == _this.eof));
}


@override
int get hashCode {
  final _this = this as FilePart;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.data),_this.size,_this.eof);
}

@override
String toString() {
  final _this = this as FilePart;
  return 'FilePart(data: ${_this.data}, size: ${_this.size}, eof: ${_this.eof})';
}


}

/// @nodoc
abstract mixin class $FilePartCopyWith<$Res>  {
  factory $FilePartCopyWith(FilePart value, $Res Function(FilePart) _then) = _$FilePartCopyWithImpl;
@useResult
$Res call({
 Uint8List data, int size, bool eof
});




}
/// @nodoc
class _$FilePartCopyWithImpl<$Res>
    implements $FilePartCopyWith<$Res> {
  _$FilePartCopyWithImpl(this._self, this._then);

  final FilePart _self;
  final $Res Function(FilePart) _then;

/// Create a copy of FilePart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? data = null,Object? size = null,Object? eof = null,}) {
  return _then(FilePart(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,eof: null == eof ? _self.eof : eof // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _FilePart implements FilePart {
  const _FilePart({required this.data, required this.size, required this.eof});
  

@override final  Uint8List data;
@override final  int size;
@override final  bool eof;

/// Create a copy of FilePart
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FilePartCopyWith<_FilePart> get copyWith => __$FilePartCopyWithImpl<_FilePart>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FilePart&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.size, size) || other.size == size)&&(identical(other.eof, eof) || other.eof == eof));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(data),size,eof);
}

@override
String toString() {
    return 'FilePart(data: $data, size: $size, eof: $eof)';
}


}

/// @nodoc
abstract mixin class _$FilePartCopyWith<$Res> implements $FilePartCopyWith<$Res> {
  factory _$FilePartCopyWith(_FilePart value, $Res Function(_FilePart) _then) = __$FilePartCopyWithImpl;
@override @useResult
$Res call({
 Uint8List data, int size, bool eof
});




}
/// @nodoc
class __$FilePartCopyWithImpl<$Res>
    implements _$FilePartCopyWith<$Res> {
  __$FilePartCopyWithImpl(this._self, this._then);

  final _FilePart _self;
  final $Res Function(_FilePart) _then;

/// Create a copy of FilePart
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = null,Object? size = null,Object? eof = null,}) {
  return _then(_FilePart(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,eof: null == eof ? _self.eof : eof // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
