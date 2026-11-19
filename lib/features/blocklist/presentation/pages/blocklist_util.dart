import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/app_text_field.dart';
import 'package:theja_aura/core/utils/app_toast.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';

Future<void> handleAddRule({
  required bool isBlockedDefault,
  required BuildContext context,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AddRuleDialogContent(isBlockedDefault: isBlockedDefault);
    },
  );
}

class _AddRuleDialogContent extends StatefulWidget {
  final bool isBlockedDefault;

  const _AddRuleDialogContent({required this.isBlockedDefault});

  @override
  State<_AddRuleDialogContent> createState() => _AddRuleDialogContentState();
}

class _AddRuleDialogContentState extends State<_AddRuleDialogContent> {
  final TextEditingController _domainController = TextEditingController();
  late final FocusNode _domainFocusNode;
  bool _isCloseFocused = false;
  bool _isEditing = false;
  String? _validationError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _domainFocusNode = FocusNode(
      debugLabel: 'AddRuleDomainFocusNode',
      onKeyEvent: _handleDomainKeyEvent,
    );
  }

  @override
  void dispose() {
    _domainFocusNode.dispose();
    _domainController.dispose();
    super.dispose();
  }

  KeyEventResult _handleDomainKeyEvent(FocusNode node, KeyEvent event) {
    if (!PlatformChecker.isAndroidTV) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isActivationKey =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;

    final isBackKey =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

    if (!_isEditing) {
      if (isActivationKey) {
        if (event is KeyDownEvent) {
          setState(() {
            _isEditing = true;
          });
          _domainController.selection = TextSelection.collapsed(
            offset: _domainController.text.length,
          );
        }
        return KeyEventResult.handled;
      }

      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (key == LogicalKeyboardKey.arrowDown) {
          final moved = node.focusInDirection(TraversalDirection.down);
          if (moved) return KeyEventResult.handled;
          final next = node.nextFocus();
          return next ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          final moved = node.focusInDirection(TraversalDirection.up);
          if (moved) return KeyEventResult.handled;
          final prev = node.previousFocus();
          return prev ? KeyEventResult.handled : KeyEventResult.ignored;
        }
      }
      return KeyEventResult.ignored;
    } else {
      if (isBackKey) {
        if (event is KeyDownEvent) {
          setState(() {
            _isEditing = false;
          });
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final isTv = PlatformChecker.isAndroidTV;

    return PopScope(
      canPop: !(isTv && _isEditing),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isTv && _isEditing) {
          setState(() {
            _isEditing = false;
          });
        }
      },
      child: Dialog(
        constraints: const BoxConstraints(maxWidth: 500),
        backgroundColor: colors.segmentBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border, width: 1),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                    Material(
                      color: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: (isTv && _isCloseFocused)
                              ? colors.primary
                              : colors.border,
                          width: isTv ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onFocusChange: (f) {
                          setState(() {
                            _isCloseFocused = f;
                          });
                        },
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surfaceRaised,
                            borderRadius: .circular(8),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, color: colors.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(
                  hintText: "ads.example.com",
                  borderColor: colors.border,
                  controller: _domainController,
                  focusNode: _domainFocusNode,
                  readOnly: isTv && !_isEditing,
                  keyboardType: TextInputType.url,
                  errorText: _validationError,
                  showSuffixIcon: false,
                  prefixIcon: Icon(
                    Icons.language,
                    color: colors.textSecondary,
                  ),
                  onChanged: (val) {
                    if (_validationError != null) {
                      setState(() {
                        _validationError = null;
                      });
                    }
                  },
                  onFieldSubmitted: (_) {
                    if (isTv) {
                      setState(() {
                        _isEditing = false;
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
                const SizedBox(height: 16),
                AppButton(
                  text: "Block",
                  color: colors.primary,
                  width: double.infinity,
                  isLoading: _isSubmitting,
                  icon: _isSubmitting ? const CupertinoActivityIndicator() : null,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: () async {
                    final rawDomain = _domainController.text.trim();
                    if (rawDomain.isEmpty) {
                      setState(() {
                        _validationError = 'Domain name cannot be empty.';
                      });
                      return;
                    }

                    setState(() {
                      _isSubmitting = true;
                      _validationError = null;
                    });

                    try {
                      final isValid = await context
                          .read<BlocklistBloc>()
                          .validateDomain(rawDomain);
                      if (!isValid) {
                        setState(() {
                          _isSubmitting = false;
                          _validationError =
                              'Invalid domain or public suffix rejected.';
                        });
                        return;
                      }
                      if (!mounted || !context.mounted) {
                        return;
                      }
                      final success = await context
                          .read<BlocklistBloc>()
                          .addRule(
                            domain: rawDomain,
                            isBlocked: widget.isBlockedDefault,
                          );

                      if (!mounted || !context.mounted) {
                        return;
                      }
                          context.pop();

                      if (success) {
                        showSuccessToast(
                          message: 'Added $rawDomain to your list.',
                        );
                      }
                    } on AuraRuleException catch (e) {
                      setState(() {
                        _isSubmitting = false;
                        _validationError = e.message;
                      });
                    } catch (e) {
                      setState(() {
                        _isSubmitting = false;
                        _validationError = 'Error: $e';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
