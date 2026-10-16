// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'blocklist_sync_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BlocklistSyncState {

 SyncState get state; String? get message; double? get progress; InstalledReleaseMeta? get installedRelease; BlocklistManifest? get latestManifest; String? get errorMessage; bool get isCategoryEndpointsMissing;
/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlocklistSyncStateCopyWith<BlocklistSyncState> get copyWith => _$BlocklistSyncStateCopyWithImpl<BlocklistSyncState>(this as BlocklistSyncState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BlocklistSyncState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlocklistSyncState&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.installedRelease, _this.installedRelease) || other.installedRelease == _this.installedRelease)&&(identical(other.latestManifest, _this.latestManifest) || other.latestManifest == _this.latestManifest)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.isCategoryEndpointsMissing, _this.isCategoryEndpointsMissing) || other.isCategoryEndpointsMissing == _this.isCategoryEndpointsMissing));
}


@override
int get hashCode {
  final _this = this as BlocklistSyncState;
  return Object.hash(runtimeType,_this.state,_this.message,_this.progress,_this.installedRelease,_this.latestManifest,_this.errorMessage,_this.isCategoryEndpointsMissing);
}

@override
String toString() {
  final _this = this as BlocklistSyncState;
  return 'BlocklistSyncState(state: ${_this.state}, message: ${_this.message}, progress: ${_this.progress}, installedRelease: ${_this.installedRelease}, latestManifest: ${_this.latestManifest}, errorMessage: ${_this.errorMessage}, isCategoryEndpointsMissing: ${_this.isCategoryEndpointsMissing})';
}


}

/// @nodoc
abstract mixin class $BlocklistSyncStateCopyWith<$Res>  {
  factory $BlocklistSyncStateCopyWith(BlocklistSyncState value, $Res Function(BlocklistSyncState) _then) = _$BlocklistSyncStateCopyWithImpl;
@useResult
$Res call({
 SyncState state, String? message, double? progress, InstalledReleaseMeta? installedRelease, BlocklistManifest? latestManifest, String? errorMessage, bool isCategoryEndpointsMissing
});


$InstalledReleaseMetaCopyWith<$Res>? get installedRelease;$BlocklistManifestCopyWith<$Res>? get latestManifest;

}
/// @nodoc
class _$BlocklistSyncStateCopyWithImpl<$Res>
    implements $BlocklistSyncStateCopyWith<$Res> {
  _$BlocklistSyncStateCopyWithImpl(this._self, this._then);

  final BlocklistSyncState _self;
  final $Res Function(BlocklistSyncState) _then;

/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,Object? message = freezed,Object? progress = freezed,Object? installedRelease = freezed,Object? latestManifest = freezed,Object? errorMessage = freezed,Object? isCategoryEndpointsMissing = null,}) {
  return _then(BlocklistSyncState(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SyncState,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,installedRelease: freezed == installedRelease ? _self.installedRelease : installedRelease // ignore: cast_nullable_to_non_nullable
as InstalledReleaseMeta?,latestManifest: freezed == latestManifest ? _self.latestManifest : latestManifest // ignore: cast_nullable_to_non_nullable
as BlocklistManifest?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,isCategoryEndpointsMissing: null == isCategoryEndpointsMissing ? _self.isCategoryEndpointsMissing : isCategoryEndpointsMissing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstalledReleaseMetaCopyWith<$Res>? get installedRelease {
    if (_self.installedRelease == null) {
    return null;
  }

  return $InstalledReleaseMetaCopyWith<$Res>(_self.installedRelease!, (value) {
    return _then(_self.copyWith(installedRelease: value));
  });
}/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BlocklistManifestCopyWith<$Res>? get latestManifest {
    if (_self.latestManifest == null) {
    return null;
  }

  return $BlocklistManifestCopyWith<$Res>(_self.latestManifest!, (value) {
    return _then(_self.copyWith(latestManifest: value));
  });
}
}


/// Adds pattern-matching-related methods to [BlocklistSyncState].
extension BlocklistSyncStatePatterns on BlocklistSyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlocklistSyncState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlocklistSyncState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlocklistSyncState value)  $default,){
final _that = this;
switch (_that) {
case _BlocklistSyncState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlocklistSyncState value)?  $default,){
final _that = this;
switch (_that) {
case _BlocklistSyncState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SyncState state,  String? message,  double? progress,  InstalledReleaseMeta? installedRelease,  BlocklistManifest? latestManifest,  String? errorMessage,  bool isCategoryEndpointsMissing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlocklistSyncState() when $default != null:
return $default(_that.state,_that.message,_that.progress,_that.installedRelease,_that.latestManifest,_that.errorMessage,_that.isCategoryEndpointsMissing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SyncState state,  String? message,  double? progress,  InstalledReleaseMeta? installedRelease,  BlocklistManifest? latestManifest,  String? errorMessage,  bool isCategoryEndpointsMissing)  $default,) {final _that = this;
switch (_that) {
case _BlocklistSyncState():
return $default(_that.state,_that.message,_that.progress,_that.installedRelease,_that.latestManifest,_that.errorMessage,_that.isCategoryEndpointsMissing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SyncState state,  String? message,  double? progress,  InstalledReleaseMeta? installedRelease,  BlocklistManifest? latestManifest,  String? errorMessage,  bool isCategoryEndpointsMissing)?  $default,) {final _that = this;
switch (_that) {
case _BlocklistSyncState() when $default != null:
return $default(_that.state,_that.message,_that.progress,_that.installedRelease,_that.latestManifest,_that.errorMessage,_that.isCategoryEndpointsMissing);case _:
  return null;

}
}

}

/// @nodoc


class _BlocklistSyncState extends BlocklistSyncState {
  const _BlocklistSyncState({this.state = SyncState.idle, this.message, this.progress, this.installedRelease, this.latestManifest, this.errorMessage, this.isCategoryEndpointsMissing = false}): super._();
  

@override@JsonKey() final  SyncState state;
@override final  String? message;
@override final  double? progress;
@override final  InstalledReleaseMeta? installedRelease;
@override final  BlocklistManifest? latestManifest;
@override final  String? errorMessage;
@override@JsonKey() final  bool isCategoryEndpointsMissing;

/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlocklistSyncStateCopyWith<_BlocklistSyncState> get copyWith => __$BlocklistSyncStateCopyWithImpl<_BlocklistSyncState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlocklistSyncState&&(identical(other.state, state) || other.state == state)&&(identical(other.message, message) || other.message == message)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.installedRelease, installedRelease) || other.installedRelease == installedRelease)&&(identical(other.latestManifest, latestManifest) || other.latestManifest == latestManifest)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.isCategoryEndpointsMissing, isCategoryEndpointsMissing) || other.isCategoryEndpointsMissing == isCategoryEndpointsMissing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,message,progress,installedRelease,latestManifest,errorMessage,isCategoryEndpointsMissing);
}

