import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_toast.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/blocklist_util.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/widgets/custom_domain_tab.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/widgets/default_domain_tab.dart';

import '../bloc/blocklist_bloc.dart';
import '../bloc/blocklist_sync_cubit.dart';

class BlocklistPage extends StatefulWidget {
  const BlocklistPage({super.key});
  static Future<void> show({required BuildContext context}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // backgroundColor: Colors.transparent,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const BlocklistPage(),
    );
  }

  @override
  State<BlocklistPage> createState() => _BlocklistPageState();
}

class _BlocklistPageState extends State<BlocklistPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
    context.read<BlocklistBloc>().add(const BlocklistEvent.started());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final isTv = PlatformChecker.isAndroidTV;

    return MultiBlocListener(
      listeners: [
        BlocListener<BlocklistBloc, BlocklistState>(
          listener: (context, state) {
            if (state.actionError != null) {
              showErrorToast(message: state.actionError!);
              context.read<BlocklistBloc>().add(
                const BlocklistEvent.actionErrorDismissed(),
              );
            }
          },
        ),
        BlocListener<BlocklistSyncCubit, BlocklistSyncState>(
          listenWhen: (previous, current) =>
              previous.state != current.state &&
              (current.state == SyncState.updated ||
                  current.state == SyncState.upToDate),
          listener: (context, syncState) {
            context.read<BlocklistBloc>().add(
              const BlocklistEvent.defaultCategoriesRefreshRequested(),
            );
          },
        ),
      ],
      child: BlocBuilder<BlocklistBloc, BlocklistState>(
        builder: (context, state) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Block lists'),
                leading: (isTv && Navigator.of(context).canPop())
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    : null,
              ),
              body: Column(
                children: [
                  Container(
                    padding: .all(4),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.segmentBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border, width: 1),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'Default'),
                        Tab(text: 'Custom'),
                      ],
                      labelStyle: typo.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle: typo.titleMedium.copyWith(
                        color: colors.textSecondary,
                      ),
                      dividerColor: Colors.transparent,
                      dividerHeight: 0.0,
                      indicator: BoxDecoration(
                        color: colors.surfaceRaised,
                        borderRadius: .circular(12),
                      ),
                      indicatorSize: .tab,
                      splashBorderRadius: BorderRadius.circular(12),
                      overlayColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
                        if (states.contains(WidgetState.focused)) {
                          return colors.surfaceRaised;
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return colors.surfaceRaised;
                        }
                        return null;
                      }),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: const [DefaultDomainTab(), CustomDomainTab()],
                    ),
                  ),
                ],
              ),
              floatingActionButton: AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  if (_tabController.index != 1) return const SizedBox.shrink();
                  return FloatingActionButton.extended(
                    onPressed: () =>
                        handleAddRule(isBlockedDefault: true, context: context),
                    icon: Icon(Icons.add, color: colors.white),
                    label: const Text(
                      'Add Domain',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    elevation: 0,
                    focusElevation: 6,
                    focusColor: colors.primary.withValues(alpha: 0.8),
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isTv ? colors.white : Colors.transparent,
                        width: isTv ? 2 : 0,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
