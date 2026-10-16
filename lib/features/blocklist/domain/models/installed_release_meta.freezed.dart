// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'installed_release_meta.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$InstalledReleaseMeta {

 String get version; DateTime get installedAt; int get domainCount; Map<String, String> get categoryFiles; Map<String, int> get categoryDomainCounts; String? get etag; String? get globalChecksum;
/// Create a copy of InstalledReleaseMeta
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstalledReleaseMetaCopyWith<InstalledReleaseMeta> get copyWith => _$InstalledReleaseMetaCopyWithImpl<InstalledReleaseMeta>(this as InstalledReleaseMeta, _$identity);

  /// Serializes this InstalledReleaseMeta to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as InstalledReleaseMeta;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstalledReleaseMeta&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.installedAt, _this.installedAt) || other.installedAt == _this.installedAt)&&(identical(other.domainCount, _this.domainCount) || other.domainCount == _this.domainCount)&&const DeepCollectionEquality().equals(other.categoryFiles, _this.categoryFiles)&&const DeepCollectionEquality().equals(other.categoryDomainCounts, _this.categoryDomainCounts)&&(identical(other.etag, _this.etag) || other.etag == _this.etag)&&(identical(other.globalChecksum, _this.globalChecksum) || other.globalChecksum == _this.globalChecksum));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as InstalledReleaseMeta;
  return Object.hash(runtimeType,_this.version,_this.installedAt,_this.domainCount,const DeepCollectionEquality().hash(_this.categoryFiles),const DeepCollectionEquality().hash(_this.categoryDomainCounts),_this.etag,_this.globalChecksum);
}

@override
String toString() {
  final _this = this as InstalledReleaseMeta;
  return 'InstalledReleaseMeta(version: ${_this.version}, installedAt: ${_this.installedAt}, domainCount: ${_this.domainCount}, categoryFiles: ${_this.categoryFiles}, categoryDomainCounts: ${_this.categoryDomainCounts}, etag: ${_this.etag}, globalChecksum: ${_this.globalChecksum})';
}


}

/// @nodoc
abstract mixin class $InstalledReleaseMetaCopyWith<$Res>  {
  factory $InstalledReleaseMetaCopyWith(InstalledReleaseMeta value, $Res Function(InstalledReleaseMeta) _then) = _$InstalledReleaseMetaCopyWithImpl;
@useResult
$Res call({
 String version, DateTime installedAt, int domainCount, Map<String, String> categoryFiles, Map<String, int> categoryDomainCounts, String? etag, String? globalChecksum
});




}
/// @nodoc
class _$InstalledReleaseMetaCopyWithImpl<$Res>
    implements $InstalledReleaseMetaCopyWith<$Res> {
  _$InstalledReleaseMetaCopyWithImpl(this._self, this._then);

  final InstalledReleaseMeta _self;
  final $Res Function(InstalledReleaseMeta) _then;

/// Create a copy of InstalledReleaseMeta
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? installedAt = null,Object? domainCount = null,Object? categoryFiles = null,Object? categoryDomainCounts = null,Object? etag = freezed,Object? globalChecksum = freezed,}) {
  return _then(InstalledReleaseMeta(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,installedAt: null == installedAt ? _self.installedAt : installedAt // ignore: cast_nullable_to_non_nullable
as DateTime,domainCount: null == domainCount ? _self.domainCount : domainCount // ignore: cast_nullable_to_non_nullable
as int,categoryFiles: null == categoryFiles ? _self.categoryFiles : categoryFiles // ignore: cast_nullable_to_non_nullable
as Map<String, String>,categoryDomainCounts: null == categoryDomainCounts ? _self.categoryDomainCounts : categoryDomainCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,etag: freezed == etag ? _self.etag : etag // ignore: cast_nullable_to_non_nullable
as String?,globalChecksum: freezed == globalChecksum ? _self.globalChecksum : globalChecksum // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InstalledReleaseMeta].
extension InstalledReleaseMetaPatterns on InstalledReleaseMeta {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InstalledReleaseMeta value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InstalledReleaseMeta() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InstalledReleaseMeta value)  $default,){
final _that = this;
switch (_that) {
case _InstalledReleaseMeta():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InstalledReleaseMeta value)?  $default,){
final _that = this;
switch (_that) {
case _InstalledReleaseMeta() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  DateTime installedAt,  int domainCount,  Map<String, String> categoryFiles,  Map<String, int> categoryDomainCounts,  String? etag,  String? globalChecksum)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InstalledReleaseMeta() when $default != null:
return $default(_that.version,_that.installedAt,_that.domainCount,_that.categoryFiles,_that.categoryDomainCounts,_that.etag,_that.globalChecksum);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  DateTime installedAt,  int domainCount,  Map<String, String> categoryFiles,  Map<String, int> categoryDomainCounts,  String? etag,  String? globalChecksum)  $default,) {final _that = this;
switch (_that) {
case _InstalledReleaseMeta():
return $default(_that.version,_that.installedAt,_that.domainCount,_that.categoryFiles,_that.categoryDomainCounts,_that.etag,_that.globalChecksum);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  DateTime installedAt,  int domainCount,  Map<String, String> categoryFiles,  Map<String, int> categoryDomainCounts,  String? etag,  String? globalChecksum)?  $default,) {final _that = this;
switch (_that) {
case _InstalledReleaseMeta() when $default != null:
return $default(_that.version,_that.installedAt,_that.domainCount,_that.categoryFiles,_that.categoryDomainCounts,_that.etag,_that.globalChecksum);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InstalledReleaseMeta implements InstalledReleaseMeta {
  const _InstalledReleaseMeta({required this.version, required this.installedAt, this.domainCount = 0,  Map<String, String> categoryFiles = const {},  Map<String, int> categoryDomainCounts = const {}, this.etag, this.globalChecksum}): _categoryFiles = categoryFiles,_categoryDomainCounts = categoryDomainCounts;
  factory _InstalledReleaseMeta.fromJson(Map<String, dynamic> json) => _$InstalledReleaseMetaFromJson(json);

@override final  String version;
@override final  DateTime installedAt;
@override@JsonKey() final  int domainCount;
 final  Map<String, String> _categoryFiles;
@override@JsonKey() Map<String, String> get categoryFiles {
  if (_categoryFiles is EqualUnmodifiableMapView) return _categoryFiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_categoryFiles);
}

 final  Map<String, int> _categoryDomainCounts;
@override@JsonKey() Map<String, int> get categoryDomainCounts {
  if (_categoryDomainCounts is EqualUnmodifiableMapView) return _categoryDomainCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_categoryDomainCounts);
}

@override final  String? etag;
@override final  String? globalChecksum;

/// Create a copy of InstalledReleaseMeta
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InstalledReleaseMetaCopyWith<_InstalledReleaseMeta> get copyWith => __$InstalledReleaseMetaCopyWithImpl<_InstalledReleaseMeta>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InstalledReleaseMetaToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InstalledReleaseMeta&&(identical(other.version, version) || other.version == version)&&(identical(other.installedAt, installedAt) || other.installedAt == installedAt)&&(identical(other.domainCount, domainCount) || other.domainCount == domainCount)&&const DeepCollectionEquality().equals(other.categoryFiles, _categoryFiles)&&const DeepCollectionEquality().equals(other.categoryDomainCounts, _categoryDomainCounts)&&(identical(other.etag, etag) || other.etag == etag)&&(identical(other.globalChecksum, globalChecksum) || other.globalChecksum == globalChecksum));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,version,installedAt,domainCount,const DeepCollectionEquality().hash(_categoryFiles),const DeepCollectionEquality().hash(_categoryDomainCounts),etag,globalChecksum);
}

