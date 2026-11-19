import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_sync_repository.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_sync_cubit.dart';

class BlockListSyncIndicator extends StatelessWidget {
  final BlocklistSyncCubit? cubit;

  const BlockListSyncIndicator({super.key, this.cubit});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;

    return BlocBuilder<BlocklistSyncCubit, BlocklistSyncState>(
      bloc: cubit,
      builder: (context, state) {
        Widget content;

        if (state.isLoading) {
          final progress = state.progress;
          content = Container(
            key: const ValueKey('blocklist_sync_loading'),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: progress != null
                ? TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    tween: Tween<double>(
                      begin: 0.0,
                      end: (progress).clamp(0.0, 1.0),
                    ),
                    builder: (context, animatedVal, _) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Updating block lists..",
                                style: typo.titleMedium,
                              ),
                              Text(
                                "${(animatedVal * 100).round()}%",
                                style: typo.bodyMedium.copyWith(
                                  color: colors.textSecondary,
                                  fontWeight: .bold,
                                ),
                              ),
                            ],
                          ),
                          LinearProgressIndicator(
                            value: animatedVal,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ],
                      );
                    },
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text("Updating block lists..", style: typo.titleMedium),
                      LinearProgressIndicator(
                        value: null,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ],
                  ),
          );
        } else if (state.errorMessage != null &&
            state.errorMessage!.isNotEmpty) {
          print(state.errorMessage);
          content = Container(
            key: const ValueKey('blocklist_sync_error'),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 18),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.error),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colors.error,
                  size: 20,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Block list sync failed",
                        style: typo.titleMedium.copyWith(
                          color: colors.textPrimary,
                          height: 1,
                        ),
                      ),
                      Text(
                        state.errorMessage ?? "Failed to sync",
                        style: typo.bodyMedium.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: state.isLoading
                      ? null
                      : () {
                          final targetCubit =
                              cubit ?? context.read<BlocklistSyncCubit>();
                          targetCubit.sync().catchError((e) {
                            return SyncResult.failure(error: e.toString());
                          });
                        },

                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.focused)) {
                        return colors.error.withValues(alpha: 0.1);
                      }
                      return null;
                    }),

                    side: WidgetStateProperty.resolveWith<BorderSide?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: colors.error);
                      }
                      return null;
                    }),
                  ),
                  icon: Icon(Icons.refresh, color: colors.error),
                  label: Text(
                    "Retry",
                    style: typo.titleMedium.copyWith(
                      color: colors.error,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          content = const SizedBox.shrink();
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: content,
        );
      },
    );
  }
}
