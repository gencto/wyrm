// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error_hint.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ErrorHint {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHint);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint()';
}


}

/// @nodoc
class $ErrorHintCopyWith<$Res>  {
$ErrorHintCopyWith(ErrorHint _, $Res Function(ErrorHint) __);
}



/// @nodoc


class ErrorHintRunDenied implements ErrorHint {
  const ErrorHintRunDenied();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRunDenied);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.runDenied()';
}


}




/// @nodoc


class ErrorHintRunNotRunning implements ErrorHint {
  const ErrorHintRunNotRunning();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRunNotRunning);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.runNotRunning()';
}


}




/// @nodoc


class ErrorHintRunNoTrigger implements ErrorHint {
  const ErrorHintRunNoTrigger();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRunNoTrigger);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.runNoTrigger()';
}


}




/// @nodoc


class ErrorHintRunNotByHand implements ErrorHint {
  const ErrorHintRunNotByHand();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRunNotByHand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.runNotByHand()';
}


}




/// @nodoc


class ErrorHintNotSettable implements ErrorHint {
  const ErrorHintNotSettable();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintNotSettable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.notSettable()';
}


}




/// @nodoc


class ErrorHintNotConnected implements ErrorHint {
  const ErrorHintNotConnected();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintNotConnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.notConnected()';
}


}




/// @nodoc


class ErrorHintNoAssistant implements ErrorHint {
  const ErrorHintNoAssistant();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintNoAssistant);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.noAssistant()';
}


}




/// @nodoc


class ErrorHintAssistantNoTask implements ErrorHint {
  const ErrorHintAssistantNoTask();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintAssistantNoTask);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.assistantNoTask()';
}


}




/// @nodoc


class ErrorHintAgentParamsUnread implements ErrorHint {
  const ErrorHintAgentParamsUnread();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintAgentParamsUnread);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.agentParamsUnread()';
}


}




/// @nodoc


class ErrorHintTaskRecordInvalid implements ErrorHint {
  const ErrorHintTaskRecordInvalid({required this.task, required this.field, required this.reason});
  

 final  String task;
 final  String field;
 final  String reason;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintTaskRecordInvalidCopyWith<ErrorHintTaskRecordInvalid> get copyWith => _$ErrorHintTaskRecordInvalidCopyWithImpl<ErrorHintTaskRecordInvalid>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintTaskRecordInvalid&&(identical(other.task, task) || other.task == task)&&(identical(other.field, field) || other.field == field)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,task,field,reason);
}

