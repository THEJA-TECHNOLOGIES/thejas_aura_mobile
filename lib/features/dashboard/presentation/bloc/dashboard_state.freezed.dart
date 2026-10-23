// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dashboard_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DashboardState {

 TunnelStatus get status; bool get isInitialized; bool get isTogglingTunnel; bool get isLoadingStats; int? get blockedToday; int? get blockedThisWeek; int? get totalBlockedDomains; List<IndividualBar> get chartData; String? get statsError; String? get errorMessage;
/// Create a copy of DashboardState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DashboardStateCopyWith<DashboardState> get copyWith => _$DashboardStateCopyWithImpl<DashboardState>(this as DashboardState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DashboardState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DashboardState&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.isInitialized, _this.isInitialized) || other.isInitialized == _this.isInitialized)&&(identical(other.isTogglingTunnel, _this.isTogglingTunnel) || other.isTogglingTunnel == _this.isTogglingTunnel)&&(identical(other.isLoadingStats, _this.isLoadingStats) || other.isLoadingStats == _this.isLoadingStats)&&(identical(other.blockedToday, _this.blockedToday) || other.blockedToday == _this.blockedToday)&&(identical(other.blockedThisWeek, _this.blockedThisWeek) || other.blockedThisWeek == _this.blockedThisWeek)&&(identical(other.totalBlockedDomains, _this.totalBlockedDomains) || other.totalBlockedDomains == _this.totalBlockedDomains)&&const DeepCollectionEquality().equals(other.chartData, _this.chartData)&&(identical(other.statsError, _this.statsError) || other.statsError == _this.statsError)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}


@override
int get hashCode {
  final _this = this as DashboardState;
  return Object.hash(runtimeType,_this.status,_this.isInitialized,_this.isTogglingTunnel,_this.isLoadingStats,_this.blockedToday,_this.blockedThisWeek,_this.totalBlockedDomains,const DeepCollectionEquality().hash(_this.chartData),_this.statsError,_this.errorMessage);
}

