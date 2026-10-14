// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'activity_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActivityEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityEvent()';
}


}

/// @nodoc
class $ActivityEventCopyWith<$Res>  {
$ActivityEventCopyWith(ActivityEvent _, $Res Function(ActivityEvent) __);
}


/// Adds pattern-matching-related methods to [ActivityEvent].
extension ActivityEventPatterns on ActivityEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _ActivityStarted value)?  started,TResult Function( _ActivityInitialPageRequested value)?  initialPageRequested,TResult Function( _ActivityLoadMoreRequested value)?  loadMoreRequested,TResult Function( _ActivityRefreshRequested value)?  refreshRequested,TResult Function( _ActivityOutcomeFilterChanged value)?  outcomeFilterChanged,TResult Function( _ActivityTimeWindowFilterChanged value)?  timeWindowFilterChanged,TResult Function( _ActivitySearchQueryChanged value)?  searchQueryChanged,TResult Function( _ActivityAppResumed value)?  appResumed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityStarted() when started != null:
return started(_that);case _ActivityInitialPageRequested() when initialPageRequested != null:
return initialPageRequested(_that);case _ActivityLoadMoreRequested() when loadMoreRequested != null:
return loadMoreRequested(_that);case _ActivityRefreshRequested() when refreshRequested != null:
return refreshRequested(_that);case _ActivityOutcomeFilterChanged() when outcomeFilterChanged != null:
return outcomeFilterChanged(_that);case _ActivityTimeWindowFilterChanged() when timeWindowFilterChanged != null:
return timeWindowFilterChanged(_that);case _ActivitySearchQueryChanged() when searchQueryChanged != null:
return searchQueryChanged(_that);case _ActivityAppResumed() when appResumed != null:
return appResumed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _ActivityStarted value)  started,required TResult Function( _ActivityInitialPageRequested value)  initialPageRequested,required TResult Function( _ActivityLoadMoreRequested value)  loadMoreRequested,required TResult Function( _ActivityRefreshRequested value)  refreshRequested,required TResult Function( _ActivityOutcomeFilterChanged value)  outcomeFilterChanged,required TResult Function( _ActivityTimeWindowFilterChanged value)  timeWindowFilterChanged,required TResult Function( _ActivitySearchQueryChanged value)  searchQueryChanged,required TResult Function( _ActivityAppResumed value)  appResumed,}){
final _that = this;
switch (_that) {
case _ActivityStarted():
return started(_that);case _ActivityInitialPageRequested():
return initialPageRequested(_that);case _ActivityLoadMoreRequested():
return loadMoreRequested(_that);case _ActivityRefreshRequested():
return refreshRequested(_that);case _ActivityOutcomeFilterChanged():
return outcomeFilterChanged(_that);case _ActivityTimeWindowFilterChanged():
return timeWindowFilterChanged(_that);case _ActivitySearchQueryChanged():
return searchQueryChanged(_that);case _ActivityAppResumed():
return appResumed(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _ActivityStarted value)?  started,TResult? Function( _ActivityInitialPageRequested value)?  initialPageRequested,TResult? Function( _ActivityLoadMoreRequested value)?  loadMoreRequested,TResult? Function( _ActivityRefreshRequested value)?  refreshRequested,TResult? Function( _ActivityOutcomeFilterChanged value)?  outcomeFilterChanged,TResult? Function( _ActivityTimeWindowFilterChanged value)?  timeWindowFilterChanged,TResult? Function( _ActivitySearchQueryChanged value)?  searchQueryChanged,TResult? Function( _ActivityAppResumed value)?  appResumed,}){
final _that = this;
switch (_that) {
case _ActivityStarted() when started != null:
return started(_that);case _ActivityInitialPageRequested() when initialPageRequested != null:
return initialPageRequested(_that);case _ActivityLoadMoreRequested() when loadMoreRequested != null:
return loadMoreRequested(_that);case _ActivityRefreshRequested() when refreshRequested != null:
return refreshRequested(_that);case _ActivityOutcomeFilterChanged() when outcomeFilterChanged != null:
return outcomeFilterChanged(_that);case _ActivityTimeWindowFilterChanged() when timeWindowFilterChanged != null:
return timeWindowFilterChanged(_that);case _ActivitySearchQueryChanged() when searchQueryChanged != null:
return searchQueryChanged(_that);case _ActivityAppResumed() when appResumed != null:
return appResumed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool isLogsMode)?  started,TResult Function()?  initialPageRequested,TResult Function()?  loadMoreRequested,TResult Function()?  refreshRequested,TResult Function( String outcome)?  outcomeFilterChanged,TResult Function( int? timeWindowMillis)?  timeWindowFilterChanged,TResult Function( String query)?  searchQueryChanged,TResult Function()?  appResumed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityStarted() when started != null:
return started(_that.isLogsMode);case _ActivityInitialPageRequested() when initialPageRequested != null:
return initialPageRequested();case _ActivityLoadMoreRequested() when loadMoreRequested != null:
return loadMoreRequested();case _ActivityRefreshRequested() when refreshRequested != null:
return refreshRequested();case _ActivityOutcomeFilterChanged() when outcomeFilterChanged != null:
return outcomeFilterChanged(_that.outcome);case _ActivityTimeWindowFilterChanged() when timeWindowFilterChanged != null:
return timeWindowFilterChanged(_that.timeWindowMillis);case _ActivitySearchQueryChanged() when searchQueryChanged != null:
return searchQueryChanged(_that.query);case _ActivityAppResumed() when appResumed != null:
return appResumed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool isLogsMode)  started,required TResult Function()  initialPageRequested,required TResult Function()  loadMoreRequested,required TResult Function()  refreshRequested,required TResult Function( String outcome)  outcomeFilterChanged,required TResult Function( int? timeWindowMillis)  timeWindowFilterChanged,required TResult Function( String query)  searchQueryChanged,required TResult Function()  appResumed,}) {final _that = this;
switch (_that) {
case _ActivityStarted():
return started(_that.isLogsMode);case _ActivityInitialPageRequested():
return initialPageRequested();case _ActivityLoadMoreRequested():
return loadMoreRequested();case _ActivityRefreshRequested():
return refreshRequested();case _ActivityOutcomeFilterChanged():
return outcomeFilterChanged(_that.outcome);case _ActivityTimeWindowFilterChanged():
return timeWindowFilterChanged(_that.timeWindowMillis);case _ActivitySearchQueryChanged():
return searchQueryChanged(_that.query);case _ActivityAppResumed():
return appResumed();case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool isLogsMode)?  started,TResult? Function()?  initialPageRequested,TResult? Function()?  loadMoreRequested,TResult? Function()?  refreshRequested,TResult? Function( String outcome)?  outcomeFilterChanged,TResult? Function( int? timeWindowMillis)?  timeWindowFilterChanged,TResult? Function( String query)?  searchQueryChanged,TResult? Function()?  appResumed,}) {final _that = this;
switch (_that) {
case _ActivityStarted() when started != null:
return started(_that.isLogsMode);case _ActivityInitialPageRequested() when initialPageRequested != null:
return initialPageRequested();case _ActivityLoadMoreRequested() when loadMoreRequested != null:
return loadMoreRequested();case _ActivityRefreshRequested() when refreshRequested != null:
return refreshRequested();case _ActivityOutcomeFilterChanged() when outcomeFilterChanged != null:
return outcomeFilterChanged(_that.outcome);case _ActivityTimeWindowFilterChanged() when timeWindowFilterChanged != null:
return timeWindowFilterChanged(_that.timeWindowMillis);case _ActivitySearchQueryChanged() when searchQueryChanged != null:
return searchQueryChanged(_that.query);case _ActivityAppResumed() when appResumed != null:
return appResumed();case _:
  return null;

}
}

}

