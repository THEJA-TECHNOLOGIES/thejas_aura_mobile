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
            margin: EdgeInsets.only(left: 16, right: 16, bottom: 18),
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
            margin: EdgeInsets.only(left: 16, right: 16, bottom: 18),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.error),
            ),
            child: Row(
              crossAxisAlignment: .center,
              mainAxisAlignment: .center,
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
                        state.errorMessage!,
                        style: typo.bodyMedium.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
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
        }

        return const SizedBox.shrink();
      },
    );
  }
}
