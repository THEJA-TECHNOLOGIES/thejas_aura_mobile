// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:http/http.dart' as _i519;
import 'package:injectable/injectable.dart' as _i526;
import 'package:theja_aura/core/config/app_config.dart' as _i990;
import 'package:theja_aura/core/DI/register_module.dart' as _i292;
import 'package:theja_aura/core/services/aura_activity_service.dart' as _i898;
import 'package:theja_aura/core/services/aura_tunnel_service.dart' as _i975;
import 'package:theja_aura/features/activity/data/repositories/activity_repository.dart'
    as _i329;
import 'package:theja_aura/features/activity/domain/repositories/i_activity_repository.dart'
    as _i24;
import 'package:theja_aura/features/activity/presentation/bloc/activity_bloc.dart'
    as _i191;
import 'package:theja_aura/features/blocklist/data/datasources/blocklist_api_client.dart'
    as _i351;
import 'package:theja_aura/features/blocklist/data/repositories/blocklist_repository.dart'
    as _i39;
import 'package:theja_aura/features/blocklist/data/repositories/blocklist_sync_repository.dart'
    as _i629;
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_repository.dart'
    as _i119;
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_sync_repository.dart'
    as _i599;
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart'
    as _i453;
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_sync_cubit.dart'
    as _i794;
import 'package:theja_aura/features/dashboard/data/repositories/dashboard_repository.dart'
    as _i549;
import 'package:theja_aura/features/dashboard/domain/repositories/i_dashboard_repository.dart'
    as _i56;
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart'
    as _i442;
import 'package:theja_aura/features/settings/presentation/bloc/bloc/theme_bloc.dart'
    as _i151;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final registerModule = _$RegisterModule();
    await gh.factoryAsync<_i990.AppConfig>(
      () => registerModule.appConfig,
      preResolve: true,
    );
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => registerModule.secureStorage,
    );
    gh.lazySingleton<_i975.AuraTunnelService>(
      () => registerModule.tunnelService,
    );
    gh.lazySingleton<_i898.AuraActivityService>(
      () => registerModule.activityService,
    );
    gh.lazySingleton<_i519.Client>(() => registerModule.httpClient);
    gh.lazySingleton<_i56.IDashboardRepository>(
      () => _i549.DashboardRepository(
        gh<_i975.AuraTunnelService>(),
        gh<_i898.AuraActivityService>(),
      ),
    );
    gh.lazySingleton<_i351.IBlocklistApiClient>(
      () => _i351.BlocklistApiClient(gh<_i990.AppConfig>(), gh<_i519.Client>()),
    );
    gh.lazySingleton<_i119.IBlocklistRepository>(
      () => _i39.BlocklistRepository(gh<_i975.AuraTunnelService>()),
    );
    gh.factory<_i151.ThemeBloc>(
      () => _i151.ThemeBloc(gh<_i558.FlutterSecureStorage>()),
    );
    gh.lazySingleton<_i24.IActivityRepository>(
      () => _i329.ActivityRepository(gh<_i898.AuraActivityService>()),
    );
    gh.lazySingleton<_i599.IBlocklistSyncRepository>(
      () => _i629.BlocklistSyncRepository(
        gh<_i351.IBlocklistApiClient>(),
        gh<_i975.AuraTunnelService>(),
      ),
    );
    gh.factory<_i794.BlocklistSyncCubit>(
      () => _i794.BlocklistSyncCubit(gh<_i599.IBlocklistSyncRepository>()),
    );
    gh.factory<_i453.BlocklistBloc>(
      () => _i453.BlocklistBloc(gh<_i119.IBlocklistRepository>()),
    );
    gh.factory<_i191.ActivityBloc>(
      () => _i191.ActivityBloc(
        gh<_i24.IActivityRepository>(),
        gh<_i119.IBlocklistRepository>(),
      ),
    );
    gh.factory<_i442.DashboardBloc>(
      () => _i442.DashboardBloc(gh<_i56.IDashboardRepository>()),
    );
    return this;
  }
}

class _$RegisterModule extends _i292.RegisterModule {}
