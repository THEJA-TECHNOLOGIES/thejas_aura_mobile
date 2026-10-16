import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../../domain/repositories/i_blocklist_repository.dart';

@LazySingleton(as: IBlocklistRepository)
class BlocklistRepository implements IBlocklistRepository {
  final AuraTunnelService _tunnelService;

  BlocklistRepository(this._tunnelService);

  @override
  Future<Set<String>> getDefaultDomainOverrides() {
    return _tunnelService.getDefaultDomainOverrides();
  }

  @override
  Future<Set<String>> toggleDefaultDomain({
    required String domain,
    required bool isEnabled,
  }) {
    return _tunnelService.toggleDefaultDomain(
      domain: domain,
      isEnabled: isEnabled,
    );
  }

  @override
  Future<List<AuraRuleItem>?> getRules() {
    return _tunnelService.getRules();
  }

  @override
  Future<AuraRuleItem> addRule({
    required String domain,
    required bool isBlocked,
    bool isEnabled = true,
  }) {
    return _tunnelService.addRule(
      domain: domain,
      isBlocked: isBlocked,
      isEnabled: isEnabled,
    );
  }

  @override
  Future<AuraRuleItem> updateRule({
    required String id,
    String? domain,
    bool? isBlocked,
    bool? isEnabled,
  }) {
    return _tunnelService.updateRule(
      id: id,
      domain: domain,
      isBlocked: isBlocked,
      isEnabled: isEnabled,
    );
  }

  @override
  Future<AuraRuleItem> deleteRule(String id) {
    return _tunnelService.deleteRule(id);
  }

  @override
  Future<AuraRuleItem> toggleRule(String id, bool isEnabled) {
    return _tunnelService.toggleRule(id, isEnabled);
  }

  @override
  Future<String> validateDomain(String domain) {
    return _tunnelService.validateDomain(domain);
  }

  @override
  Future<Map<String, bool>> getCategories() {
    return _tunnelService.getCategories();
  }

  @override
  Future<List<AuraDefaultCategory>> getDefaultCategories() async {
    final rawCats = await _tunnelService.getReleaseCategories();
    if (rawCats == null || rawCats.isEmpty) {
      return const [];
    }
    return rawCats.map((item) {
      final name = item['name'] as String? ?? '';
      final count = (item['domainCount'] as num?)?.toInt() ?? 0;
      return AuraDefaultCategory(
        name: name,
        description: AuraCategoryMetadata.descriptionForCategory(name),
        icon: AuraCategoryMetadata.iconForCategory(name),
        domainCount: count,
      );
    }).toList();
  }

  @override
  Future<List<String>> getCategoryDomains(String category) async {
    final domains = await _tunnelService.getCategoryDomains(category);
    return domains ?? const [];
  }
}
