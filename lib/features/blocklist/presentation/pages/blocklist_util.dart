import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/app_text_field.dart';
import 'package:theja_aura/core/utils/app_toast.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';

Future<void> handleAddRule({
  required bool isBlockedDefault,
  required BuildContext context,
}) async {
  final domainController = TextEditingController();
  bool isBlocked = isBlockedDefault;
  String? validationError;
  bool isSubmitting = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = context.appColors;
          final typo = context.appTypography;
          return Dialog(
            constraints: BoxConstraints(maxWidth: 500),
            backgroundColor: colors.segmentBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.border, width: 1),
            ),
            insetPadding: EdgeInsets.symmetric(horizontal: 16),
            // title: Text(isBlocked ? 'Add Block Rule' : 'Add Allow Rule'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Add a domain",
                            style: typo.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            context.pop();
                          },
                          child: Container(
                            decoration: ShapeDecoration(
                              color: colors.surfaceRaised,
                              shape: RoundedRectangleBorder(
                                borderRadius: .circular(8),
                                side: BorderSide(
                                  color: colors.border,
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close, color: colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    AppTextField(
                      hintText: "ads.example.com",
                      borderColor: colors.border,
                      controller: domainController,
                      keyboardType: TextInputType.url,
                      errorText: validationError,
                      showSuffixIcon: false,
                      prefixIcon: Icon(
                        Icons.language,
                        color: colors.textSecondary,
                      ),
                      onChanged: (val) {
                        if (validationError != null) {
                          setDialogState(() {
                            validationError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Queries matching this domain and subdomains will be blocked.',
                      style: typo.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 16),
                    AppButton(
                      text: "Block",
                      color: colors.primary,
                      width: double.infinity,
                      isLoading: isSubmitting,
                      icon: isSubmitting ? CupertinoActivityIndicator() : null,
                      padding: .symmetric(vertical: 12),
                      onPressed: () async {
                        final rawDomain = domainController.text.trim();
                        if (rawDomain.isEmpty) {
                          setDialogState(() {
                            validationError = 'Domain name cannot be empty.';
                          });
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          validationError = null;
                        });

                        try {
                          final isValid = await context
                              .read<BlocklistBloc>()
                              .validateDomain(rawDomain);
                          if (!isValid) {
                            setDialogState(() {
                              isSubmitting = false;
                              validationError =
                                  'Invalid domain or public suffix rejected.';
                            });
                            return;
                          }
                          if (!dialogContext.mounted || !context.mounted) {
                            return;
                          }
                          final success = await context
                              .read<BlocklistBloc>()
                              .addRule(domain: rawDomain, isBlocked: isBlocked);

                          if (!dialogContext.mounted || !context.mounted) {
                            return;
                          }
                          dialogContext.pop();

                          if (success) {
                            showSuccessToast(
                              message: 'Added $rawDomain to your list.',
                            );
                          }
                        } on AuraRuleException catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            validationError = e.message;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            validationError = 'Error: $e';
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> handleDeleteRule(AuraRuleItem rule, BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final colors = context.appColors;
      return Dialog(
        constraints: BoxConstraints(maxWidth: 500),
        backgroundColor: colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border, width: 1),
        ),
        insetPadding: EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: .start,
              children: [
                Text(
                  "Remove this domain?",
                  style: context.theme.appTypography.titleLarge.copyWith(),
                ),
                const SizedBox(height: 16),
                Text(
                  "${rule.domain} will stop being blocked right away.",
                  style: context.theme.appTypography.labelLarge,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 16,
                  children: [
                    Expanded(
                      child: AppButton(
                        text: "Cancel",
                        color: colors.gray2,
                        onPressed: () {
                          ctx.pop(false);
                        },
                        padding: .symmetric(vertical: 10),
                      ),
                    ),
                    Expanded(
                      child: AppButton(
                        text: "Remove",
                        padding: .symmetric(vertical: 10),
                        color: colors.error,
                        onPressed: () {
                          ctx.pop(true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (confirmed != true) return;
  if (!context.mounted) return;
  final success = await context.read<BlocklistBloc>().deleteRule(rule.id);
  if (success && context.mounted) {
    showErrorToast(message: "Deleated ${rule.domain} form your list.");
  }
}