/// @nodoc


class _ActivityStarted implements ActivityEvent {
  const _ActivityStarted({this.isLogsMode = false});
  

@JsonKey() final  bool isLogsMode;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityStartedCopyWith<_ActivityStarted> get copyWith => __$ActivityStartedCopyWithImpl<_ActivityStarted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityStarted&&(identical(other.isLogsMode, isLogsMode) || other.isLogsMode == isLogsMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,isLogsMode);
}

@override
String toString() {
    return 'ActivityEvent.started(isLogsMode: $isLogsMode)';
}


}

/// @nodoc
abstract mixin class _$ActivityStartedCopyWith<$Res> implements $ActivityEventCopyWith<$Res> {
  factory _$ActivityStartedCopyWith(_ActivityStarted value, $Res Function(_ActivityStarted) _then) = __$ActivityStartedCopyWithImpl;
@useResult
$Res call({
 bool isLogsMode
});




}
/// @nodoc
class __$ActivityStartedCopyWithImpl<$Res>
    implements _$ActivityStartedCopyWith<$Res> {
  __$ActivityStartedCopyWithImpl(this._self, this._then);

  final _ActivityStarted _self;
  final $Res Function(_ActivityStarted) _then;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? isLogsMode = null,}) {
  return _then(_ActivityStarted(
isLogsMode: null == isLogsMode ? _self.isLogsMode : isLogsMode // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class _ActivityInitialPageRequested implements ActivityEvent {
  const _ActivityInitialPageRequested();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityInitialPageRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityEvent.initialPageRequested()';
}


}




/// @nodoc


class _ActivityLoadMoreRequested implements ActivityEvent {
  const _ActivityLoadMoreRequested();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityLoadMoreRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityEvent.loadMoreRequested()';
}


}




/// @nodoc


class _ActivityRefreshRequested implements ActivityEvent {
  const _ActivityRefreshRequested();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityRefreshRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityEvent.refreshRequested()';
}


}




/// @nodoc


