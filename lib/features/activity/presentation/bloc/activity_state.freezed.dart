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

 List<DnsActivityRecord> get records; bool get isLoading; bool get isLoadingMore; bool get hasMore; int? get nextCursorTimestamp; int? get nextCursorId; String? get errorMessage; String get selectedOutcome; int? get selectedTimeWindowMillis; String get searchQuery; bool get isLogsMode; Map<String, bool> get effectiveBlockedState; Set<String> get pendingDomainToggles; List<AuraRuleItem> get customRules; Set<String> get disabledDefaultDomains; Map<String, bool> get categoryPreferences; String? get actionError;
/// Create a copy of ActivityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityStateCopyWith<ActivityState> get copyWith => _$ActivityStateCopyWithImpl<ActivityState>(this as ActivityState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityState&&const DeepCollectionEquality().equals(other.records, _this.records)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.isLoadingMore, _this.isLoadingMore) || other.isLoadingMore == _this.isLoadingMore)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore)&&(identical(other.nextCursorTimestamp, _this.nextCursorTimestamp) || other.nextCursorTimestamp == _this.nextCursorTimestamp)&&(identical(other.nextCursorId, _this.nextCursorId) || other.nextCursorId == _this.nextCursorId)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.selectedOutcome, _this.selectedOutcome) || other.selectedOutcome == _this.selectedOutcome)&&(identical(other.selectedTimeWindowMillis, _this.selectedTimeWindowMillis) || other.selectedTimeWindowMillis == _this.selectedTimeWindowMillis)&&(identical(other.searchQuery, _this.searchQuery) || other.searchQuery == _this.searchQuery)&&(identical(other.isLogsMode, _this.isLogsMode) || other.isLogsMode == _this.isLogsMode)&&const DeepCollectionEquality().equals(other.effectiveBlockedState, _this.effectiveBlockedState)&&const DeepCollectionEquality().equals(other.pendingDomainToggles, _this.pendingDomainToggles)&&const DeepCollectionEquality().equals(other.customRules, _this.customRules)&&const DeepCollectionEquality().equals(other.disabledDefaultDomains, _this.disabledDefaultDomains)&&const DeepCollectionEquality().equals(other.categoryPreferences, _this.categoryPreferences)&&(identical(other.actionError, _this.actionError) || other.actionError == _this.actionError));
}


@override
int get hashCode {
  final _this = this as ActivityState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.records),_this.isLoading,_this.isLoadingMore,_this.hasMore,_this.nextCursorTimestamp,_this.nextCursorId,_this.errorMessage,_this.selectedOutcome,_this.selectedTimeWindowMillis,_this.searchQuery,_this.isLogsMode,const DeepCollectionEquality().hash(_this.effectiveBlockedState),const DeepCollectionEquality().hash(_this.pendingDomainToggles),const DeepCollectionEquality().hash(_this.customRules),const DeepCollectionEquality().hash(_this.disabledDefaultDomains),const DeepCollectionEquality().hash(_this.categoryPreferences),_this.actionError);
}

@override
String toString() {
  final _this = this as ActivityState;
  return 'ActivityState(records: ${_this.records}, isLoading: ${_this.isLoading}, isLoadingMore: ${_this.isLoadingMore}, hasMore: ${_this.hasMore}, nextCursorTimestamp: ${_this.nextCursorTimestamp}, nextCursorId: ${_this.nextCursorId}, errorMessage: ${_this.errorMessage}, selectedOutcome: ${_this.selectedOutcome}, selectedTimeWindowMillis: ${_this.selectedTimeWindowMillis}, searchQuery: ${_this.searchQuery}, isLogsMode: ${_this.isLogsMode}, effectiveBlockedState: ${_this.effectiveBlockedState}, pendingDomainToggles: ${_this.pendingDomainToggles}, customRules: ${_this.customRules}, disabledDefaultDomains: ${_this.disabledDefaultDomains}, categoryPreferences: ${_this.categoryPreferences}, actionError: ${_this.actionError})';
}


}

