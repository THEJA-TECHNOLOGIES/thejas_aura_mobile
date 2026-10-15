import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

class FirewallController extends StatelessWidget {
  const FirewallController({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      DashboardBloc,
      DashboardState,
      (bool, bool, TunnelStatus)
    >(
      selector: (state) {
        return (state.isInitialized, state.isTogglingTunnel, state.status);
      },
      builder: (context, state) {
        final (isInitialized, isTogglingTunnel, status) = state;
        final isConnected = status == TunnelStatus.connected;
        final isBusy =
            !isInitialized ||
            status == TunnelStatus.connecting ||
            status == TunnelStatus.disconnecting ||
            isTogglingTunnel;
        return Container();
      },
    );
  }
}