@override
String toString() {
    return 'ErrorHint.taskRecordInvalid(task: $task, field: $field, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ErrorHintTaskRecordInvalidCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintTaskRecordInvalidCopyWith(ErrorHintTaskRecordInvalid value, $Res Function(ErrorHintTaskRecordInvalid) _then) = _$ErrorHintTaskRecordInvalidCopyWithImpl;
@useResult
$Res call({
 String task, String field, String reason
});




}
/// @nodoc
class _$ErrorHintTaskRecordInvalidCopyWithImpl<$Res>
    implements $ErrorHintTaskRecordInvalidCopyWith<$Res> {
  _$ErrorHintTaskRecordInvalidCopyWithImpl(this._self, this._then);

  final ErrorHintTaskRecordInvalid _self;
  final $Res Function(ErrorHintTaskRecordInvalid) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? task = null,Object? field = null,Object? reason = null,}) {
  return _then(ErrorHintTaskRecordInvalid(
task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ErrorHintLibraryBlockInvalid implements ErrorHint {
  const ErrorHintLibraryBlockInvalid({required this.name, required this.field, required this.reason});
  

 final  String name;
 final  String field;
 final  String reason;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintLibraryBlockInvalidCopyWith<ErrorHintLibraryBlockInvalid> get copyWith => _$ErrorHintLibraryBlockInvalidCopyWithImpl<ErrorHintLibraryBlockInvalid>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintLibraryBlockInvalid&&(identical(other.name, name) || other.name == name)&&(identical(other.field, field) || other.field == field)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,field,reason);
}

@override
String toString() {
    return 'ErrorHint.libraryBlockInvalid(name: $name, field: $field, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ErrorHintLibraryBlockInvalidCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintLibraryBlockInvalidCopyWith(ErrorHintLibraryBlockInvalid value, $Res Function(ErrorHintLibraryBlockInvalid) _then) = _$ErrorHintLibraryBlockInvalidCopyWithImpl;
@useResult
$Res call({
 String name, String field, String reason
});




}
/// @nodoc
class _$ErrorHintLibraryBlockInvalidCopyWithImpl<$Res>
    implements $ErrorHintLibraryBlockInvalidCopyWith<$Res> {
  _$ErrorHintLibraryBlockInvalidCopyWithImpl(this._self, this._then);

  final ErrorHintLibraryBlockInvalid _self;
  final $Res Function(ErrorHintLibraryBlockInvalid) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? field = null,Object? reason = null,}) {
  return _then(ErrorHintLibraryBlockInvalid(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ErrorHintFlowDefInvalid implements ErrorHint {
  const ErrorHintFlowDefInvalid({required this.flow, required this.why});
  

 final  String flow;
 final  String why;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintFlowDefInvalidCopyWith<ErrorHintFlowDefInvalid> get copyWith => _$ErrorHintFlowDefInvalidCopyWithImpl<ErrorHintFlowDefInvalid>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintFlowDefInvalid&&(identical(other.flow, flow) || other.flow == flow)&&(identical(other.why, why) || other.why == why));
}


@override
int get hashCode {
    return Object.hash(runtimeType,flow,why);
}

@override
String toString() {
    return 'ErrorHint.flowDefInvalid(flow: $flow, why: $why)';
}


}

/// @nodoc
abstract mixin class $ErrorHintFlowDefInvalidCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintFlowDefInvalidCopyWith(ErrorHintFlowDefInvalid value, $Res Function(ErrorHintFlowDefInvalid) _then) = _$ErrorHintFlowDefInvalidCopyWithImpl;
@useResult
$Res call({
 String flow, String why
});




}
/// @nodoc
class _$ErrorHintFlowDefInvalidCopyWithImpl<$Res>
    implements $ErrorHintFlowDefInvalidCopyWith<$Res> {
  _$ErrorHintFlowDefInvalidCopyWithImpl(this._self, this._then);

  final ErrorHintFlowDefInvalid _self;
  final $Res Function(ErrorHintFlowDefInvalid) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? flow = null,Object? why = null,}) {
  return _then(ErrorHintFlowDefInvalid(
flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as String,why: null == why ? _self.why : why // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ErrorHintNoEditAction implements ErrorHint {
  const ErrorHintNoEditAction();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintNoEditAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.noEditAction()';
}


}




/// @nodoc


class ErrorHintProfileNotJson implements ErrorHint {
  const ErrorHintProfileNotJson(this.detail);
  

 final  String detail;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintProfileNotJsonCopyWith<ErrorHintProfileNotJson> get copyWith => _$ErrorHintProfileNotJsonCopyWithImpl<ErrorHintProfileNotJson>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintProfileNotJson&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,detail);
}

@override
String toString() {
    return 'ErrorHint.profileNotJson(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $ErrorHintProfileNotJsonCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintProfileNotJsonCopyWith(ErrorHintProfileNotJson value, $Res Function(ErrorHintProfileNotJson) _then) = _$ErrorHintProfileNotJsonCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$ErrorHintProfileNotJsonCopyWithImpl<$Res>
    implements $ErrorHintProfileNotJsonCopyWith<$Res> {
  _$ErrorHintProfileNotJsonCopyWithImpl(this._self, this._then);

  final ErrorHintProfileNotJson _self;
  final $Res Function(ErrorHintProfileNotJson) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(ErrorHintProfileNotJson(
null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ErrorHintProfileNotObject implements ErrorHint {
  const ErrorHintProfileNotObject();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintProfileNotObject);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.profileNotObject()';
}


}




/// @nodoc


class ErrorHintProfileUnknownKey implements ErrorHint {
  const ErrorHintProfileUnknownKey({required this.key, required this.known});
  

 final  String key;
 final  IList<String> known;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintProfileUnknownKeyCopyWith<ErrorHintProfileUnknownKey> get copyWith => _$ErrorHintProfileUnknownKeyCopyWithImpl<ErrorHintProfileUnknownKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintProfileUnknownKey&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other.known, known));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,const DeepCollectionEquality().hash(known));
}

@override
String toString() {
    return 'ErrorHint.profileUnknownKey(key: $key, known: $known)';
}


}

