import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_button.dart';
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
        if (state.isLoading) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text("Updating block lists..", style: typo.titleMedium),
                LinearProgressIndicator(
                  value: state.progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(30),
                ),
              ],
            ),
          );
        }

        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: colors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Block list sync failed",
                        style: typo.titleMedium.copyWith(color: colors.error),
                      ),
                    ),
                  ],
                ),
                Text(
                  state.errorMessage!,
                  style: typo.bodySmall.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    key: const Key('block_list_sync_retry_button'),
                    text: "Retry",
                    color: colors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    borderRadius: 12,
                    isLoading: state.isLoading,
                    onPressed: state.isLoading
                        ? null
                        : () {
                            final targetCubit =
                                cubit ?? context.read<BlocklistSyncCubit>();
                            targetCubit.sync().catchError((e) {
                              return SyncResult.failure(error: e.toString());
                            });
                          },
                  ),
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
