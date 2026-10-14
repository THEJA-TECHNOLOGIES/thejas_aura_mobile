// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'activity_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActivityState {

 List<DnsActivityRecord> get records; bool get isLoading; bool get isLoadingMore; bool get hasMore; int? get nextCursorTimestamp; int? get nextCursorId; String? get errorMessage; String get selectedOutcome; int? get selectedTimeWindowMillis; String get searchQuery; bool get isLogsMode;
/// Create a copy of ActivityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityStateCopyWith<ActivityState> get copyWith => _$ActivityStateCopyWithImpl<ActivityState>(this as ActivityState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityState&&const DeepCollectionEquality().equals(other.records, _this.records)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.isLoadingMore, _this.isLoadingMore) || other.isLoadingMore == _this.isLoadingMore)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore)&&(identical(other.nextCursorTimestamp, _this.nextCursorTimestamp) || other.nextCursorTimestamp == _this.nextCursorTimestamp)&&(identical(other.nextCursorId, _this.nextCursorId) || other.nextCursorId == _this.nextCursorId)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.selectedOutcome, _this.selectedOutcome) || other.selectedOutcome == _this.selectedOutcome)&&(identical(other.selectedTimeWindowMillis, _this.selectedTimeWindowMillis) || other.selectedTimeWindowMillis == _this.selectedTimeWindowMillis)&&(identical(other.searchQuery, _this.searchQuery) || other.searchQuery == _this.searchQuery)&&(identical(other.isLogsMode, _this.isLogsMode) || other.isLogsMode == _this.isLogsMode));
}


@override
int get hashCode {
  final _this = this as ActivityState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.records),_this.isLoading,_this.isLoadingMore,_this.hasMore,_this.nextCursorTimestamp,_this.nextCursorId,_this.errorMessage,_this.selectedOutcome,_this.selectedTimeWindowMillis,_this.searchQuery,_this.isLogsMode);
}

@override
String toString() {
  final _this = this as ActivityState;
  return 'ActivityState(records: ${_this.records}, isLoading: ${_this.isLoading}, isLoadingMore: ${_this.isLoadingMore}, hasMore: ${_this.hasMore}, nextCursorTimestamp: ${_this.nextCursorTimestamp}, nextCursorId: ${_this.nextCursorId}, errorMessage: ${_this.errorMessage}, selectedOutcome: ${_this.selectedOutcome}, selectedTimeWindowMillis: ${_this.selectedTimeWindowMillis}, searchQuery: ${_this.searchQuery}, isLogsMode: ${_this.isLogsMode})';
}


}

