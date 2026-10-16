import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/blocklist_util.dart';

class CustomDomainTab extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return BlocBuilder<BlocklistBloc, BlocklistState>(
      builder: (context, state) {
        if (state.isLoadingRules) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.rulesError != null) {
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
                    state.rulesError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.read<BlocklistBloc>().add(
                      const BlocklistEvent.customRulesRefreshRequested(),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (state.customRules.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rule, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No Custom Domains',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add custom allow or block rules to fine-tune your firewall decisions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () =>
                        handleAddRule(isBlockedDefault: true, context: context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Rule'),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => context.read<BlocklistBloc>().add(
            const BlocklistEvent.customRulesRefreshRequested(),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: state.customRules.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rule = state.customRules[index];
              // ignore: unused_local_variable
              final isBlocked = rule.isBlocked;
              final isEnabled = rule.isEnabled;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.segmentBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            rule.domain,
                            style: typo.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '• ${!isEnabled ? "Allowed" : "Blocked"}',
                            style: typo.bodySmall.copyWith(
                              color: isEnabled
                                  ? colors.primary
                                  : colors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      inactiveThumbColor: colors.textTertiary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      inactiveTrackColor: colors.trackOff,
                      value: isEnabled,
                      onChanged: (val) => context.read<BlocklistBloc>().add(
                        BlocklistEvent.customRuleToggled(rule),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => handleDeleteRule(rule, context),
                      child: Icon(
                        CupertinoIcons.delete,
                        color: colors.textSecondary,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