class _ActivityOutcomeFilterChanged implements ActivityEvent {
  const _ActivityOutcomeFilterChanged(this.outcome);
  

 final  String outcome;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityOutcomeFilterChangedCopyWith<_ActivityOutcomeFilterChanged> get copyWith => __$ActivityOutcomeFilterChangedCopyWithImpl<_ActivityOutcomeFilterChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityOutcomeFilterChanged&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,outcome);
}

@override
String toString() {
    return 'ActivityEvent.outcomeFilterChanged(outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class _$ActivityOutcomeFilterChangedCopyWith<$Res> implements $ActivityEventCopyWith<$Res> {
  factory _$ActivityOutcomeFilterChangedCopyWith(_ActivityOutcomeFilterChanged value, $Res Function(_ActivityOutcomeFilterChanged) _then) = __$ActivityOutcomeFilterChangedCopyWithImpl;
@useResult
$Res call({
 String outcome
});




}
/// @nodoc
class __$ActivityOutcomeFilterChangedCopyWithImpl<$Res>
    implements _$ActivityOutcomeFilterChangedCopyWith<$Res> {
  __$ActivityOutcomeFilterChangedCopyWithImpl(this._self, this._then);

  final _ActivityOutcomeFilterChanged _self;
  final $Res Function(_ActivityOutcomeFilterChanged) _then;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? outcome = null,}) {
  return _then(_ActivityOutcomeFilterChanged(
null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _ActivityTimeWindowFilterChanged implements ActivityEvent {
  const _ActivityTimeWindowFilterChanged(this.timeWindowMillis);
  

 final  int? timeWindowMillis;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityTimeWindowFilterChangedCopyWith<_ActivityTimeWindowFilterChanged> get copyWith => __$ActivityTimeWindowFilterChangedCopyWithImpl<_ActivityTimeWindowFilterChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityTimeWindowFilterChanged&&(identical(other.timeWindowMillis, timeWindowMillis) || other.timeWindowMillis == timeWindowMillis));
}


@override
int get hashCode {
    return Object.hash(runtimeType,timeWindowMillis);
}

@override
String toString() {
    return 'ActivityEvent.timeWindowFilterChanged(timeWindowMillis: $timeWindowMillis)';
}


}

/// @nodoc
abstract mixin class _$ActivityTimeWindowFilterChangedCopyWith<$Res> implements $ActivityEventCopyWith<$Res> {
  factory _$ActivityTimeWindowFilterChangedCopyWith(_ActivityTimeWindowFilterChanged value, $Res Function(_ActivityTimeWindowFilterChanged) _then) = __$ActivityTimeWindowFilterChangedCopyWithImpl;
@useResult
$Res call({
 int? timeWindowMillis
});




}
/// @nodoc
class __$ActivityTimeWindowFilterChangedCopyWithImpl<$Res>
    implements _$ActivityTimeWindowFilterChangedCopyWith<$Res> {
  __$ActivityTimeWindowFilterChangedCopyWithImpl(this._self, this._then);

  final _ActivityTimeWindowFilterChanged _self;
  final $Res Function(_ActivityTimeWindowFilterChanged) _then;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? timeWindowMillis = freezed,}) {
  return _then(_ActivityTimeWindowFilterChanged(
freezed == timeWindowMillis ? _self.timeWindowMillis : timeWindowMillis // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class _ActivitySearchQueryChanged implements ActivityEvent {
  const _ActivitySearchQueryChanged(this.query);
  

 final  String query;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivitySearchQueryChangedCopyWith<_ActivitySearchQueryChanged> get copyWith => __$ActivitySearchQueryChangedCopyWithImpl<_ActivitySearchQueryChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivitySearchQueryChanged&&(identical(other.query, query) || other.query == query));
}


@override
int get hashCode {
    return Object.hash(runtimeType,query);
}

@override
String toString() {
    return 'ActivityEvent.searchQueryChanged(query: $query)';
}


}

/// @nodoc
abstract mixin class _$ActivitySearchQueryChangedCopyWith<$Res> implements $ActivityEventCopyWith<$Res> {
  factory _$ActivitySearchQueryChangedCopyWith(_ActivitySearchQueryChanged value, $Res Function(_ActivitySearchQueryChanged) _then) = __$ActivitySearchQueryChangedCopyWithImpl;
@useResult
$Res call({
 String query
});




}
/// @nodoc
class __$ActivitySearchQueryChangedCopyWithImpl<$Res>
    implements _$ActivitySearchQueryChangedCopyWith<$Res> {
  __$ActivitySearchQueryChangedCopyWithImpl(this._self, this._then);

  final _ActivitySearchQueryChanged _self;
  final $Res Function(_ActivitySearchQueryChanged) _then;

/// Create a copy of ActivityEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,}) {
  return _then(_ActivitySearchQueryChanged(
null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _ActivityAppResumed implements ActivityEvent {
  const _ActivityAppResumed();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityAppResumed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ActivityEvent.appResumed()';
}


}




// dart format on