/// @nodoc
abstract mixin class $ActivityStateCopyWith<$Res>  {
  factory $ActivityStateCopyWith(ActivityState value, $Res Function(ActivityState) _then) = _$ActivityStateCopyWithImpl;
@useResult
$Res call({
 List<DnsActivityRecord> records, bool isLoading, bool isLoadingMore, bool hasMore, int? nextCursorTimestamp, int? nextCursorId, String? errorMessage, String selectedOutcome, int? selectedTimeWindowMillis, String searchQuery, bool isLogsMode, Map<String, bool> effectiveBlockedState, Set<String> pendingDomainToggles, List<AuraRuleItem> customRules, Set<String> disabledDefaultDomains, Map<String, bool> categoryPreferences, String? actionError
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
@pragma('vm:prefer-inline') @override $Res call({Object? records = null,Object? isLoading = null,Object? isLoadingMore = null,Object? hasMore = null,Object? nextCursorTimestamp = freezed,Object? nextCursorId = freezed,Object? errorMessage = freezed,Object? selectedOutcome = null,Object? selectedTimeWindowMillis = freezed,Object? searchQuery = null,Object? isLogsMode = null,Object? effectiveBlockedState = null,Object? pendingDomainToggles = null,Object? customRules = null,Object? disabledDefaultDomains = null,Object? categoryPreferences = null,Object? actionError = freezed,}) {
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
as bool,effectiveBlockedState: null == effectiveBlockedState ? _self.effectiveBlockedState : effectiveBlockedState // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,pendingDomainToggles: null == pendingDomainToggles ? _self.pendingDomainToggles : pendingDomainToggles // ignore: cast_nullable_to_non_nullable
as Set<String>,customRules: null == customRules ? _self.customRules : customRules // ignore: cast_nullable_to_non_nullable
as List<AuraRuleItem>,disabledDefaultDomains: null == disabledDefaultDomains ? _self.disabledDefaultDomains : disabledDefaultDomains // ignore: cast_nullable_to_non_nullable
as Set<String>,categoryPreferences: null == categoryPreferences ? _self.categoryPreferences : categoryPreferences // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,actionError: freezed == actionError ? _self.actionError : actionError // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<DnsActivityRecord> records,  bool isLoading,  bool isLoadingMore,  bool hasMore,  int? nextCursorTimestamp,  int? nextCursorId,  String? errorMessage,  String selectedOutcome,  int? selectedTimeWindowMillis,  String searchQuery,  bool isLogsMode,  Map<String, bool> effectiveBlockedState,  Set<String> pendingDomainToggles,  List<AuraRuleItem> customRules,  Set<String> disabledDefaultDomains,  Map<String, bool> categoryPreferences,  String? actionError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityState() when $default != null:
return $default(_that.records,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.nextCursorTimestamp,_that.nextCursorId,_that.errorMessage,_that.selectedOutcome,_that.selectedTimeWindowMillis,_that.searchQuery,_that.isLogsMode,_that.effectiveBlockedState,_that.pendingDomainToggles,_that.customRules,_that.disabledDefaultDomains,_that.categoryPreferences,_that.actionError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<DnsActivityRecord> records,  bool isLoading,  bool isLoadingMore,  bool hasMore,  int? nextCursorTimestamp,  int? nextCursorId,  String? errorMessage,  String selectedOutcome,  int? selectedTimeWindowMillis,  String searchQuery,  bool isLogsMode,  Map<String, bool> effectiveBlockedState,  Set<String> pendingDomainToggles,  List<AuraRuleItem> customRules,  Set<String> disabledDefaultDomains,  Map<String, bool> categoryPreferences,  String? actionError)  $default,) {final _that = this;
switch (_that) {
case _ActivityState():
return $default(_that.records,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.nextCursorTimestamp,_that.nextCursorId,_that.errorMessage,_that.selectedOutcome,_that.selectedTimeWindowMillis,_that.searchQuery,_that.isLogsMode,_that.effectiveBlockedState,_that.pendingDomainToggles,_that.customRules,_that.disabledDefaultDomains,_that.categoryPreferences,_that.actionError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<DnsActivityRecord> records,  bool isLoading,  bool isLoadingMore,  bool hasMore,  int? nextCursorTimestamp,  int? nextCursorId,  String? errorMessage,  String selectedOutcome,  int? selectedTimeWindowMillis,  String searchQuery,  bool isLogsMode,  Map<String, bool> effectiveBlockedState,  Set<String> pendingDomainToggles,  List<AuraRuleItem> customRules,  Set<String> disabledDefaultDomains,  Map<String, bool> categoryPreferences,  String? actionError)?  $default,) {final _that = this;
switch (_that) {
case _ActivityState() when $default != null:
return $default(_that.records,_that.isLoading,_that.isLoadingMore,_that.hasMore,_that.nextCursorTimestamp,_that.nextCursorId,_that.errorMessage,_that.selectedOutcome,_that.selectedTimeWindowMillis,_that.searchQuery,_that.isLogsMode,_that.effectiveBlockedState,_that.pendingDomainToggles,_that.customRules,_that.disabledDefaultDomains,_that.categoryPreferences,_that.actionError);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityState extends ActivityState {
  const _ActivityState({ List<DnsActivityRecord> records = const [], this.isLoading = false, this.isLoadingMore = false, this.hasMore = false, this.nextCursorTimestamp, this.nextCursorId, this.errorMessage, this.selectedOutcome = 'all', this.selectedTimeWindowMillis, this.searchQuery = '', this.isLogsMode = false,  Map<String, bool> effectiveBlockedState = const {},  Set<String> pendingDomainToggles = const {},  List<AuraRuleItem> customRules = const [],  Set<String> disabledDefaultDomains = const {},  Map<String, bool> categoryPreferences = const {}, this.actionError}): _records = records,_effectiveBlockedState = effectiveBlockedState,_pendingDomainToggles = pendingDomainToggles,_customRules = customRules,_disabledDefaultDomains = disabledDefaultDomains,_categoryPreferences = categoryPreferences,super._();
  

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
 final  Map<String, bool> _effectiveBlockedState;
@override@JsonKey() Map<String, bool> get effectiveBlockedState {
  if (_effectiveBlockedState is EqualUnmodifiableMapView) return _effectiveBlockedState;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_effectiveBlockedState);
}

 final  Set<String> _pendingDomainToggles;
@override@JsonKey() Set<String> get pendingDomainToggles {
  if (_pendingDomainToggles is EqualUnmodifiableSetView) return _pendingDomainToggles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_pendingDomainToggles);
}

 final  List<AuraRuleItem> _customRules;
@override@JsonKey() List<AuraRuleItem> get customRules {
  if (_customRules is EqualUnmodifiableListView) return _customRules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_customRules);
}

 final  Set<String> _disabledDefaultDomains;
@override@JsonKey() Set<String> get disabledDefaultDomains {
  if (_disabledDefaultDomains is EqualUnmodifiableSetView) return _disabledDefaultDomains;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_disabledDefaultDomains);
}

 final  Map<String, bool> _categoryPreferences;
@override@JsonKey() Map<String, bool> get categoryPreferences {
  if (_categoryPreferences is EqualUnmodifiableMapView) return _categoryPreferences;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_categoryPreferences);
}

@override final  String? actionError;

/// Create a copy of ActivityState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityStateCopyWith<_ActivityState> get copyWith => __$ActivityStateCopyWithImpl<_ActivityState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityState&&const DeepCollectionEquality().equals(other.records, _records)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isLoadingMore, isLoadingMore) || other.isLoadingMore == isLoadingMore)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.nextCursorTimestamp, nextCursorTimestamp) || other.nextCursorTimestamp == nextCursorTimestamp)&&(identical(other.nextCursorId, nextCursorId) || other.nextCursorId == nextCursorId)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.selectedOutcome, selectedOutcome) || other.selectedOutcome == selectedOutcome)&&(identical(other.selectedTimeWindowMillis, selectedTimeWindowMillis) || other.selectedTimeWindowMillis == selectedTimeWindowMillis)&&(identical(other.searchQuery, searchQuery) || other.searchQuery == searchQuery)&&(identical(other.isLogsMode, isLogsMode) || other.isLogsMode == isLogsMode)&&const DeepCollectionEquality().equals(other.effectiveBlockedState, _effectiveBlockedState)&&const DeepCollectionEquality().equals(other.pendingDomainToggles, _pendingDomainToggles)&&const DeepCollectionEquality().equals(other.customRules, _customRules)&&const DeepCollectionEquality().equals(other.disabledDefaultDomains, _disabledDefaultDomains)&&const DeepCollectionEquality().equals(other.categoryPreferences, _categoryPreferences)&&(identical(other.actionError, actionError) || other.actionError == actionError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_records),isLoading,isLoadingMore,hasMore,nextCursorTimestamp,nextCursorId,errorMessage,selectedOutcome,selectedTimeWindowMillis,searchQuery,isLogsMode,const DeepCollectionEquality().hash(_effectiveBlockedState),const DeepCollectionEquality().hash(_pendingDomainToggles),const DeepCollectionEquality().hash(_customRules),const DeepCollectionEquality().hash(_disabledDefaultDomains),const DeepCollectionEquality().hash(_categoryPreferences),actionError);
}

@override
String toString() {
    return 'ActivityState(records: $records, isLoading: $isLoading, isLoadingMore: $isLoadingMore, hasMore: $hasMore, nextCursorTimestamp: $nextCursorTimestamp, nextCursorId: $nextCursorId, errorMessage: $errorMessage, selectedOutcome: $selectedOutcome, selectedTimeWindowMillis: $selectedTimeWindowMillis, searchQuery: $searchQuery, isLogsMode: $isLogsMode, effectiveBlockedState: $effectiveBlockedState, pendingDomainToggles: $pendingDomainToggles, customRules: $customRules, disabledDefaultDomains: $disabledDefaultDomains, categoryPreferences: $categoryPreferences, actionError: $actionError)';
}


}

