// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'blocklist_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BlocklistState {

 Set<String> get disabledDefaultDomains; bool get isLoadingOverrides; String? get overridesError; List<AuraRuleItem> get customRules; bool get isLoadingRules; String? get rulesError; String? get actionError;
/// Create a copy of BlocklistState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlocklistStateCopyWith<BlocklistState> get copyWith => _$BlocklistStateCopyWithImpl<BlocklistState>(this as BlocklistState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BlocklistState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlocklistState&&const DeepCollectionEquality().equals(other.disabledDefaultDomains, _this.disabledDefaultDomains)&&(identical(other.isLoadingOverrides, _this.isLoadingOverrides) || other.isLoadingOverrides == _this.isLoadingOverrides)&&(identical(other.overridesError, _this.overridesError) || other.overridesError == _this.overridesError)&&const DeepCollectionEquality().equals(other.customRules, _this.customRules)&&(identical(other.isLoadingRules, _this.isLoadingRules) || other.isLoadingRules == _this.isLoadingRules)&&(identical(other.rulesError, _this.rulesError) || other.rulesError == _this.rulesError)&&(identical(other.actionError, _this.actionError) || other.actionError == _this.actionError));
}


@override
int get hashCode {
  final _this = this as BlocklistState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.disabledDefaultDomains),_this.isLoadingOverrides,_this.overridesError,const DeepCollectionEquality().hash(_this.customRules),_this.isLoadingRules,_this.rulesError,_this.actionError);
}

@override
String toString() {
  final _this = this as BlocklistState;
  return 'BlocklistState(disabledDefaultDomains: ${_this.disabledDefaultDomains}, isLoadingOverrides: ${_this.isLoadingOverrides}, overridesError: ${_this.overridesError}, customRules: ${_this.customRules}, isLoadingRules: ${_this.isLoadingRules}, rulesError: ${_this.rulesError}, actionError: ${_this.actionError})';
}


}

/// @nodoc
abstract mixin class $BlocklistStateCopyWith<$Res>  {
  factory $BlocklistStateCopyWith(BlocklistState value, $Res Function(BlocklistState) _then) = _$BlocklistStateCopyWithImpl;
@useResult
$Res call({
 Set<String> disabledDefaultDomains, bool isLoadingOverrides, String? overridesError, List<AuraRuleItem> customRules, bool isLoadingRules, String? rulesError, String? actionError
});




}
/// @nodoc
class _$BlocklistStateCopyWithImpl<$Res>
    implements $BlocklistStateCopyWith<$Res> {
  _$BlocklistStateCopyWithImpl(this._self, this._then);

  final BlocklistState _self;
  final $Res Function(BlocklistState) _then;

/// Create a copy of BlocklistState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? disabledDefaultDomains = null,Object? isLoadingOverrides = null,Object? overridesError = freezed,Object? customRules = null,Object? isLoadingRules = null,Object? rulesError = freezed,Object? actionError = freezed,}) {
  return _then(BlocklistState(
disabledDefaultDomains: null == disabledDefaultDomains ? _self.disabledDefaultDomains : disabledDefaultDomains // ignore: cast_nullable_to_non_nullable
as Set<String>,isLoadingOverrides: null == isLoadingOverrides ? _self.isLoadingOverrides : isLoadingOverrides // ignore: cast_nullable_to_non_nullable
as bool,overridesError: freezed == overridesError ? _self.overridesError : overridesError // ignore: cast_nullable_to_non_nullable
as String?,customRules: null == customRules ? _self.customRules : customRules // ignore: cast_nullable_to_non_nullable
as List<AuraRuleItem>,isLoadingRules: null == isLoadingRules ? _self.isLoadingRules : isLoadingRules // ignore: cast_nullable_to_non_nullable
as bool,rulesError: freezed == rulesError ? _self.rulesError : rulesError // ignore: cast_nullable_to_non_nullable
as String?,actionError: freezed == actionError ? _self.actionError : actionError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BlocklistState].
extension BlocklistStatePatterns on BlocklistState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlocklistState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlocklistState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlocklistState value)  $default,){
final _that = this;
switch (_that) {
case _BlocklistState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlocklistState value)?  $default,){
final _that = this;
switch (_that) {
case _BlocklistState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Set<String> disabledDefaultDomains,  bool isLoadingOverrides,  String? overridesError,  List<AuraRuleItem> customRules,  bool isLoadingRules,  String? rulesError,  String? actionError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlocklistState() when $default != null:
return $default(_that.disabledDefaultDomains,_that.isLoadingOverrides,_that.overridesError,_that.customRules,_that.isLoadingRules,_that.rulesError,_that.actionError);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Set<String> disabledDefaultDomains,  bool isLoadingOverrides,  String? overridesError,  List<AuraRuleItem> customRules,  bool isLoadingRules,  String? rulesError,  String? actionError)  $default,) {final _that = this;
switch (_that) {
case _BlocklistState():
return $default(_that.disabledDefaultDomains,_that.isLoadingOverrides,_that.overridesError,_that.customRules,_that.isLoadingRules,_that.rulesError,_that.actionError);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Set<String> disabledDefaultDomains,  bool isLoadingOverrides,  String? overridesError,  List<AuraRuleItem> customRules,  bool isLoadingRules,  String? rulesError,  String? actionError)?  $default,) {final _that = this;
switch (_that) {
case _BlocklistState() when $default != null:
return $default(_that.disabledDefaultDomains,_that.isLoadingOverrides,_that.overridesError,_that.customRules,_that.isLoadingRules,_that.rulesError,_that.actionError);case _:
  return null;

}
}

}