/// @nodoc
abstract mixin class $ErrorHintProfileUnknownKeyCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintProfileUnknownKeyCopyWith(ErrorHintProfileUnknownKey value, $Res Function(ErrorHintProfileUnknownKey) _then) = _$ErrorHintProfileUnknownKeyCopyWithImpl;
@useResult
$Res call({
 String key, IList<String> known
});




}
/// @nodoc
class _$ErrorHintProfileUnknownKeyCopyWithImpl<$Res>
    implements $ErrorHintProfileUnknownKeyCopyWith<$Res> {
  _$ErrorHintProfileUnknownKeyCopyWithImpl(this._self, this._then);

  final ErrorHintProfileUnknownKey _self;
  final $Res Function(ErrorHintProfileUnknownKey) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? key = null,Object? known = null,}) {
  return _then(ErrorHintProfileUnknownKey(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,known: null == known ? _self.known : known // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

/// @nodoc


class ErrorHintProfileUnknownType implements ErrorHint {
  const ErrorHintProfileUnknownType(this.type);
  

 final  String type;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintProfileUnknownTypeCopyWith<ErrorHintProfileUnknownType> get copyWith => _$ErrorHintProfileUnknownTypeCopyWithImpl<ErrorHintProfileUnknownType>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintProfileUnknownType&&(identical(other.type, type) || other.type == type));
}


@override
int get hashCode {
    return Object.hash(runtimeType,type);
}

@override
String toString() {
    return 'ErrorHint.profileUnknownType(type: $type)';
}


}

/// @nodoc
abstract mixin class $ErrorHintProfileUnknownTypeCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintProfileUnknownTypeCopyWith(ErrorHintProfileUnknownType value, $Res Function(ErrorHintProfileUnknownType) _then) = _$ErrorHintProfileUnknownTypeCopyWithImpl;
@useResult
$Res call({
 String type
});




}
/// @nodoc
class _$ErrorHintProfileUnknownTypeCopyWithImpl<$Res>
    implements $ErrorHintProfileUnknownTypeCopyWith<$Res> {
  _$ErrorHintProfileUnknownTypeCopyWithImpl(this._self, this._then);

  final ErrorHintProfileUnknownType _self;
  final $Res Function(ErrorHintProfileUnknownType) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? type = null,}) {
  return _then(ErrorHintProfileUnknownType(
null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ErrorHintProfileTooBig implements ErrorHint {
  const ErrorHintProfileTooBig();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintProfileTooBig);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.profileTooBig()';
}


}




/// @nodoc


class ErrorHintRangeBadText implements ErrorHint {
  const ErrorHintRangeBadText();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRangeBadText);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.rangeBadText()';
}


}




/// @nodoc


class ErrorHintRangeBadPart implements ErrorHint {
  const ErrorHintRangeBadPart();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRangeBadPart);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.rangeBadPart()';
}


}




/// @nodoc


class ErrorHintRangeBadPrefix implements ErrorHint {
  const ErrorHintRangeBadPrefix();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRangeBadPrefix);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.rangeBadPrefix()';
}


}




/// @nodoc


class ErrorHintRangeTooBig implements ErrorHint {
  const ErrorHintRangeTooBig();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintRangeTooBig);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.rangeTooBig()';
}


}




/// @nodoc


class ErrorHintPortOutOfRange implements ErrorHint {
  const ErrorHintPortOutOfRange();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintPortOutOfRange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.portOutOfRange()';
}


}




/// @nodoc


class ErrorHintNoDeviceKey implements ErrorHint {
  const ErrorHintNoDeviceKey(this.host);
  

 final  HostPlatform host;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintNoDeviceKeyCopyWith<ErrorHintNoDeviceKey> get copyWith => _$ErrorHintNoDeviceKeyCopyWithImpl<ErrorHintNoDeviceKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintNoDeviceKey&&(identical(other.host, host) || other.host == host));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host);
}

@override
String toString() {
    return 'ErrorHint.noDeviceKey(host: $host)';
}


}

