import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/widgets/category_domain_sheet.dart';

class DefaultDomainTab extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return BlocBuilder<BlocklistBloc, BlocklistState>(
      builder: (context, state) {
        if (state.isLoadingOverrides) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.overridesError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.overridesError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.read<BlocklistBloc>().add(
                      const BlocklistEvent.defaultDomainOverridesRefreshRequested(),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final categories = AuraDefaultCategoryData.categories;

        return RefreshIndicator(
          onRefresh: () async => context.read<BlocklistBloc>().add(
            const BlocklistEvent.defaultDomainOverridesRefreshRequested(),
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...categories.map((category) {
                return GestureDetector(
                  onTap: () => CategoryDomainSheet.show(
                    context: context,
                    category: category,
                    disabledDomains: state.disabledDefaultDomains,
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.segmentBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border, width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            category.icon,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.name,
                                style: typo.titleMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                category.description,
                                style: typo.bodySmall.copyWith(
                                  color: colors.textSecondary,
                                ),
                                overflow: .ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category.domainCount.toString(),
                          style: typo.titleSmall.copyWith(
                            fontWeight: .w600,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right, color: colors.textPrimary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
