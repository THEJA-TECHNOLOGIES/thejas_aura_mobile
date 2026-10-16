import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

part 'blocklist_state.freezed.dart';

@freezed
abstract class BlocklistState with _$BlocklistState {
  const factory BlocklistState({
    @Default([]) List<AuraDefaultCategory> defaultCategories,
    @Default(true) bool isLoadingCategories,
    String? categoriesError,
    @Default({}) Set<String> disabledDefaultDomains,
    @Default(true) bool isLoadingOverrides,
    String? overridesError,
    @Default([]) List<AuraRuleItem> customRules,
    @Default(true) bool isLoadingRules,
    String? rulesError,
    String? actionError,
  }) = _BlocklistState;
}
