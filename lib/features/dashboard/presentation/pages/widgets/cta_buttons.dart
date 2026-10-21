import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/sized_context.dart';
import 'package:theja_aura/features/activity/presentation/pages/activity_page.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/blocklist_page.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

class CTAButtons extends StatelessWidget {
  const new({super.key, this.useRow = false});
  final bool useRow;

  @override
  Widget build(BuildContext context) {
    void openLiveActivity() async {
      ActivityPage.show(context: context);
      if (context.mounted) {
        context.read<DashboardBloc>().add(
          const DashboardEvent.statsRefreshRequested(),
        );
      }
    }

    void openBlocklist() async {
      // await context.push('/blocklist');
      BlocklistPage.show(context: context);
      if (context.mounted) {
        context.read<DashboardBloc>().add(
          const DashboardEvent.statsRefreshRequested(),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (!context.isMobile) ...[
            Expanded(
              child: CtaButtons(
                label: 'Logs',
                subtitle: 'Blocked events',
                icon: Icons.notes,
                useRow: useRow,
                color: Colors.blueAccent,
                onTap: () {
                  ActivityPage.show(context: context, isLogsMode: true);
                  if (context.mounted) {
                    context.read<DashboardBloc>().add(
                      const DashboardEvent.statsRefreshRequested(),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: CtaButtons(
              label: 'Live Activity',
              subtitle: 'All requests',
              icon: Icons.insights,
              color: Color(0XFF0B7F65),
              useRow: useRow,
              onTap: openLiveActivity,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CtaButtons(
              label: 'Blocklist',
              subtitle: 'Domains & rules',
              icon: Icons.rule,
              color: Colors.deepPurpleAccent,
              onTap: openBlocklist,
              useRow: useRow,
            ),
          ),
        ],
      ),
    );
  }
}

class CtaButtons extends StatefulWidget {
  const new({
    super.key,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    this.useRow = false,
  });
  final bool useRow;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<CtaButtons> createState() => _CtaButtonsState();
}

class _CtaButtonsState extends State<CtaButtons> {
  bool _isFocused = false;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onTap,
      focusColor: Colors.transparent,
      onFocusChange: (bool hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
      },

      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _isFocused
                ? context.isDark
                      ? Colors.white
                      : Colors.black
                : colors.border,
            width: _isFocused ? 2 : 1,
          ),
        ),
        child: widget.useRow
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 22),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: typo.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          widget.subtitle,
                          style: typo.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 18),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 22),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.label,
                    style: typo.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: typo.bodySmall.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );
  }
}
