// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error_call.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ErrorCall {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorCall);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ErrorCall()';
}


}





/// @nodoc


class ErrorCallKnown extends ErrorCall {
  const ErrorCallKnown(this.call): super._();
  

 final  KnownCall call;




@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorCallKnown&&(identical(other.call, call) || other.call == call));
}


@override
int get hashCode {
    return Object.hash(runtimeType,call);
}

@override
String toString() {
    return 'ErrorCall.known(call: $call)';
}


}




/// @nodoc


class ErrorCallNamed extends ErrorCall {
  const ErrorCallNamed(this.name): super._();
  

 final  String name;




@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorCallNamed&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'ErrorCall.named(name: $name)';
}


}




// dart format on
