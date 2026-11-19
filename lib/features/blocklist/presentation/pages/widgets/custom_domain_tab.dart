import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
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
                  AppButton(
                    text: 'Retry',
                    color: colors.primary,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => context.read<BlocklistBloc>().add(
                      const BlocklistEvent.customRulesRefreshRequested(),
                    ),
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
              return _CustomRuleCard(key: ValueKey(rule.id), rule: rule);
            },
          ),
        );
      },
    );
  }
}

class _CustomRuleCard extends StatefulWidget {
  final AuraRuleItem rule;

  const _CustomRuleCard({super.key, required this.rule});

  @override
  State<_CustomRuleCard> createState() => _CustomRuleCardState();
}

class _CustomRuleCardState extends State<_CustomRuleCard> {
  bool _isCardFocused = false;
  bool _isDeleteFocused = false;

  void _handleToggle() {
    context.read<BlocklistBloc>().add(
      BlocklistEvent.customRuleToggled(widget.rule),
    );
  }

  void _handleDelete() {
    handleDeleteRule(widget.rule, context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final isTv = PlatformChecker.isAndroidTV;
    final rule = widget.rule;
    final isEnabled = rule.isEnabled;

    return Container(
      decoration: BoxDecoration(
        color: isTv && _isCardFocused ? colors.surfaceRaised : colors.segmentBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: InkWell(
                focusColor: Colors.transparent,

                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
                onFocusChange: (focused) {
                  setState(() => _isCardFocused = focused);
                  if (focused && isTv) {
                    Scrollable.ensureVisible(
                      context,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                    );
                  }
                },
                onTap: _handleToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(width: 8),
                      ExcludeFocus(
                        excluding: isTv,
                        child: IgnorePointer(
                          ignoring: isTv,
                          child: Switch(
                            inactiveThumbColor: colors.textTertiary,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            inactiveTrackColor: colors.trackOff,
                            value: isEnabled,
                            onChanged: (val) => _handleToggle(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: (isTv && _isDeleteFocused)
                  ? colors.error.withValues(alpha: 0.2)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: (isTv && _isDeleteFocused)
                      ? colors.error
                      : Colors.transparent,
                  width: isTv ? 1 : 0,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onFocusChange: (focused) {
                  setState(() => _isDeleteFocused = focused);
                  if (focused && isTv) {
                    Scrollable.ensureVisible(
                      context,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                    );
                  }
                },
                onTap: _handleDelete,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    CupertinoIcons.delete,
                    color: (isTv && _isDeleteFocused)
                        ? colors.error
                        : colors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