/// @nodoc
abstract mixin class $ActivityStateCopyWith<$Res>  {
  factory $ActivityStateCopyWith(ActivityState value, $Res Function(ActivityState) _then) = _$ActivityStateCopyWithImpl;
@useResult
$Res call({
 List<DnsActivityRecord> records, bool isLoading, bool isLoadingMore, bool hasMore, int? nextCursorTimestamp, int? nextCursorId, String? errorMessage, String selectedOutcome, int? selectedTimeWindowMillis, String searchQuery, bool isLogsMode
});




}
/// @nodoc
class _$ActivityStateCopyWithImpl<$Res>
    implements $ActivityStateCopyWith<$Res> {
  _$ActivityStateCopyWithImpl(this._self, this._then);

  final ActivityState _self;
  final $Res Function(ActivityState) _then;

/// Create a copy of ActivityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? records = null,Object? isLoading = null,Object? isLoadingMore = null,Object? hasMore = null,Object? nextCursorTimestamp = freezed,Object? nextCursorId = freezed,Object? errorMessage = freezed,Object? selectedOutcome = null,Object? selectedTimeWindowMillis = freezed,Object? searchQuery = null,Object? isLogsMode = null,}) {
  return _then(ActivityState(
records: null == records ? _self.records : records // ignore: cast_nullable_to_non_nullable
as List<DnsActivityRecord>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isLoadingMore: null == isLoadingMore ? _self.isLoadingMore : isLoadingMore // ignore: cast_nullable_to_non_nullable
as bool,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,nextCursorTimestamp: freezed == nextCursorTimestamp ? _self.nextCursorTimestamp : nextCursorTimestamp // ignore: cast_nullable_to_non_nullable
as int?,nextCursorId: freezed == nextCursorId ? _self.nextCursorId : nextCursorId // ignore: cast_nullable_to_non_nullable
as int?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,selectedOutcome: null == selectedOutcome ? _self.selectedOutcome : selectedOutcome // ignore: cast_nullable_to_non_nullable
as String,selectedTimeWindowMillis: freezed == selectedTimeWindowMillis ? _self.selectedTimeWindowMillis : selectedTimeWindowMillis // ignore: cast_nullable_to_non_nullable
as int?,searchQuery: null == searchQuery ? _self.searchQuery : searchQuery // ignore: cast_nullable_to_non_nullable
as String,isLogsMode: null == isLogsMode ? _self.isLogsMode : isLogsMode // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ActivityState].
extension ActivityStatePatterns on ActivityState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityState value)  $default,){
final _that = this;
switch (_that) {
case _ActivityState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityState value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<DnsActivityRecord> records,  bool isLoading,  bool isLoadingMore,  bool hasMore,  int? nextCursorTimestamp,  int? nextCursorId,  String? errorMessage,  String selectedOutcome,  int? selectedTimeWindowMillis,  String searchQuery,  bool isLogsMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityState() when $default != null:
return $default(_that.records,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.nextCursorTimestamp,_that.nextCursorId,_that.errorMessage,_that.selectedOutcome,_that.selectedTimeWindowMillis,_that.searchQuery,_that.isLogsMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<DnsActivityRecord> records,  bool isLoading,  bool isLoadingMore,  bool hasMore,  int? nextCursorTimestamp,  int? nextCursorId,  String? errorMessage,  String selectedOutcome,  int? selectedTimeWindowMillis,  String searchQuery,  bool isLogsMode)  $default,) {final _that = this;
switch (_that) {
case _ActivityState():
return $default(_that.records,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.nextCursorTimestamp,_that.nextCursorId,_that.errorMessage,_that.selectedOutcome,_that.selectedTimeWindowMillis,_that.searchQuery,_that.isLogsMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<DnsActivityRecord> records,  bool isLoading,  bool isLoadingMore,  bool hasMore,  int? nextCursorTimestamp,  int? nextCursorId,  String? errorMessage,  String selectedOutcome,  int? selectedTimeWindowMillis,  String searchQuery,  bool isLogsMode)?  $default,) {final _that = this;
switch (_that) {
case _ActivityState() when $default != null:
return $default(_that.records,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.nextCursorTimestamp,_that.nextCursorId,_that.errorMessage,_that.selectedOutcome,_that.selectedTimeWindowMillis,_that.searchQuery,_that.isLogsMode);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityState implements ActivityState {
  const _ActivityState({ List<DnsActivityRecord> records = const [], this.isLoading = false, this.isLoadingMore = false, this.hasMore = false, this.nextCursorTimestamp, this.nextCursorId, this.errorMessage, this.selectedOutcome = 'all', this.selectedTimeWindowMillis, this.searchQuery = '', this.isLogsMode = false}): _records = records;
  

 final  List<DnsActivityRecord> _records;
@override@JsonKey() List<DnsActivityRecord> get records {
  if (_records is EqualUnmodifiableListView) return _records;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_records);
}

@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isLoadingMore;
@override@JsonKey() final  bool hasMore;
@override final  int? nextCursorTimestamp;
@override final  int? nextCursorId;
@override final  String? errorMessage;
@override@JsonKey() final  String selectedOutcome;
@override final  int? selectedTimeWindowMillis;
@override@JsonKey() final  String searchQuery;
@override@JsonKey() final  bool isLogsMode;

/// Create a copy of ActivityState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityStateCopyWith<_ActivityState> get copyWith => __$ActivityStateCopyWithImpl<_ActivityState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityState&&const DeepCollectionEquality().equals(other.records, _records)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isLoadingMore, isLoadingMore) || other.isLoadingMore == isLoadingMore)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.nextCursorTimestamp, nextCursorTimestamp) || other.nextCursorTimestamp == nextCursorTimestamp)&&(identical(other.nextCursorId, nextCursorId) || other.nextCursorId == nextCursorId)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.selectedOutcome, selectedOutcome) || other.selectedOutcome == selectedOutcome)&&(identical(other.selectedTimeWindowMillis, selectedTimeWindowMillis) || other.selectedTimeWindowMillis == selectedTimeWindowMillis)&&(identical(other.searchQuery, searchQuery) || other.searchQuery == searchQuery)&&(identical(other.isLogsMode, isLogsMode) || other.isLogsMode == isLogsMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_records),isLoading,isLoadingMore,hasMore,nextCursorTimestamp,nextCursorId,errorMessage,selectedOutcome,selectedTimeWindowMillis,searchQuery,isLogsMode);
}

@override
String toString() {
    return 'ActivityState(records: $records, isLoading: $isLoading, isLoadingMore: $isLoadingMore, hasMore: $hasMore, nextCursorTimestamp: $nextCursorTimestamp, nextCursorId: $nextCursorId, errorMessage: $errorMessage, selectedOutcome: $selectedOutcome, selectedTimeWindowMillis: $selectedTimeWindowMillis, searchQuery: $searchQuery, isLogsMode: $isLogsMode)';
}


}

/// @nodoc
abstract mixin class _$ActivityStateCopyWith<$Res> implements $ActivityStateCopyWith<$Res> {
  factory _$ActivityStateCopyWith(_ActivityState value, $Res Function(_ActivityState) _then) = __$ActivityStateCopyWithImpl;
@override @useResult
$Res call({
 List<DnsActivityRecord> records, bool isLoading, bool isLoadingMore, bool hasMore, int? nextCursorTimestamp, int? nextCursorId, String? errorMessage, String selectedOutcome, int? selectedTimeWindowMillis, String searchQuery, bool isLogsMode
});




}
/// @nodoc
class __$ActivityStateCopyWithImpl<$Res>
    implements _$ActivityStateCopyWith<$Res> {
  __$ActivityStateCopyWithImpl(this._self, this._then);

  final _ActivityState _self;
  final $Res Function(_ActivityState) _then;

/// Create a copy of ActivityState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? records = null,Object? isLoading = null,Object? isLoadingMore = null,Object? hasMore = null,Object? nextCursorTimestamp = freezed,Object? nextCursorId = freezed,Object? errorMessage = freezed,Object? selectedOutcome = null,Object? selectedTimeWindowMillis = freezed,Object? searchQuery = null,Object? isLogsMode = null,}) {
  return _then(_ActivityState(
records: null == records ? _self._records : records // ignore: cast_nullable_to_non_nullable
as List<DnsActivityRecord>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isLoadingMore: null == isLoadingMore ? _self.isLoadingMore : isLoadingMore // ignore: cast_nullable_to_non_nullable
as bool,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,nextCursorTimestamp: freezed == nextCursorTimestamp ? _self.nextCursorTimestamp : nextCursorTimestamp // ignore: cast_nullable_to_non_nullable
as int?,nextCursorId: freezed == nextCursorId ? _self.nextCursorId : nextCursorId // ignore: cast_nullable_to_non_nullable
as int?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,selectedOutcome: null == selectedOutcome ? _self.selectedOutcome : selectedOutcome // ignore: cast_nullable_to_non_nullable
as String,selectedTimeWindowMillis: freezed == selectedTimeWindowMillis ? _self.selectedTimeWindowMillis : selectedTimeWindowMillis // ignore: cast_nullable_to_non_nullable
as int?,searchQuery: null == searchQuery ? _self.searchQuery : searchQuery // ignore: cast_nullable_to_non_nullable
as String,isLogsMode: null == isLogsMode ? _self.isLogsMode : isLogsMode // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
