// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'blocklist_manifest.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BlocklistCategoryMeta {

 String get name; String? get description; int get domainCount; Map<String, String> get files; String? get domainsUrl; String? get hostsUrl; String? get checksum;
/// Create a copy of BlocklistCategoryMeta
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlocklistCategoryMetaCopyWith<BlocklistCategoryMeta> get copyWith => _$BlocklistCategoryMetaCopyWithImpl<BlocklistCategoryMeta>(this as BlocklistCategoryMeta, _$identity);

  /// Serializes this BlocklistCategoryMeta to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BlocklistCategoryMeta;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlocklistCategoryMeta&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.domainCount, _this.domainCount) || other.domainCount == _this.domainCount)&&const DeepCollectionEquality().equals(other.files, _this.files)&&(identical(other.domainsUrl, _this.domainsUrl) || other.domainsUrl == _this.domainsUrl)&&(identical(other.hostsUrl, _this.hostsUrl) || other.hostsUrl == _this.hostsUrl)&&(identical(other.checksum, _this.checksum) || other.checksum == _this.checksum));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BlocklistCategoryMeta;
  return Object.hash(runtimeType,_this.name,_this.description,_this.domainCount,const DeepCollectionEquality().hash(_this.files),_this.domainsUrl,_this.hostsUrl,_this.checksum);
}

@override
String toString() {
  final _this = this as BlocklistCategoryMeta;
  return 'BlocklistCategoryMeta(name: ${_this.name}, description: ${_this.description}, domainCount: ${_this.domainCount}, files: ${_this.files}, domainsUrl: ${_this.domainsUrl}, hostsUrl: ${_this.hostsUrl}, checksum: ${_this.checksum})';
}


}

/// @nodoc
abstract mixin class $BlocklistCategoryMetaCopyWith<$Res>  {
  factory $BlocklistCategoryMetaCopyWith(BlocklistCategoryMeta value, $Res Function(BlocklistCategoryMeta) _then) = _$BlocklistCategoryMetaCopyWithImpl;
@useResult
$Res call({
 String name, String? description, int domainCount, Map<String, String> files, String? domainsUrl, String? hostsUrl, String? checksum
});




}
/// @nodoc
class _$BlocklistCategoryMetaCopyWithImpl<$Res>
    implements $BlocklistCategoryMetaCopyWith<$Res> {
  _$BlocklistCategoryMetaCopyWithImpl(this._self, this._then);

  final BlocklistCategoryMeta _self;
  final $Res Function(BlocklistCategoryMeta) _then;

/// Create a copy of BlocklistCategoryMeta
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? description = freezed,Object? domainCount = null,Object? files = null,Object? domainsUrl = freezed,Object? hostsUrl = freezed,Object? checksum = freezed,}) {
  return _then(BlocklistCategoryMeta(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,domainCount: null == domainCount ? _self.domainCount : domainCount // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as Map<String, String>,domainsUrl: freezed == domainsUrl ? _self.domainsUrl : domainsUrl // ignore: cast_nullable_to_non_nullable
as String?,hostsUrl: freezed == hostsUrl ? _self.hostsUrl : hostsUrl // ignore: cast_nullable_to_non_nullable
as String?,checksum: freezed == checksum ? _self.checksum : checksum // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BlocklistCategoryMeta].
extension BlocklistCategoryMetaPatterns on BlocklistCategoryMeta {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlocklistCategoryMeta value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlocklistCategoryMeta() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlocklistCategoryMeta value)  $default,){
final _that = this;
switch (_that) {
case _BlocklistCategoryMeta():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlocklistCategoryMeta value)?  $default,){
final _that = this;
switch (_that) {
case _BlocklistCategoryMeta() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? description,  int domainCount,  Map<String, String> files,  String? domainsUrl,  String? hostsUrl,  String? checksum)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlocklistCategoryMeta() when $default != null:
return $default(_that.name,_that.description,_that.domainCount,_that.files,_that.domainsUrl,_that.hostsUrl,_that.checksum);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? description,  int domainCount,  Map<String, String> files,  String? domainsUrl,  String? hostsUrl,  String? checksum)  $default,) {final _that = this;
switch (_that) {
case _BlocklistCategoryMeta():
return $default(_that.name,_that.description,_that.domainCount,_that.files,_that.domainsUrl,_that.hostsUrl,_that.checksum);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? description,  int domainCount,  Map<String, String> files,  String? domainsUrl,  String? hostsUrl,  String? checksum)?  $default,) {final _that = this;
switch (_that) {
case _BlocklistCategoryMeta() when $default != null:
return $default(_that.name,_that.description,_that.domainCount,_that.files,_that.domainsUrl,_that.hostsUrl,_that.checksum);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlocklistCategoryMeta extends BlocklistCategoryMeta {
  const _BlocklistCategoryMeta({this.name = '', this.description, this.domainCount = 0,  Map<String, String> files = const {}, this.domainsUrl, this.hostsUrl, this.checksum}): _files = files,super._();
  factory _BlocklistCategoryMeta.fromJson(Map<String, dynamic> json) => _$BlocklistCategoryMetaFromJson(json);

@override@JsonKey() final  String name;
@override final  String? description;
@override@JsonKey() final  int domainCount;
 final  Map<String, String> _files;
@override@JsonKey() Map<String, String> get files {
  if (_files is EqualUnmodifiableMapView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_files);
}

@override final  String? domainsUrl;
@override final  String? hostsUrl;
@override final  String? checksum;

/// Create a copy of BlocklistCategoryMeta
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlocklistCategoryMetaCopyWith<_BlocklistCategoryMeta> get copyWith => __$BlocklistCategoryMetaCopyWithImpl<_BlocklistCategoryMeta>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlocklistCategoryMetaToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlocklistCategoryMeta&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.domainCount, domainCount) || other.domainCount == domainCount)&&const DeepCollectionEquality().equals(other.files, _files)&&(identical(other.domainsUrl, domainsUrl) || other.domainsUrl == domainsUrl)&&(identical(other.hostsUrl, hostsUrl) || other.hostsUrl == hostsUrl)&&(identical(other.checksum, checksum) || other.checksum == checksum));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,description,domainCount,const DeepCollectionEquality().hash(_files),domainsUrl,hostsUrl,checksum);
}