@override
String toString() {
    return 'BlocklistSyncState(state: $state, message: $message, progress: $progress, installedRelease: $installedRelease, latestManifest: $latestManifest, errorMessage: $errorMessage, isCategoryEndpointsMissing: $isCategoryEndpointsMissing)';
}


}

/// @nodoc
abstract mixin class _$BlocklistSyncStateCopyWith<$Res> implements $BlocklistSyncStateCopyWith<$Res> {
  factory _$BlocklistSyncStateCopyWith(_BlocklistSyncState value, $Res Function(_BlocklistSyncState) _then) = __$BlocklistSyncStateCopyWithImpl;
@override @useResult
$Res call({
 SyncState state, String? message, double? progress, InstalledReleaseMeta? installedRelease, BlocklistManifest? latestManifest, String? errorMessage, bool isCategoryEndpointsMissing
});


@override $InstalledReleaseMetaCopyWith<$Res>? get installedRelease;@override $BlocklistManifestCopyWith<$Res>? get latestManifest;

}
/// @nodoc
class __$BlocklistSyncStateCopyWithImpl<$Res>
    implements _$BlocklistSyncStateCopyWith<$Res> {
  __$BlocklistSyncStateCopyWithImpl(this._self, this._then);

  final _BlocklistSyncState _self;
  final $Res Function(_BlocklistSyncState) _then;

/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? message = freezed,Object? progress = freezed,Object? installedRelease = freezed,Object? latestManifest = freezed,Object? errorMessage = freezed,Object? isCategoryEndpointsMissing = null,}) {
  return _then(_BlocklistSyncState(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SyncState,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,installedRelease: freezed == installedRelease ? _self.installedRelease : installedRelease // ignore: cast_nullable_to_non_nullable
as InstalledReleaseMeta?,latestManifest: freezed == latestManifest ? _self.latestManifest : latestManifest // ignore: cast_nullable_to_non_nullable
as BlocklistManifest?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,isCategoryEndpointsMissing: null == isCategoryEndpointsMissing ? _self.isCategoryEndpointsMissing : isCategoryEndpointsMissing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstalledReleaseMetaCopyWith<$Res>? get installedRelease {
    if (_self.installedRelease == null) {
    return null;
  }

  return $InstalledReleaseMetaCopyWith<$Res>(_self.installedRelease!, (value) {
    return _then(_self.copyWith(installedRelease: value));
  });
}/// Create a copy of BlocklistSyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BlocklistManifestCopyWith<$Res>? get latestManifest {
    if (_self.latestManifest == null) {
    return null;
  }

  return $BlocklistManifestCopyWith<$Res>(_self.latestManifest!, (value) {
    return _then(_self.copyWith(latestManifest: value));
  });
}
}

// dart format on
