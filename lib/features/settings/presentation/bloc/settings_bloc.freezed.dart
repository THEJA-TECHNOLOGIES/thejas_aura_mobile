// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_bloc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SettingsEvent()';
}


}

/// @nodoc
class $SettingsEventCopyWith<$Res>  {
$SettingsEventCopyWith(SettingsEvent _, $Res Function(SettingsEvent) __);
}


/// Adds pattern-matching-related methods to [SettingsEvent].
extension SettingsEventPatterns on SettingsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Load value)?  load,TResult Function( ThemeChanged value)?  themeChanged,TResult Function( AutoRestartToggled value)?  autoRestartToggled,TResult Function( RetentionPeriodChanged value)?  retentionPeriodChanged,TResult Function( ClearActivityHistory value)?  clearActivityHistory,TResult Function( ErrorMessageDismissed value)?  errorMessageDismissed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Load() when load != null:
return load(_that);case ThemeChanged() when themeChanged != null:
return themeChanged(_that);case AutoRestartToggled() when autoRestartToggled != null:
return autoRestartToggled(_that);case RetentionPeriodChanged() when retentionPeriodChanged != null:
return retentionPeriodChanged(_that);case ClearActivityHistory() when clearActivityHistory != null:
return clearActivityHistory(_that);case ErrorMessageDismissed() when errorMessageDismissed != null:
return errorMessageDismissed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Load value)  load,required TResult Function( ThemeChanged value)  themeChanged,required TResult Function( AutoRestartToggled value)  autoRestartToggled,required TResult Function( RetentionPeriodChanged value)  retentionPeriodChanged,required TResult Function( ClearActivityHistory value)  clearActivityHistory,required TResult Function( ErrorMessageDismissed value)  errorMessageDismissed,}){
final _that = this;
switch (_that) {
case Load():
return load(_that);case ThemeChanged():
return themeChanged(_that);case AutoRestartToggled():
return autoRestartToggled(_that);case RetentionPeriodChanged():
return retentionPeriodChanged(_that);case ClearActivityHistory():
return clearActivityHistory(_that);case ErrorMessageDismissed():
return errorMessageDismissed(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Load value)?  load,TResult? Function( ThemeChanged value)?  themeChanged,TResult? Function( AutoRestartToggled value)?  autoRestartToggled,TResult? Function( RetentionPeriodChanged value)?  retentionPeriodChanged,TResult? Function( ClearActivityHistory value)?  clearActivityHistory,TResult? Function( ErrorMessageDismissed value)?  errorMessageDismissed,}){
final _that = this;
switch (_that) {
case Load() when load != null:
return load(_that);case ThemeChanged() when themeChanged != null:
return themeChanged(_that);case AutoRestartToggled() when autoRestartToggled != null:
return autoRestartToggled(_that);case RetentionPeriodChanged() when retentionPeriodChanged != null:
return retentionPeriodChanged(_that);case ClearActivityHistory() when clearActivityHistory != null:
return clearActivityHistory(_that);case ErrorMessageDismissed() when errorMessageDismissed != null:
return errorMessageDismissed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  load,TResult Function( ThemeMode themeMode)?  themeChanged,TResult Function( bool enabled)?  autoRestartToggled,TResult Function( int days)?  retentionPeriodChanged,TResult Function()?  clearActivityHistory,TResult Function()?  errorMessageDismissed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Load() when load != null:
return load();case ThemeChanged() when themeChanged != null:
return themeChanged(_that.themeMode);case AutoRestartToggled() when autoRestartToggled != null:
return autoRestartToggled(_that.enabled);case RetentionPeriodChanged() when retentionPeriodChanged != null:
return retentionPeriodChanged(_that.days);case ClearActivityHistory() when clearActivityHistory != null:
return clearActivityHistory();case ErrorMessageDismissed() when errorMessageDismissed != null:
return errorMessageDismissed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  load,required TResult Function( ThemeMode themeMode)  themeChanged,required TResult Function( bool enabled)  autoRestartToggled,required TResult Function( int days)  retentionPeriodChanged,required TResult Function()  clearActivityHistory,required TResult Function()  errorMessageDismissed,}) {final _that = this;
switch (_that) {
case Load():
return load();case ThemeChanged():
return themeChanged(_that.themeMode);case AutoRestartToggled():
return autoRestartToggled(_that.enabled);case RetentionPeriodChanged():
return retentionPeriodChanged(_that.days);case ClearActivityHistory():
return clearActivityHistory();case ErrorMessageDismissed():
return errorMessageDismissed();case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  load,TResult? Function( ThemeMode themeMode)?  themeChanged,TResult? Function( bool enabled)?  autoRestartToggled,TResult? Function( int days)?  retentionPeriodChanged,TResult? Function()?  clearActivityHistory,TResult? Function()?  errorMessageDismissed,}) {final _that = this;
switch (_that) {
case Load() when load != null:
return load();case ThemeChanged() when themeChanged != null:
return themeChanged(_that.themeMode);case AutoRestartToggled() when autoRestartToggled != null:
return autoRestartToggled(_that.enabled);case RetentionPeriodChanged() when retentionPeriodChanged != null:
return retentionPeriodChanged(_that.days);case ClearActivityHistory() when clearActivityHistory != null:
return clearActivityHistory();case ErrorMessageDismissed() when errorMessageDismissed != null:
return errorMessageDismissed();case _:
  return null;

}
}

}