@override
String toString() {
    return 'BlocklistCategoryMeta(name: $name, description: $description, domainCount: $domainCount, files: $files, domainsUrl: $domainsUrl, hostsUrl: $hostsUrl, checksum: $checksum)';
}


}

/// @nodoc
abstract mixin class _$BlocklistCategoryMetaCopyWith<$Res> implements $BlocklistCategoryMetaCopyWith<$Res> {
  factory _$BlocklistCategoryMetaCopyWith(_BlocklistCategoryMeta value, $Res Function(_BlocklistCategoryMeta) _then) = __$BlocklistCategoryMetaCopyWithImpl;
@override @useResult
$Res call({
 String name, String? description, int domainCount, Map<String, String> files, String? domainsUrl, String? hostsUrl, String? checksum
});




}
/// @nodoc
class __$BlocklistCategoryMetaCopyWithImpl<$Res>
    implements _$BlocklistCategoryMetaCopyWith<$Res> {
  __$BlocklistCategoryMetaCopyWithImpl(this._self, this._then);

  final _BlocklistCategoryMeta _self;
  final $Res Function(_BlocklistCategoryMeta) _then;

/// Create a copy of BlocklistCategoryMeta
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? description = freezed,Object? domainCount = null,Object? files = null,Object? domainsUrl = freezed,Object? hostsUrl = freezed,Object? checksum = freezed,}) {
  return _then(_BlocklistCategoryMeta(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,domainCount: null == domainCount ? _self.domainCount : domainCount // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as Map<String, String>,domainsUrl: freezed == domainsUrl ? _self.domainsUrl : domainsUrl // ignore: cast_nullable_to_non_nullable
as String?,hostsUrl: freezed == hostsUrl ? _self.hostsUrl : hostsUrl // ignore: cast_nullable_to_non_nullable
as String?,checksum: freezed == checksum ? _self.checksum : checksum // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$BlocklistManifest {

 String get version; DateTime get updatedAt; int get domainCount; Map<String, String> get files; Map<String, BlocklistCategoryMeta>? get categories; String? get checksum;
/// Create a copy of BlocklistManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlocklistManifestCopyWith<BlocklistManifest> get copyWith => _$BlocklistManifestCopyWithImpl<BlocklistManifest>(this as BlocklistManifest, _$identity);

  /// Serializes this BlocklistManifest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BlocklistManifest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlocklistManifest&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.domainCount, _this.domainCount) || other.domainCount == _this.domainCount)&&const DeepCollectionEquality().equals(other.files, _this.files)&&const DeepCollectionEquality().equals(other.categories, _this.categories)&&(identical(other.checksum, _this.checksum) || other.checksum == _this.checksum));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BlocklistManifest;
  return Object.hash(runtimeType,_this.version,_this.updatedAt,_this.domainCount,const DeepCollectionEquality().hash(_this.files),const DeepCollectionEquality().hash(_this.categories),_this.checksum);
}

@override
String toString() {
  final _this = this as BlocklistManifest;
  return 'BlocklistManifest(version: ${_this.version}, updatedAt: ${_this.updatedAt}, domainCount: ${_this.domainCount}, files: ${_this.files}, categories: ${_this.categories}, checksum: ${_this.checksum})';
}


}

/// @nodoc
abstract mixin class $BlocklistManifestCopyWith<$Res>  {
  factory $BlocklistManifestCopyWith(BlocklistManifest value, $Res Function(BlocklistManifest) _then) = _$BlocklistManifestCopyWithImpl;
@useResult
$Res call({
 String version, DateTime updatedAt, int domainCount, Map<String, String> files, Map<String, BlocklistCategoryMeta>? categories, String? checksum
});




}
/// @nodoc
class _$BlocklistManifestCopyWithImpl<$Res>
    implements $BlocklistManifestCopyWith<$Res> {
  _$BlocklistManifestCopyWithImpl(this._self, this._then);

  final BlocklistManifest _self;
  final $Res Function(BlocklistManifest) _then;

/// Create a copy of BlocklistManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? updatedAt = null,Object? domainCount = null,Object? files = null,Object? categories = freezed,Object? checksum = freezed,}) {
  return _then(BlocklistManifest(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,domainCount: null == domainCount ? _self.domainCount : domainCount // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as Map<String, String>,categories: freezed == categories ? _self.categories : categories // ignore: cast_nullable_to_non_nullable
as Map<String, BlocklistCategoryMeta>?,checksum: freezed == checksum ? _self.checksum : checksum // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BlocklistManifest].
extension BlocklistManifestPatterns on BlocklistManifest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlocklistManifest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlocklistManifest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlocklistManifest value)  $default,){
final _that = this;
switch (_that) {
case _BlocklistManifest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlocklistManifest value)?  $default,){
final _that = this;
switch (_that) {
case _BlocklistManifest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  DateTime updatedAt,  int domainCount,  Map<String, String> files,  Map<String, BlocklistCategoryMeta>? categories,  String? checksum)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlocklistManifest() when $default != null:
return $default(_that.version,_that.updatedAt,_that.domainCount,_that.files,_that.categories,_that.checksum);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  DateTime updatedAt,  int domainCount,  Map<String, String> files,  Map<String, BlocklistCategoryMeta>? categories,  String? checksum)  $default,) {final _that = this;
switch (_that) {
case _BlocklistManifest():
return $default(_that.version,_that.updatedAt,_that.domainCount,_that.files,_that.categories,_that.checksum);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  DateTime updatedAt,  int domainCount,  Map<String, String> files,  Map<String, BlocklistCategoryMeta>? categories,  String? checksum)?  $default,) {final _that = this;
switch (_that) {
case _BlocklistManifest() when $default != null:
return $default(_that.version,_that.updatedAt,_that.domainCount,_that.files,_that.categories,_that.checksum);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BlocklistManifest implements BlocklistManifest {
  const _BlocklistManifest({required this.version, required this.updatedAt, this.domainCount = 0,  Map<String, String> files = const {},  Map<String, BlocklistCategoryMeta>? categories, this.checksum}): _files = files,_categories = categories;
  factory _BlocklistManifest.fromJson(Map<String, dynamic> json) => _$BlocklistManifestFromJson(json);

@override final  String version;
@override final  DateTime updatedAt;
@override@JsonKey() final  int domainCount;
 final  Map<String, String> _files;
@override@JsonKey() Map<String, String> get files {
  if (_files is EqualUnmodifiableMapView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_files);
}

 final  Map<String, BlocklistCategoryMeta>? _categories;
@override Map<String, BlocklistCategoryMeta>? get categories {
  final value = _categories;
  if (value == null) return null;
  if (_categories is EqualUnmodifiableMapView) return _categories;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  String? checksum;

/// Create a copy of BlocklistManifest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlocklistManifestCopyWith<_BlocklistManifest> get copyWith => __$BlocklistManifestCopyWithImpl<_BlocklistManifest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BlocklistManifestToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlocklistManifest&&(identical(other.version, version) || other.version == version)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.domainCount, domainCount) || other.domainCount == domainCount)&&const DeepCollectionEquality().equals(other.files, _files)&&const DeepCollectionEquality().equals(other.categories, _categories)&&(identical(other.checksum, checksum) || other.checksum == checksum));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,version,updatedAt,domainCount,const DeepCollectionEquality().hash(_files),const DeepCollectionEquality().hash(_categories),checksum);
}

@override
String toString() {
    return 'BlocklistManifest(version: $version, updatedAt: $updatedAt, domainCount: $domainCount, files: $files, categories: $categories, checksum: $checksum)';
}


}

/// @nodoc
abstract mixin class _$BlocklistManifestCopyWith<$Res> implements $BlocklistManifestCopyWith<$Res> {
  factory _$BlocklistManifestCopyWith(_BlocklistManifest value, $Res Function(_BlocklistManifest) _then) = __$BlocklistManifestCopyWithImpl;
@override @useResult
$Res call({
 String version, DateTime updatedAt, int domainCount, Map<String, String> files, Map<String, BlocklistCategoryMeta>? categories, String? checksum
});




}
/// @nodoc
class __$BlocklistManifestCopyWithImpl<$Res>
    implements _$BlocklistManifestCopyWith<$Res> {
  __$BlocklistManifestCopyWithImpl(this._self, this._then);

  final _BlocklistManifest _self;
  final $Res Function(_BlocklistManifest) _then;

/// Create a copy of BlocklistManifest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? updatedAt = null,Object? domainCount = null,Object? files = null,Object? categories = freezed,Object? checksum = freezed,}) {
  return _then(_BlocklistManifest(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,domainCount: null == domainCount ? _self.domainCount : domainCount // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as Map<String, String>,categories: freezed == categories ? _self._categories : categories // ignore: cast_nullable_to_non_nullable
as Map<String, BlocklistCategoryMeta>?,checksum: freezed == checksum ? _self.checksum : checksum // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
