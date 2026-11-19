import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/app_utils.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
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
        if (state.isLoadingOverrides || state.isLoadingCategories) {
          return const Center(child: CircularProgressIndicator());
        }

        final error = state.overridesError ?? state.categoriesError;
        if (error != null) {
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
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    text: 'Retry',
                    color: colors.primary,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => context.read<BlocklistBloc>().add(
                      const BlocklistEvent.started(),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final categories = state.defaultCategories;

        if (categories.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => context.read<BlocklistBloc>().add(
              const BlocklistEvent.started(),
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 56,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Categories Installed',
                          style: typo.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Published blocklist categories and domains will appear here once synchronized with the backend.',
                          textAlign: TextAlign.center,
                          style: typo.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        AppButton(
                          text: 'Check for Updates',
                          color: colors.primary,
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: () => context.read<BlocklistBloc>().add(
                            const BlocklistEvent.started(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async =>
              context.read<BlocklistBloc>().add(const BlocklistEvent.started()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...categories.map((category) {
                return _CategoryCard(
                  key: ValueKey(category.name),
                  category: category,
                  disabledDomains: state.disabledDefaultDomains,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final AuraDefaultCategory category;
  final Set<String> disabledDomains;

  const _CategoryCard({
    super.key,
    required this.category,
    required this.disabledDomains,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _isFocused = false;
  bool _isOpening = false;

  Future<void> _openSheet() async {
    if (_isOpening) return;
    _isOpening = true;
    try {
      await CategoryDomainSheet.show(
        context: context,
        category: widget.category,
        disabledDomains: widget.disabledDomains,
      );
    } finally {
      if (mounted) {
        _isOpening = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final isTv = PlatformChecker.isAndroidTV;

    return Container(
      margin: EdgeInsets.only(
        bottom: 12,
        left: isTv && _isFocused ? 4 : 0,
        right: isTv && _isFocused ? 4 : 0,
      ),
      decoration: BoxDecoration(
        color: isTv && _isFocused ? colors.surfaceRaised : colors.segmentBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          focusColor: Colors.transparent,
          onFocusChange: (hasNav) {
            setState(() => _isFocused = hasNav);
            if (hasNav && isTv) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
            }
          },
          onTap: _openSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.category.icon,
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
                        widget.category.name,
                        style: typo.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.category.description,
                        style: typo.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatNumber(widget.category.domainCount),
                  style: typo.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, color: colors.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
