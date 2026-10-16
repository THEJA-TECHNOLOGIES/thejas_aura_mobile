import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

abstract class IBlocklistRepository {
  Future<Set<String>> getDefaultDomainOverrides();
  Future<Set<String>> toggleDefaultDomain({
    required String domain,
    required bool isEnabled,
  });
  Future<List<AuraRuleItem>?> getRules();
  Future<AuraRuleItem> addRule({
    required String domain,
    required bool isBlocked,
    bool isEnabled = true,
  });
  Future<AuraRuleItem> updateRule({
    required String id,
    String? domain,
    bool? isBlocked,
    bool? isEnabled,
  });
  Future<AuraRuleItem> deleteRule(String id);
  Future<AuraRuleItem> toggleRule(String id, bool isEnabled);
  Future<String> validateDomain(String domain);
  Future<Map<String, bool>> getCategories();
  Future<List<AuraDefaultCategory>> getDefaultCategories();
  Future<List<String>> getCategoryDomains(String category);
}
