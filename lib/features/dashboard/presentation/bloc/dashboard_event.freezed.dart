// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dashboard_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DashboardEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DashboardEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent()';
}


}

/// @nodoc
class $DashboardEventCopyWith<$Res>  {
$DashboardEventCopyWith(DashboardEvent _, $Res Function(DashboardEvent) __);
}


/// Adds pattern-matching-related methods to [DashboardEvent].
extension DashboardEventPatterns on DashboardEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _DashboardStarted value)?  started,TResult Function( _DashboardTunnelStatusUpdated value)?  tunnelStatusUpdated,TResult Function( _DashboardTunnelToggled value)?  tunnelToggled,TResult Function( _DashboardPauseRequested value)?  pauseRequested,TResult Function( _DashboardShutdownRequested value)?  shutdownRequested,TResult Function( _DashboardStatsRefreshRequested value)?  statsRefreshRequested,TResult Function( _DashboardAppResumed value)?  appResumed,TResult Function( _DashboardErrorMessageDismissed value)?  errorMessageDismissed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DashboardStarted() when started != null:
return started(_that);case _DashboardTunnelStatusUpdated() when tunnelStatusUpdated != null:
return tunnelStatusUpdated(_that);case _DashboardTunnelToggled() when tunnelToggled != null:
return tunnelToggled(_that);case _DashboardPauseRequested() when pauseRequested != null:
return pauseRequested(_that);case _DashboardShutdownRequested() when shutdownRequested != null:
return shutdownRequested(_that);case _DashboardStatsRefreshRequested() when statsRefreshRequested != null:
return statsRefreshRequested(_that);case _DashboardAppResumed() when appResumed != null:
return appResumed(_that);case _DashboardErrorMessageDismissed() when errorMessageDismissed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _DashboardStarted value)  started,required TResult Function( _DashboardTunnelStatusUpdated value)  tunnelStatusUpdated,required TResult Function( _DashboardTunnelToggled value)  tunnelToggled,required TResult Function( _DashboardPauseRequested value)  pauseRequested,required TResult Function( _DashboardShutdownRequested value)  shutdownRequested,required TResult Function( _DashboardStatsRefreshRequested value)  statsRefreshRequested,required TResult Function( _DashboardAppResumed value)  appResumed,required TResult Function( _DashboardErrorMessageDismissed value)  errorMessageDismissed,}){
final _that = this;
switch (_that) {
case _DashboardStarted():
return started(_that);case _DashboardTunnelStatusUpdated():
return tunnelStatusUpdated(_that);case _DashboardTunnelToggled():
return tunnelToggled(_that);case _DashboardPauseRequested():
return pauseRequested(_that);case _DashboardShutdownRequested():
return shutdownRequested(_that);case _DashboardStatsRefreshRequested():
return statsRefreshRequested(_that);case _DashboardAppResumed():
return appResumed(_that);case _DashboardErrorMessageDismissed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _DashboardStarted value)?  started,TResult? Function( _DashboardTunnelStatusUpdated value)?  tunnelStatusUpdated,TResult? Function( _DashboardTunnelToggled value)?  tunnelToggled,TResult? Function( _DashboardPauseRequested value)?  pauseRequested,TResult? Function( _DashboardShutdownRequested value)?  shutdownRequested,TResult? Function( _DashboardStatsRefreshRequested value)?  statsRefreshRequested,TResult? Function( _DashboardAppResumed value)?  appResumed,TResult? Function( _DashboardErrorMessageDismissed value)?  errorMessageDismissed,}){
final _that = this;
switch (_that) {
case _DashboardStarted() when started != null:
return started(_that);case _DashboardTunnelStatusUpdated() when tunnelStatusUpdated != null:
return tunnelStatusUpdated(_that);case _DashboardTunnelToggled() when tunnelToggled != null:
return tunnelToggled(_that);case _DashboardPauseRequested() when pauseRequested != null:
return pauseRequested(_that);case _DashboardShutdownRequested() when shutdownRequested != null:
return shutdownRequested(_that);case _DashboardStatsRefreshRequested() when statsRefreshRequested != null:
return statsRefreshRequested(_that);case _DashboardAppResumed() when appResumed != null:
return appResumed(_that);case _DashboardErrorMessageDismissed() when errorMessageDismissed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  started,TResult Function( TunnelStatus status)?  tunnelStatusUpdated,TResult Function()?  tunnelToggled,TResult Function( Duration duration)?  pauseRequested,TResult Function()?  shutdownRequested,TResult Function()?  statsRefreshRequested,TResult Function()?  appResumed,TResult Function()?  errorMessageDismissed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DashboardStarted() when started != null:
return started();case _DashboardTunnelStatusUpdated() when tunnelStatusUpdated != null:
return tunnelStatusUpdated(_that.status);case _DashboardTunnelToggled() when tunnelToggled != null:
return tunnelToggled();case _DashboardPauseRequested() when pauseRequested != null:
return pauseRequested(_that.duration);case _DashboardShutdownRequested() when shutdownRequested != null:
return shutdownRequested();case _DashboardStatsRefreshRequested() when statsRefreshRequested != null:
return statsRefreshRequested();case _DashboardAppResumed() when appResumed != null:
return appResumed();case _DashboardErrorMessageDismissed() when errorMessageDismissed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  started,required TResult Function( TunnelStatus status)  tunnelStatusUpdated,required TResult Function()  tunnelToggled,required TResult Function( Duration duration)  pauseRequested,required TResult Function()  shutdownRequested,required TResult Function()  statsRefreshRequested,required TResult Function()  appResumed,required TResult Function()  errorMessageDismissed,}) {final _that = this;
switch (_that) {
case _DashboardStarted():
return started();case _DashboardTunnelStatusUpdated():
return tunnelStatusUpdated(_that.status);case _DashboardTunnelToggled():
return tunnelToggled();case _DashboardPauseRequested():
return pauseRequested(_that.duration);case _DashboardShutdownRequested():
return shutdownRequested();case _DashboardStatsRefreshRequested():
return statsRefreshRequested();case _DashboardAppResumed():
return appResumed();case _DashboardErrorMessageDismissed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  started,TResult? Function( TunnelStatus status)?  tunnelStatusUpdated,TResult? Function()?  tunnelToggled,TResult? Function( Duration duration)?  pauseRequested,TResult? Function()?  shutdownRequested,TResult? Function()?  statsRefreshRequested,TResult? Function()?  appResumed,TResult? Function()?  errorMessageDismissed,}) {final _that = this;
switch (_that) {
case _DashboardStarted() when started != null:
return started();case _DashboardTunnelStatusUpdated() when tunnelStatusUpdated != null:
return tunnelStatusUpdated(_that.status);case _DashboardTunnelToggled() when tunnelToggled != null:
return tunnelToggled();case _DashboardPauseRequested() when pauseRequested != null:
return pauseRequested(_that.duration);case _DashboardShutdownRequested() when shutdownRequested != null:
return shutdownRequested();case _DashboardStatsRefreshRequested() when statsRefreshRequested != null:
return statsRefreshRequested();case _DashboardAppResumed() when appResumed != null:
return appResumed();case _DashboardErrorMessageDismissed() when errorMessageDismissed != null:
return errorMessageDismissed();case _:
  return null;

}
}

}