@override
String toString() {
  final _this = this as DashboardState;
  return 'DashboardState(status: ${_this.status}, isInitialized: ${_this.isInitialized}, isTogglingTunnel: ${_this.isTogglingTunnel}, isLoadingStats: ${_this.isLoadingStats}, blockedToday: ${_this.blockedToday}, blockedThisWeek: ${_this.blockedThisWeek}, totalBlockedDomains: ${_this.totalBlockedDomains}, chartData: ${_this.chartData}, statsError: ${_this.statsError}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $DashboardStateCopyWith<$Res>  {
  factory $DashboardStateCopyWith(DashboardState value, $Res Function(DashboardState) _then) = _$DashboardStateCopyWithImpl;
@useResult
$Res call({
 TunnelStatus status, bool isInitialized, bool isTogglingTunnel, bool isLoadingStats, int? blockedToday, int? blockedThisWeek, int? totalBlockedDomains, List<IndividualBar> chartData, String? statsError, String? errorMessage
});




}
/// @nodoc
class _$DashboardStateCopyWithImpl<$Res>
    implements $DashboardStateCopyWith<$Res> {
  _$DashboardStateCopyWithImpl(this._self, this._then);

  final DashboardState _self;
  final $Res Function(DashboardState) _then;

/// Create a copy of DashboardState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? isInitialized = null,Object? isTogglingTunnel = null,Object? isLoadingStats = null,Object? blockedToday = freezed,Object? blockedThisWeek = freezed,Object? totalBlockedDomains = freezed,Object? chartData = null,Object? statsError = freezed,Object? errorMessage = freezed,}) {
  return _then(DashboardState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TunnelStatus,isInitialized: null == isInitialized ? _self.isInitialized : isInitialized // ignore: cast_nullable_to_non_nullable
as bool,isTogglingTunnel: null == isTogglingTunnel ? _self.isTogglingTunnel : isTogglingTunnel // ignore: cast_nullable_to_non_nullable
as bool,isLoadingStats: null == isLoadingStats ? _self.isLoadingStats : isLoadingStats // ignore: cast_nullable_to_non_nullable
as bool,blockedToday: freezed == blockedToday ? _self.blockedToday : blockedToday // ignore: cast_nullable_to_non_nullable
as int?,blockedThisWeek: freezed == blockedThisWeek ? _self.blockedThisWeek : blockedThisWeek // ignore: cast_nullable_to_non_nullable
as int?,totalBlockedDomains: freezed == totalBlockedDomains ? _self.totalBlockedDomains : totalBlockedDomains // ignore: cast_nullable_to_non_nullable
as int?,chartData: null == chartData ? _self.chartData : chartData // ignore: cast_nullable_to_non_nullable
as List<IndividualBar>,statsError: freezed == statsError ? _self.statsError : statsError // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [DashboardState].
extension DashboardStatePatterns on DashboardState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DashboardState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DashboardState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DashboardState value)  $default,){
final _that = this;
switch (_that) {
case _DashboardState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DashboardState value)?  $default,){
final _that = this;
switch (_that) {
case _DashboardState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TunnelStatus status,  bool isInitialized,  bool isTogglingTunnel,  bool isLoadingStats,  int? blockedToday,  int? blockedThisWeek,  int? totalBlockedDomains,  List<IndividualBar> chartData,  String? statsError,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DashboardState() when $default != null:
return $default(_that.status,_that.isInitialized,_that.isTogglingTunnel,_that.isLoadingStats,_that.blockedToday,_that.blockedThisWeek,_that.totalBlockedDomains,_that.chartData,_that.statsError,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TunnelStatus status,  bool isInitialized,  bool isTogglingTunnel,  bool isLoadingStats,  int? blockedToday,  int? blockedThisWeek,  int? totalBlockedDomains,  List<IndividualBar> chartData,  String? statsError,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _DashboardState():
return $default(_that.status,_that.isInitialized,_that.isTogglingTunnel,_that.isLoadingStats,_that.blockedToday,_that.blockedThisWeek,_that.totalBlockedDomains,_that.chartData,_that.statsError,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TunnelStatus status,  bool isInitialized,  bool isTogglingTunnel,  bool isLoadingStats,  int? blockedToday,  int? blockedThisWeek,  int? totalBlockedDomains,  List<IndividualBar> chartData,  String? statsError,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _DashboardState() when $default != null:
return $default(_that.status,_that.isInitialized,_that.isTogglingTunnel,_that.isLoadingStats,_that.blockedToday,_that.blockedThisWeek,_that.totalBlockedDomains,_that.chartData,_that.statsError,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _DashboardState implements DashboardState {
  const _DashboardState({this.status = TunnelStatus.disconnected, this.isInitialized = false, this.isTogglingTunnel = false, this.isLoadingStats = false, this.blockedToday, this.blockedThisWeek, this.totalBlockedDomains,  List<IndividualBar> chartData = const [], this.statsError, this.errorMessage}): _chartData = chartData;
  

@override@JsonKey() final  TunnelStatus status;
@override@JsonKey() final  bool isInitialized;
@override@JsonKey() final  bool isTogglingTunnel;
@override@JsonKey() final  bool isLoadingStats;
@override final  int? blockedToday;
@override final  int? blockedThisWeek;
@override final  int? totalBlockedDomains;
 final  List<IndividualBar> _chartData;
@override@JsonKey() List<IndividualBar> get chartData {
  if (_chartData is EqualUnmodifiableListView) return _chartData;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_chartData);
}

@override final  String? statsError;
@override final  String? errorMessage;

/// Create a copy of DashboardState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DashboardStateCopyWith<_DashboardState> get copyWith => __$DashboardStateCopyWithImpl<_DashboardState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardState&&(identical(other.status, status) || other.status == status)&&(identical(other.isInitialized, isInitialized) || other.isInitialized == isInitialized)&&(identical(other.isTogglingTunnel, isTogglingTunnel) || other.isTogglingTunnel == isTogglingTunnel)&&(identical(other.isLoadingStats, isLoadingStats) || other.isLoadingStats == isLoadingStats)&&(identical(other.blockedToday, blockedToday) || other.blockedToday == blockedToday)&&(identical(other.blockedThisWeek, blockedThisWeek) || other.blockedThisWeek == blockedThisWeek)&&(identical(other.totalBlockedDomains, totalBlockedDomains) || other.totalBlockedDomains == totalBlockedDomains)&&const DeepCollectionEquality().equals(other.chartData, _chartData)&&(identical(other.statsError, statsError) || other.statsError == statsError)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,isInitialized,isTogglingTunnel,isLoadingStats,blockedToday,blockedThisWeek,totalBlockedDomains,const DeepCollectionEquality().hash(_chartData),statsError,errorMessage);
}

@override
String toString() {
    return 'DashboardState(status: $status, isInitialized: $isInitialized, isTogglingTunnel: $isTogglingTunnel, isLoadingStats: $isLoadingStats, blockedToday: $blockedToday, blockedThisWeek: $blockedThisWeek, totalBlockedDomains: $totalBlockedDomains, chartData: $chartData, statsError: $statsError, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$DashboardStateCopyWith<$Res> implements $DashboardStateCopyWith<$Res> {
  factory _$DashboardStateCopyWith(_DashboardState value, $Res Function(_DashboardState) _then) = __$DashboardStateCopyWithImpl;
@override @useResult
$Res call({
 TunnelStatus status, bool isInitialized, bool isTogglingTunnel, bool isLoadingStats, int? blockedToday, int? blockedThisWeek, int? totalBlockedDomains, List<IndividualBar> chartData, String? statsError, String? errorMessage
});




}
/// @nodoc
class __$DashboardStateCopyWithImpl<$Res>
    implements _$DashboardStateCopyWith<$Res> {
  __$DashboardStateCopyWithImpl(this._self, this._then);

  final _DashboardState _self;
  final $Res Function(_DashboardState) _then;

/// Create a copy of DashboardState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? isInitialized = null,Object? isTogglingTunnel = null,Object? isLoadingStats = null,Object? blockedToday = freezed,Object? blockedThisWeek = freezed,Object? totalBlockedDomains = freezed,Object? chartData = null,Object? statsError = freezed,Object? errorMessage = freezed,}) {
  return _then(_DashboardState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TunnelStatus,isInitialized: null == isInitialized ? _self.isInitialized : isInitialized // ignore: cast_nullable_to_non_nullable
as bool,isTogglingTunnel: null == isTogglingTunnel ? _self.isTogglingTunnel : isTogglingTunnel // ignore: cast_nullable_to_non_nullable
as bool,isLoadingStats: null == isLoadingStats ? _self.isLoadingStats : isLoadingStats // ignore: cast_nullable_to_non_nullable
as bool,blockedToday: freezed == blockedToday ? _self.blockedToday : blockedToday // ignore: cast_nullable_to_non_nullable
as int?,blockedThisWeek: freezed == blockedThisWeek ? _self.blockedThisWeek : blockedThisWeek // ignore: cast_nullable_to_non_nullable
as int?,totalBlockedDomains: freezed == totalBlockedDomains ? _self.totalBlockedDomains : totalBlockedDomains // ignore: cast_nullable_to_non_nullable
as int?,chartData: null == chartData ? _self._chartData : chartData // ignore: cast_nullable_to_non_nullable
as List<IndividualBar>,statsError: freezed == statsError ? _self.statsError : statsError // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