/// @nodoc
abstract mixin class _$ActivityStateCopyWith<$Res> implements $ActivityStateCopyWith<$Res> {
  factory _$ActivityStateCopyWith(_ActivityState value, $Res Function(_ActivityState) _then) = __$ActivityStateCopyWithImpl;
@override @useResult
$Res call({
 List<DnsActivityRecord> records, bool isLoading, bool isLoadingMore, bool hasMore, int? nextCursorTimestamp, int? nextCursorId, String? errorMessage, String selectedOutcome, int? selectedTimeWindowMillis, String searchQuery, bool isLogsMode, Map<String, bool> effectiveBlockedState, Set<String> pendingDomainToggles, List<AuraRuleItem> customRules, Set<String> disabledDefaultDomains, Map<String, bool> categoryPreferences, String? actionError
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
@override @pragma('vm:prefer-inline') $Res call({Object? records = null,Object? isLoading = null,Object? isLoadingMore = null,Object? hasMore = null,Object? nextCursorTimestamp = freezed,Object? nextCursorId = freezed,Object? errorMessage = freezed,Object? selectedOutcome = null,Object? selectedTimeWindowMillis = freezed,Object? searchQuery = null,Object? isLogsMode = null,Object? effectiveBlockedState = null,Object? pendingDomainToggles = null,Object? customRules = null,Object? disabledDefaultDomains = null,Object? categoryPreferences = null,Object? actionError = freezed,}) {
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
as bool,effectiveBlockedState: null == effectiveBlockedState ? _self._effectiveBlockedState : effectiveBlockedState // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,pendingDomainToggles: null == pendingDomainToggles ? _self._pendingDomainToggles : pendingDomainToggles // ignore: cast_nullable_to_non_nullable
as Set<String>,customRules: null == customRules ? _self._customRules : customRules // ignore: cast_nullable_to_non_nullable
as List<AuraRuleItem>,disabledDefaultDomains: null == disabledDefaultDomains ? _self._disabledDefaultDomains : disabledDefaultDomains // ignore: cast_nullable_to_non_nullable
as Set<String>,categoryPreferences: null == categoryPreferences ? _self._categoryPreferences : categoryPreferences // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,actionError: freezed == actionError ? _self.actionError : actionError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