/// @nodoc


class _DashboardStarted implements DashboardEvent {
  const _DashboardStarted();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent.started()';
}


}




/// @nodoc


class _DashboardTunnelStatusUpdated implements DashboardEvent {
  const _DashboardTunnelStatusUpdated(this.status);
  

 final  TunnelStatus status;

/// Create a copy of DashboardEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DashboardTunnelStatusUpdatedCopyWith<_DashboardTunnelStatusUpdated> get copyWith => __$DashboardTunnelStatusUpdatedCopyWithImpl<_DashboardTunnelStatusUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardTunnelStatusUpdated&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status);
}

@override
String toString() {
    return 'DashboardEvent.tunnelStatusUpdated(status: $status)';
}


}

/// @nodoc
abstract mixin class _$DashboardTunnelStatusUpdatedCopyWith<$Res> implements $DashboardEventCopyWith<$Res> {
  factory _$DashboardTunnelStatusUpdatedCopyWith(_DashboardTunnelStatusUpdated value, $Res Function(_DashboardTunnelStatusUpdated) _then) = __$DashboardTunnelStatusUpdatedCopyWithImpl;
@useResult
$Res call({
 TunnelStatus status
});




}
/// @nodoc
class __$DashboardTunnelStatusUpdatedCopyWithImpl<$Res>
    implements _$DashboardTunnelStatusUpdatedCopyWith<$Res> {
  __$DashboardTunnelStatusUpdatedCopyWithImpl(this._self, this._then);

  final _DashboardTunnelStatusUpdated _self;
  final $Res Function(_DashboardTunnelStatusUpdated) _then;

/// Create a copy of DashboardEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(_DashboardTunnelStatusUpdated(
null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TunnelStatus,
  ));
}


}

/// @nodoc


class _DashboardTunnelToggled implements DashboardEvent {
  const _DashboardTunnelToggled();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardTunnelToggled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent.tunnelToggled()';
}


}




/// @nodoc


class _DashboardPauseRequested implements DashboardEvent {
  const _DashboardPauseRequested(this.duration);
  

 final  Duration duration;

/// Create a copy of DashboardEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DashboardPauseRequestedCopyWith<_DashboardPauseRequested> get copyWith => __$DashboardPauseRequestedCopyWithImpl<_DashboardPauseRequested>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardPauseRequested&&(identical(other.duration, duration) || other.duration == duration));
}


@override
int get hashCode {
    return Object.hash(runtimeType,duration);
}

@override
String toString() {
    return 'DashboardEvent.pauseRequested(duration: $duration)';
}


}

/// @nodoc
abstract mixin class _$DashboardPauseRequestedCopyWith<$Res> implements $DashboardEventCopyWith<$Res> {
  factory _$DashboardPauseRequestedCopyWith(_DashboardPauseRequested value, $Res Function(_DashboardPauseRequested) _then) = __$DashboardPauseRequestedCopyWithImpl;
@useResult
$Res call({
 Duration duration
});




}
/// @nodoc
class __$DashboardPauseRequestedCopyWithImpl<$Res>
    implements _$DashboardPauseRequestedCopyWith<$Res> {
  __$DashboardPauseRequestedCopyWithImpl(this._self, this._then);

  final _DashboardPauseRequested _self;
  final $Res Function(_DashboardPauseRequested) _then;

/// Create a copy of DashboardEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? duration = null,}) {
  return _then(_DashboardPauseRequested(
null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

/// @nodoc


class _DashboardShutdownRequested implements DashboardEvent {
  const _DashboardShutdownRequested();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardShutdownRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent.shutdownRequested()';
}


}




/// @nodoc


class _DashboardStatsRefreshRequested implements DashboardEvent {
  const _DashboardStatsRefreshRequested();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardStatsRefreshRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent.statsRefreshRequested()';
}


}




/// @nodoc


class _DashboardAppResumed implements DashboardEvent {
  const _DashboardAppResumed();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardAppResumed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent.appResumed()';
}


}




/// @nodoc


class _DashboardErrorMessageDismissed implements DashboardEvent {
  const _DashboardErrorMessageDismissed();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardErrorMessageDismissed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DashboardEvent.errorMessageDismissed()';
}


}




// dart format on