/// @nodoc
abstract mixin class $ErrorHintNoDeviceKeyCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintNoDeviceKeyCopyWith(ErrorHintNoDeviceKey value, $Res Function(ErrorHintNoDeviceKey) _then) = _$ErrorHintNoDeviceKeyCopyWithImpl;
@useResult
$Res call({
 HostPlatform host
});




}
/// @nodoc
class _$ErrorHintNoDeviceKeyCopyWithImpl<$Res>
    implements $ErrorHintNoDeviceKeyCopyWith<$Res> {
  _$ErrorHintNoDeviceKeyCopyWithImpl(this._self, this._then);

  final ErrorHintNoDeviceKey _self;
  final $Res Function(ErrorHintNoDeviceKey) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,}) {
  return _then(ErrorHintNoDeviceKey(
null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as HostPlatform,
  ));
}


}

/// @nodoc


class ErrorHintBackupNoDigest implements ErrorHint {
  const ErrorHintBackupNoDigest();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintBackupNoDigest);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.backupNoDigest()';
}


}




/// @nodoc


class ErrorHintBackupDigestMismatch implements ErrorHint {
  const ErrorHintBackupDigestMismatch({required this.got, required this.expected});
  

 final  String got;
 final  String expected;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintBackupDigestMismatchCopyWith<ErrorHintBackupDigestMismatch> get copyWith => _$ErrorHintBackupDigestMismatchCopyWithImpl<ErrorHintBackupDigestMismatch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintBackupDigestMismatch&&(identical(other.got, got) || other.got == got)&&(identical(other.expected, expected) || other.expected == expected));
}


@override
int get hashCode {
    return Object.hash(runtimeType,got,expected);
}

@override
String toString() {
    return 'ErrorHint.backupDigestMismatch(got: $got, expected: $expected)';
}


}

/// @nodoc
abstract mixin class $ErrorHintBackupDigestMismatchCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintBackupDigestMismatchCopyWith(ErrorHintBackupDigestMismatch value, $Res Function(ErrorHintBackupDigestMismatch) _then) = _$ErrorHintBackupDigestMismatchCopyWithImpl;
@useResult
$Res call({
 String got, String expected
});




}
/// @nodoc
class _$ErrorHintBackupDigestMismatchCopyWithImpl<$Res>
    implements $ErrorHintBackupDigestMismatchCopyWith<$Res> {
  _$ErrorHintBackupDigestMismatchCopyWithImpl(this._self, this._then);

  final ErrorHintBackupDigestMismatch _self;
  final $Res Function(ErrorHintBackupDigestMismatch) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? got = null,Object? expected = null,}) {
  return _then(ErrorHintBackupDigestMismatch(
got: null == got ? _self.got : got // ignore: cast_nullable_to_non_nullable
as String,expected: null == expected ? _self.expected : expected // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ErrorHintFileEndedEarly implements ErrorHint {
  const ErrorHintFileEndedEarly({required this.offset, required this.size});
  

 final  int offset;
 final  int size;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ErrorHintFileEndedEarlyCopyWith<ErrorHintFileEndedEarly> get copyWith => _$ErrorHintFileEndedEarlyCopyWithImpl<ErrorHintFileEndedEarly>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintFileEndedEarly&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.size, size) || other.size == size));
}


@override
int get hashCode {
    return Object.hash(runtimeType,offset,size);
}

@override
String toString() {
    return 'ErrorHint.fileEndedEarly(offset: $offset, size: $size)';
}


}

/// @nodoc
abstract mixin class $ErrorHintFileEndedEarlyCopyWith<$Res> implements $ErrorHintCopyWith<$Res> {
  factory $ErrorHintFileEndedEarlyCopyWith(ErrorHintFileEndedEarly value, $Res Function(ErrorHintFileEndedEarly) _then) = _$ErrorHintFileEndedEarlyCopyWithImpl;
@useResult
$Res call({
 int offset, int size
});




}
/// @nodoc
class _$ErrorHintFileEndedEarlyCopyWithImpl<$Res>
    implements $ErrorHintFileEndedEarlyCopyWith<$Res> {
  _$ErrorHintFileEndedEarlyCopyWithImpl(this._self, this._then);

  final ErrorHintFileEndedEarly _self;
  final $Res Function(ErrorHintFileEndedEarly) _then;

/// Create a copy of ErrorHint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? offset = null,Object? size = null,}) {
  return _then(ErrorHintFileEndedEarly(
offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ErrorHintEmptyPart implements ErrorHint {
  const ErrorHintEmptyPart();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorHintEmptyPart);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorHint.emptyPart()';
}


}




// dart format on
