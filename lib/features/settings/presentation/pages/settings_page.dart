import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:theja_aura/core/theme/app_colors.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/theme/app_typography.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/app_toast.dart';
import 'package:theja_aura/features/activity/presentation/bloc/activity_bloc.dart';
import 'package:theja_aura/features/activity/presentation/pages/activity_page.dart';
import 'package:theja_aura/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static Future<void> show({required BuildContext context}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const SettingsPage(),
    );
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PackageInfo? packageInfo;

  @override
  void initState() {
    _loadPackageInfo();
    super.initState();
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _loadPackageInfo() async {
    final data = await PackageInfo.fromPlatform();
    setState(() {
      packageInfo = data;
    });
  }

  static const _logsHistoryOptions = [
    (outcome: '7', label: '7 days', key: ValueKey('7_days')),
    (outcome: '30', label: '30 days', key: ValueKey('30_days')),
  ];

  Future<bool?> _showClearHistoryConfirmationDialog(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          constraints: const BoxConstraints(maxWidth: 500),
          backgroundColor: colors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.border, width: 1),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Clear activity history?",
                  style: typo.titleLarge.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  "This will permanently delete all activity and DNS query logs stored on this device. This action cannot be undone.",
                  style: typo.labelLarge.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 12,
                  children: [
                    Expanded(
                      child: AppButton(
                        text: "Cancel",
                        color: colors.gray2,
                        onPressed: () => ctx.pop(false),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                    Expanded(
                      child: AppButton(
                        text: "Clear",
                        color: colors.error,
                        onPressed: () => ctx.pop(true),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: .all(16),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Center(
                  child: Container(
                    height: 8,
                    width: 60,
                    decoration: BoxDecoration(
                      color: colors.segmentBg,
                      borderRadius: .circular(18),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            "Settings",
                            style: typo.headlineMedium.copyWith(
                              fontWeight: .bold,
                            ),
                          ),
                          Text(
                            "Make the app work your way.",
                            style: typo.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        context.pop();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: BlocConsumer<SettingsBloc, SettingsState>(
                    listenWhen: (previous, current) =>
                        previous.errorMessage != current.errorMessage ||
                        (previous.isPruning &&
                            !current.isPruning &&
                            current.errorMessage == null),
                    listener: (context, state) {
                      if (state.errorMessage != null) {
                        showErrorToast(message: state.errorMessage!);
                        context.read<SettingsBloc>().add(
                          const SettingsEvent.errorMessageDismissed(),
                        );
                      } else if (!state.isPruning) {
                        showSuccessToast(
                          message: "Activity history cleared successfully.",
                        );
                      }
                    },
                    builder: (context, state) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            _title(typo, colors, "PROTECTION"),
                            const SizedBox(height: 4),
                            Container(
                              padding: .all(12),
                              decoration: BoxDecoration(
                                color: colors.segmentBg,
                                borderRadius: .circular(14),
                                border: Border.all(color: colors.border),
                              ),
                              child: Row(
                                spacing: 6,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      children: [
                                        Text(
                                          "Auto-restart",
                                          style: typo.titleMedium.copyWith(
                                            fontWeight: .bold,
                                          ),
                                        ),
                                        Text(
                                          "Turn protection back on after your device restarts or the app is closed.",
                                          style: typo.labelSmall.copyWith(
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    inactiveThumbColor: colors.textTertiary,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    inactiveTrackColor: colors.trackOff,
                                    value: state.autoRestartEnabled,
                                    onChanged: (value) {
                                      context.read<SettingsBloc>().add(
                                        SettingsEvent.autoRestartToggled(value),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _title(typo, colors, "ACTIVITY AND PRIVACY"),
                            const SizedBox(height: 4),
                            Container(
                              decoration: BoxDecoration(
                                color: colors.segmentBg,
                                borderRadius: .circular(14),
                                border: Border.all(color: colors.border),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      spacing: 6,
                                      children: [
                                        Text(
                                          "Keep logs history for",
                                          style: typo.titleMedium.copyWith(
                                            fontWeight: .bold,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: colors.segmentBg,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: colors.border,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            spacing: 6,
                                            children: [
                                              for (
                                                var i = 0;
                                                i < _logsHistoryOptions.length;
                                                i++
                                              )
                                                FilterWidget(
                                                  key: _logsHistoryOptions[i]
                                                      .key,
                                                  onTap: () {
                                                    final days = int.parse(
                                                      _logsHistoryOptions[i]
                                                          .outcome,
                                                    );
                                                    context
                                                        .read<SettingsBloc>()
                                                        .add(
                                                          SettingsEvent.retentionPeriodChanged(
                                                            days,
                                                          ),
                                                        );
                                                  },
                                                  isSelected:
                                                      state
                                                          .retentionPeriodDays ==
                                                      int.parse(
                                                        _logsHistoryOptions[i]
                                                            .outcome,
                                                      ),
                                                  isFocused: false,
                                                  label: _logsHistoryOptions[i]
                                                      .label,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(),
                                  InkWell(
                                    onTap: state.isPruning
                                        ? null
                                        : () async {
                                            final confirmed =
                                                await _showClearHistoryConfirmationDialog(
                                                  context,
                                                );
                                            if (confirmed == true &&
                                                context.mounted) {
                                              context.read<SettingsBloc>().add(
                                                const SettingsEvent.clearActivityHistory(),
                                              );
                                              try {
                                                context.read<ActivityBloc>().add(
                                                  const ActivityEvent.refreshRequested(),
                                                );
                                              } catch (_) {}
                                            }
                                          },
                                    focusColor: Colors.transparent,
                                    borderRadius: .circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        spacing: 8,
                                        children: [
                                          Container(
                                            padding: .all(10),
                                            decoration: BoxDecoration(
                                              color: colors.error.withValues(
                                                alpha: .15,
                                              ),
                                              borderRadius: .circular(8),
                                            ),
                                            child: state.isPruning
                                                ? SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: colors.error,
                                                        ),
                                                  )
                                                : Icon(
                                                    CupertinoIcons.delete,
                                                    color: colors.error,
                                                    size: 20,
                                                  ),
                                          ),

                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "Clear activity history",
                                                  style: typo.titleMedium
                                                      .copyWith(
                                                        fontWeight: .bold,
                                                      ),
                                                ),
                                                Text(
                                                  state.isPruning
                                                      ? "Clearing logs..."
                                                      : "Removes the logs stored on this device",
                                                  style: typo.labelSmall
                                                      .copyWith(
                                                        color: colors
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _title(typo, colors, "APPEARANCE"),
                            const SizedBox(height: 4),
                            Container(
                              padding: .all(12),
                              decoration: BoxDecoration(
                                color: colors.segmentBg,
                                borderRadius: .circular(14),
                                border: Border.all(color: colors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: .start,
                                children: [
                                  Text(
                                    "Theme",
                                    style: typo.titleMedium.copyWith(
                                      fontWeight: .bold,
                                    ),
                                  ),
                                  Text(
                                    "System follows your device setting.",
                                    style: typo.labelSmall.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: colors.segmentBg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colors.border,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      spacing: 6,
                                      children: ThemeMode.values.map((e) {
                                        return FilterWidget(
                                          key: ValueKey(e.name),
                                          onTap: () {
                                            context.read<SettingsBloc>().add(
                                              SettingsEvent.themeChanged(e),
                                            );
                                          },
                                          isSelected: e == state.themeMode,
                                          isFocused: false,
                                          label: e.name,
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _title(typo, colors, "ABOUT"),
                            const SizedBox(height: 4),
                            Container(
                              decoration: BoxDecoration(
                                color: colors.segmentBg,
                                borderRadius: .circular(14),
                                border: Border.all(color: colors.border),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment: .start,
                                      spacing: 6,
                                      mainAxisAlignment: .spaceBetween,
                                      children: [
                                        Text(
                                          "Version",
                                          style: typo.titleMedium.copyWith(
                                            fontWeight: .bold,
                                          ),
                                        ),
                                        Text(
                                          packageInfo?.version ?? "1.0.0",
                                          style: typo.labelSmall.copyWith(
                                            color: colors.textSecondary,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(),
                                  InkWell(
                                    onTap: () => _launchURL(
                                      "https://aura.theja.in/privacy",
                                    ),
                                    focusColor: Colors.transparent,
                                    borderRadius: .circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        spacing: 8,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "Privacy Policy",
                                              style: typo.titleMedium.copyWith(
                                                fontWeight: .bold,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.open_in_new,
                                            color: colors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Divider(),
                                  InkWell(
                                    onTap: () => _launchURL(
                                      "https://aura.theja.in/terms",
                                    ),
                                    focusColor: Colors.transparent,
                                    borderRadius: .circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        spacing: 8,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "Terms of Use",
                                              style: typo.titleMedium.copyWith(
                                                fontWeight: .bold,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.open_in_new,
                                            color: colors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Divider(),
                                  InkWell(
                                    onTap: () => _launchURL(
                                      "https://aura.theja.in/support",
                                    ),
                                    focusColor: Colors.transparent,
                                    borderRadius: .circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        spacing: 8,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: .start,
                                              children: [
                                                Text(
                                                  "Support",
                                                  style: typo.titleMedium
                                                      .copyWith(
                                                        fontWeight: .bold,
                                                      ),
                                                ),
                                                Text(
                                                  "Help and Contact, Opens on the web",
                                                  style: typo.labelSmall
                                                      .copyWith(
                                                        color: colors
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.open_in_new,
                                            color: colors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Text _title(AppTypography typo, AppColors colors, String text) {
    return Text(
      text,
      style: typo.titleMedium.copyWith(
        color: colors.textSecondary,
        fontWeight: .w700,
      ),
    );
  }
}