/// @nodoc


class Load implements SettingsEvent {
  const Load();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Load);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SettingsEvent.load()';
}


}




/// @nodoc


class ThemeChanged implements SettingsEvent {
  const ThemeChanged(this.themeMode);
  

 final  ThemeMode themeMode;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThemeChangedCopyWith<ThemeChanged> get copyWith => _$ThemeChangedCopyWithImpl<ThemeChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThemeChanged&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,themeMode);
}

@override
String toString() {
    return 'SettingsEvent.themeChanged(themeMode: $themeMode)';
}


}

/// @nodoc
abstract mixin class $ThemeChangedCopyWith<$Res> implements $SettingsEventCopyWith<$Res> {
  factory $ThemeChangedCopyWith(ThemeChanged value, $Res Function(ThemeChanged) _then) = _$ThemeChangedCopyWithImpl;
@useResult
$Res call({
 ThemeMode themeMode
});




}
/// @nodoc
class _$ThemeChangedCopyWithImpl<$Res>
    implements $ThemeChangedCopyWith<$Res> {
  _$ThemeChangedCopyWithImpl(this._self, this._then);

  final ThemeChanged _self;
  final $Res Function(ThemeChanged) _then;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? themeMode = null,}) {
  return _then(ThemeChanged(
null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as ThemeMode,
  ));
}


}

/// @nodoc


class AutoRestartToggled implements SettingsEvent {
  const AutoRestartToggled(this.enabled);
  

 final  bool enabled;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AutoRestartToggledCopyWith<AutoRestartToggled> get copyWith => _$AutoRestartToggledCopyWithImpl<AutoRestartToggled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AutoRestartToggled&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled);
}

