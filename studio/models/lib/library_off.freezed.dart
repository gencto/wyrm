// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'library_off.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LibraryOff {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryOff);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryOff()';
}


}

/// @nodoc
class $LibraryOffCopyWith<$Res>  {
$LibraryOffCopyWith(LibraryOff _, $Res Function(LibraryOff) __);
}



/// @nodoc


class LibraryOffUnread implements LibraryOff {
  const LibraryOffUnread();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryOffUnread);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryOff.unread()';
}


}




/// @nodoc


class LibraryOffRefused implements LibraryOff {
  const LibraryOffRefused(this.status);
  

 final  StatusCode status;

/// Create a copy of LibraryOff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryOffRefusedCopyWith<LibraryOffRefused> get copyWith => _$LibraryOffRefusedCopyWithImpl<LibraryOffRefused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryOffRefused&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status);
}

@override
String toString() {
    return 'LibraryOff.refused(status: $status)';
}


}

/// @nodoc
abstract mixin class $LibraryOffRefusedCopyWith<$Res> implements $LibraryOffCopyWith<$Res> {
  factory $LibraryOffRefusedCopyWith(LibraryOffRefused value, $Res Function(LibraryOffRefused) _then) = _$LibraryOffRefusedCopyWithImpl;
@useResult
$Res call({
 StatusCode status
});




}
/// @nodoc
class _$LibraryOffRefusedCopyWithImpl<$Res>
    implements $LibraryOffRefusedCopyWith<$Res> {
  _$LibraryOffRefusedCopyWithImpl(this._self, this._then);

  final LibraryOffRefused _self;
  final $Res Function(LibraryOffRefused) _then;

/// Create a copy of LibraryOff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(LibraryOffRefused(
null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StatusCode,
  ));
}


}

// dart format on