@override
String toString() {
    return 'InstalledReleaseMeta(version: $version, installedAt: $installedAt, domainCount: $domainCount, categoryFiles: $categoryFiles, categoryDomainCounts: $categoryDomainCounts, etag: $etag, globalChecksum: $globalChecksum)';
}


}

/// @nodoc
abstract mixin class _$InstalledReleaseMetaCopyWith<$Res> implements $InstalledReleaseMetaCopyWith<$Res> {
  factory _$InstalledReleaseMetaCopyWith(_InstalledReleaseMeta value, $Res Function(_InstalledReleaseMeta) _then) = __$InstalledReleaseMetaCopyWithImpl;
@override @useResult
$Res call({
 String version, DateTime installedAt, int domainCount, Map<String, String> categoryFiles, Map<String, int> categoryDomainCounts, String? etag, String? globalChecksum
});




}
/// @nodoc
class __$InstalledReleaseMetaCopyWithImpl<$Res>
    implements _$InstalledReleaseMetaCopyWith<$Res> {
  __$InstalledReleaseMetaCopyWithImpl(this._self, this._then);

  final _InstalledReleaseMeta _self;
  final $Res Function(_InstalledReleaseMeta) _then;

/// Create a copy of InstalledReleaseMeta
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? installedAt = null,Object? domainCount = null,Object? categoryFiles = null,Object? categoryDomainCounts = null,Object? etag = freezed,Object? globalChecksum = freezed,}) {
  return _then(_InstalledReleaseMeta(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,installedAt: null == installedAt ? _self.installedAt : installedAt // ignore: cast_nullable_to_non_nullable
as DateTime,domainCount: null == domainCount ? _self.domainCount : domainCount // ignore: cast_nullable_to_non_nullable
as int,categoryFiles: null == categoryFiles ? _self._categoryFiles : categoryFiles // ignore: cast_nullable_to_non_nullable
as Map<String, String>,categoryDomainCounts: null == categoryDomainCounts ? _self._categoryDomainCounts : categoryDomainCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,etag: freezed == etag ? _self.etag : etag // ignore: cast_nullable_to_non_nullable
as String?,globalChecksum: freezed == globalChecksum ? _self.globalChecksum : globalChecksum // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