@override
String toString() {
    return 'SettingsEvent.autoRestartToggled(enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class $AutoRestartToggledCopyWith<$Res> implements $SettingsEventCopyWith<$Res> {
  factory $AutoRestartToggledCopyWith(AutoRestartToggled value, $Res Function(AutoRestartToggled) _then) = _$AutoRestartToggledCopyWithImpl;
@useResult
$Res call({
 bool enabled
});




}
/// @nodoc
class _$AutoRestartToggledCopyWithImpl<$Res>
    implements $AutoRestartToggledCopyWith<$Res> {
  _$AutoRestartToggledCopyWithImpl(this._self, this._then);

  final AutoRestartToggled _self;
  final $Res Function(AutoRestartToggled) _then;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? enabled = null,}) {
  return _then(AutoRestartToggled(
null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RetentionPeriodChanged implements SettingsEvent {
  const RetentionPeriodChanged(this.days);
  

 final  int days;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetentionPeriodChangedCopyWith<RetentionPeriodChanged> get copyWith => _$RetentionPeriodChangedCopyWithImpl<RetentionPeriodChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RetentionPeriodChanged&&(identical(other.days, days) || other.days == days));
}


@override
int get hashCode {
    return Object.hash(runtimeType,days);
}

@override
String toString() {
    return 'SettingsEvent.retentionPeriodChanged(days: $days)';
}


}

/// @nodoc
abstract mixin class $RetentionPeriodChangedCopyWith<$Res> implements $SettingsEventCopyWith<$Res> {
  factory $RetentionPeriodChangedCopyWith(RetentionPeriodChanged value, $Res Function(RetentionPeriodChanged) _then) = _$RetentionPeriodChangedCopyWithImpl;
@useResult
$Res call({
 int days
});




}
/// @nodoc
class _$RetentionPeriodChangedCopyWithImpl<$Res>
    implements $RetentionPeriodChangedCopyWith<$Res> {
  _$RetentionPeriodChangedCopyWithImpl(this._self, this._then);

  final RetentionPeriodChanged _self;
  final $Res Function(RetentionPeriodChanged) _then;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? days = null,}) {
  return _then(RetentionPeriodChanged(
null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ClearActivityHistory implements SettingsEvent {
  const ClearActivityHistory();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClearActivityHistory);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SettingsEvent.clearActivityHistory()';
}


}




/// @nodoc


class ErrorMessageDismissed implements SettingsEvent {
  const ErrorMessageDismissed();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ErrorMessageDismissed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SettingsEvent.errorMessageDismissed()';
}


}




/// @nodoc
mixin _$SettingsState {

 ThemeMode get themeMode; bool get autoRestartEnabled; int get retentionPeriodDays; bool get isLoading; bool get isPruning; String? get errorMessage;
/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsStateCopyWith<SettingsState> get copyWith => _$SettingsStateCopyWithImpl<SettingsState>(this as SettingsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsState&&(identical(other.themeMode, _this.themeMode) || other.themeMode == _this.themeMode)&&(identical(other.autoRestartEnabled, _this.autoRestartEnabled) || other.autoRestartEnabled == _this.autoRestartEnabled)&&(identical(other.retentionPeriodDays, _this.retentionPeriodDays) || other.retentionPeriodDays == _this.retentionPeriodDays)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.isPruning, _this.isPruning) || other.isPruning == _this.isPruning)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}


@override
int get hashCode {
  final _this = this as SettingsState;
  return Object.hash(runtimeType,_this.themeMode,_this.autoRestartEnabled,_this.retentionPeriodDays,_this.isLoading,_this.isPruning,_this.errorMessage);
}