/// @nodoc


class _BlocklistState implements BlocklistState {
  const _BlocklistState({ Set<String> disabledDefaultDomains = const {}, this.isLoadingOverrides = true, this.overridesError,  List<AuraRuleItem> customRules = const [], this.isLoadingRules = true, this.rulesError, this.actionError}): _disabledDefaultDomains = disabledDefaultDomains,_customRules = customRules;
  

 final  Set<String> _disabledDefaultDomains;
@override@JsonKey() Set<String> get disabledDefaultDomains {
  if (_disabledDefaultDomains is EqualUnmodifiableSetView) return _disabledDefaultDomains;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_disabledDefaultDomains);
}

@override@JsonKey() final  bool isLoadingOverrides;
@override final  String? overridesError;
 final  List<AuraRuleItem> _customRules;
@override@JsonKey() List<AuraRuleItem> get customRules {
  if (_customRules is EqualUnmodifiableListView) return _customRules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_customRules);
}

@override@JsonKey() final  bool isLoadingRules;
@override final  String? rulesError;
@override final  String? actionError;

/// Create a copy of BlocklistState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlocklistStateCopyWith<_BlocklistState> get copyWith => __$BlocklistStateCopyWithImpl<_BlocklistState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlocklistState&&const DeepCollectionEquality().equals(other.disabledDefaultDomains, _disabledDefaultDomains)&&(identical(other.isLoadingOverrides, isLoadingOverrides) || other.isLoadingOverrides == isLoadingOverrides)&&(identical(other.overridesError, overridesError) || other.overridesError == overridesError)&&const DeepCollectionEquality().equals(other.customRules, _customRules)&&(identical(other.isLoadingRules, isLoadingRules) || other.isLoadingRules == isLoadingRules)&&(identical(other.rulesError, rulesError) || other.rulesError == rulesError)&&(identical(other.actionError, actionError) || other.actionError == actionError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_disabledDefaultDomains),isLoadingOverrides,overridesError,const DeepCollectionEquality().hash(_customRules),isLoadingRules,rulesError,actionError);
}

@override
String toString() {
    return 'BlocklistState(disabledDefaultDomains: $disabledDefaultDomains, isLoadingOverrides: $isLoadingOverrides, overridesError: $overridesError, customRules: $customRules, isLoadingRules: $isLoadingRules, rulesError: $rulesError, actionError: $actionError)';
}


}

/// @nodoc
abstract mixin class _$BlocklistStateCopyWith<$Res> implements $BlocklistStateCopyWith<$Res> {
  factory _$BlocklistStateCopyWith(_BlocklistState value, $Res Function(_BlocklistState) _then) = __$BlocklistStateCopyWithImpl;
@override @useResult
$Res call({
 Set<String> disabledDefaultDomains, bool isLoadingOverrides, String? overridesError, List<AuraRuleItem> customRules, bool isLoadingRules, String? rulesError, String? actionError
});




}
/// @nodoc
class __$BlocklistStateCopyWithImpl<$Res>
    implements _$BlocklistStateCopyWith<$Res> {
  __$BlocklistStateCopyWithImpl(this._self, this._then);

  final _BlocklistState _self;
  final $Res Function(_BlocklistState) _then;

/// Create a copy of BlocklistState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? disabledDefaultDomains = null,Object? isLoadingOverrides = null,Object? overridesError = freezed,Object? customRules = null,Object? isLoadingRules = null,Object? rulesError = freezed,Object? actionError = freezed,}) {
  return _then(_BlocklistState(
disabledDefaultDomains: null == disabledDefaultDomains ? _self._disabledDefaultDomains : disabledDefaultDomains // ignore: cast_nullable_to_non_nullable
as Set<String>,isLoadingOverrides: null == isLoadingOverrides ? _self.isLoadingOverrides : isLoadingOverrides // ignore: cast_nullable_to_non_nullable
as bool,overridesError: freezed == overridesError ? _self.overridesError : overridesError // ignore: cast_nullable_to_non_nullable
as String?,customRules: null == customRules ? _self._customRules : customRules // ignore: cast_nullable_to_non_nullable
as List<AuraRuleItem>,isLoadingRules: null == isLoadingRules ? _self.isLoadingRules : isLoadingRules // ignore: cast_nullable_to_non_nullable
as bool,rulesError: freezed == rulesError ? _self.rulesError : rulesError // ignore: cast_nullable_to_non_nullable
as String?,actionError: freezed == actionError ? _self.actionError : actionError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
