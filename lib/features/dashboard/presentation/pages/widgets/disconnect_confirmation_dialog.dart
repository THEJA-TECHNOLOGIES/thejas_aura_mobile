import 'package:flutter/material.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';

/// Presents the disconnect confirmation modal with pause and shutdown policy options.
/// Returns:
/// - A [Duration] if a temporary pause duration was selected (30m, 2h, 3h).
/// - `'shutdown'` if "Turn Off Until I Turn It On" was selected.
/// - `null` if cancelled or dismissed.
Future<dynamic> showDisconnectConfirmationDialog(
  BuildContext context, {
  bool isAlwaysOnActive = false,
  bool isLockdownActive = false,
  VoidCallback? onOpenVpnSettings,
}) {
  return showDialog<dynamic>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return DisconnectConfirmationDialog(
        isAlwaysOnActive: isAlwaysOnActive,
        isLockdownActive: isLockdownActive,
        onOpenVpnSettings: onOpenVpnSettings,
      );
    },
  );
}

class DisconnectConfirmationDialog extends StatelessWidget {
  final bool isAlwaysOnActive;
  final bool isLockdownActive;
  final VoidCallback? onOpenVpnSettings;

  const DisconnectConfirmationDialog({
    super.key,
    this.isAlwaysOnActive = false,
    this.isLockdownActive = false,
    this.onOpenVpnSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final isTv = PlatformChecker.isAndroidTV;

    return Dialog(
      backgroundColor: colors.background,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isTv ? 120 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        color: colors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pause or Turn Off',
                            style: typo.titleLarge.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Choose how long to suspend firewall protection:',
                            style: typo.bodySmall.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Always-On VPN limitation banner (Android)
                if (isAlwaysOnActive || isLockdownActive) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: colors.warning,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isLockdownActive
                                  ? 'System VPN Lockdown Active'
                                  : 'Always-on VPN Active',
                              style: typo.labelLarge.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.warning,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isLockdownActive
                              ? 'Android "Block connections without VPN" is active. Pausing will block all device internet traffic until disabled in System Settings.'
                              : 'Android Always-on VPN is enabled in system settings. Android may automatically restart the VPN until disabled in System Settings.',
                          style: typo.bodySmall.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        if (onOpenVpnSettings != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onOpenVpnSettings?.call();
                              },
                              icon: const Icon(Icons.settings, size: 16),
                              label: const Text('Open System VPN Settings'),
                              style: TextButton.styleFrom(
                                foregroundColor: colors.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 1. Pause for 30 minutes
                _PolicyOptionTile(
                  autofocus: true,
                  title: 'Pause for 30 minutes',
                  subtitle: 'Automatically resumes filtering in 30 minutes',
                  icon: Icons.timer_outlined,
                  onTap: () => Navigator.of(context).pop(const Duration(minutes: 30)),
                ),
                const SizedBox(height: 10),

                // 2. Pause for 2 hours
                _PolicyOptionTile(
                  title: 'Pause for 2 hours',
                  subtitle: 'Automatically resumes filtering in 2 hours',
                  icon: Icons.hourglass_top_outlined,
                  onTap: () => Navigator.of(context).pop(const Duration(hours: 2)),
                ),
                const SizedBox(height: 10),

                // 3. Pause for 3 hours
                _PolicyOptionTile(
                  title: 'Pause for 3 hours',
                  subtitle: 'Automatically resumes filtering in 3 hours',
                  icon: Icons.hourglass_bottom_outlined,
                  onTap: () => Navigator.of(context).pop(const Duration(hours: 3)),
                ),
                const SizedBox(height: 10),

                // 4. Turn Off Until I Turn It On
                _PolicyOptionTile(
                  title: 'Turn Off Until I Turn It On',
                  subtitle: 'Stays off across reboots until you explicitly enable it',
                  icon: Icons.power_settings_new_outlined,
                  isDestructive: true,
                  onTap: () => Navigator.of(context).pop('shutdown'),
                ),
                const SizedBox(height: 16),

                // 5. Cancel
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Cancel',
                    style: typo.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicyOptionTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isDestructive;

  const _PolicyOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
    this.isDestructive = false,
  });

  @override
  State<_PolicyOptionTile> createState() => _PolicyOptionTileState();
}

class _PolicyOptionTileState extends State<_PolicyOptionTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;

    final accentColor = widget.isDestructive ? colors.error : colors.primary;

    return Material(
      color: _isFocused
          ? colors.surfaceRaised
          : colors.segmentBg,
      borderRadius: BorderRadius.circular(12),
      elevation: _isFocused ? 2 : 0,
      child: InkWell(
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? colors.primary
                  : colors.border,
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.icon,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: typo.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: widget.isDestructive ? colors.error : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: typo.labelSmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