@override
String toString() {
  final _this = this as SettingsState;
  return 'SettingsState(themeMode: ${_this.themeMode}, autoRestartEnabled: ${_this.autoRestartEnabled}, retentionPeriodDays: ${_this.retentionPeriodDays}, isLoading: ${_this.isLoading}, isPruning: ${_this.isPruning}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $SettingsStateCopyWith<$Res>  {
  factory $SettingsStateCopyWith(SettingsState value, $Res Function(SettingsState) _then) = _$SettingsStateCopyWithImpl;
@useResult
$Res call({
 ThemeMode themeMode, bool autoRestartEnabled, int retentionPeriodDays, bool isLoading, bool isPruning, String? errorMessage
});




}
/// @nodoc
class _$SettingsStateCopyWithImpl<$Res>
    implements $SettingsStateCopyWith<$Res> {
  _$SettingsStateCopyWithImpl(this._self, this._then);

  final SettingsState _self;
  final $Res Function(SettingsState) _then;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? themeMode = null,Object? autoRestartEnabled = null,Object? retentionPeriodDays = null,Object? isLoading = null,Object? isPruning = null,Object? errorMessage = freezed,}) {
  return _then(SettingsState(
themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as ThemeMode,autoRestartEnabled: null == autoRestartEnabled ? _self.autoRestartEnabled : autoRestartEnabled // ignore: cast_nullable_to_non_nullable
as bool,retentionPeriodDays: null == retentionPeriodDays ? _self.retentionPeriodDays : retentionPeriodDays // ignore: cast_nullable_to_non_nullable
as int,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isPruning: null == isPruning ? _self.isPruning : isPruning // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsState].
extension SettingsStatePatterns on SettingsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsState value)  $default,){
final _that = this;
switch (_that) {
case _SettingsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsState value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThemeMode themeMode,  bool autoRestartEnabled,  int retentionPeriodDays,  bool isLoading,  bool isPruning,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.themeMode,_that.autoRestartEnabled,_that.retentionPeriodDays,_that.isLoading,_that.isPruning,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThemeMode themeMode,  bool autoRestartEnabled,  int retentionPeriodDays,  bool isLoading,  bool isPruning,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _SettingsState():
return $default(_that.themeMode,_that.autoRestartEnabled,_that.retentionPeriodDays,_that.isLoading,_that.isPruning,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThemeMode themeMode,  bool autoRestartEnabled,  int retentionPeriodDays,  bool isLoading,  bool isPruning,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.themeMode,_that.autoRestartEnabled,_that.retentionPeriodDays,_that.isLoading,_that.isPruning,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsState implements SettingsState {
  const _SettingsState({this.themeMode = ThemeMode.system, this.autoRestartEnabled = true, this.retentionPeriodDays = 30, this.isLoading = false, this.isPruning = false, this.errorMessage});
  

@override@JsonKey() final  ThemeMode themeMode;
@override@JsonKey() final  bool autoRestartEnabled;
@override@JsonKey() final  int retentionPeriodDays;
@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isPruning;
@override final  String? errorMessage;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsStateCopyWith<_SettingsState> get copyWith => __$SettingsStateCopyWithImpl<_SettingsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsState&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.autoRestartEnabled, autoRestartEnabled) || other.autoRestartEnabled == autoRestartEnabled)&&(identical(other.retentionPeriodDays, retentionPeriodDays) || other.retentionPeriodDays == retentionPeriodDays)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isPruning, isPruning) || other.isPruning == isPruning)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,themeMode,autoRestartEnabled,retentionPeriodDays,isLoading,isPruning,errorMessage);
}

@override
String toString() {
    return 'SettingsState(themeMode: $themeMode, autoRestartEnabled: $autoRestartEnabled, retentionPeriodDays: $retentionPeriodDays, isLoading: $isLoading, isPruning: $isPruning, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$SettingsStateCopyWith<$Res> implements $SettingsStateCopyWith<$Res> {
  factory _$SettingsStateCopyWith(_SettingsState value, $Res Function(_SettingsState) _then) = __$SettingsStateCopyWithImpl;
@override @useResult
$Res call({
 ThemeMode themeMode, bool autoRestartEnabled, int retentionPeriodDays, bool isLoading, bool isPruning, String? errorMessage
});




}
/// @nodoc
class __$SettingsStateCopyWithImpl<$Res>
    implements _$SettingsStateCopyWith<$Res> {
  __$SettingsStateCopyWithImpl(this._self, this._then);

  final _SettingsState _self;
  final $Res Function(_SettingsState) _then;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? themeMode = null,Object? autoRestartEnabled = null,Object? retentionPeriodDays = null,Object? isLoading = null,Object? isPruning = null,Object? errorMessage = freezed,}) {
  return _then(_SettingsState(
themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as ThemeMode,autoRestartEnabled: null == autoRestartEnabled ? _self.autoRestartEnabled : autoRestartEnabled // ignore: cast_nullable_to_non_nullable
as bool,retentionPeriodDays: null == retentionPeriodDays ? _self.retentionPeriodDays : retentionPeriodDays // ignore: cast_nullable_to_non_nullable
as int,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isPruning: null == isPruning ? _self.isPruning : isPruning // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
