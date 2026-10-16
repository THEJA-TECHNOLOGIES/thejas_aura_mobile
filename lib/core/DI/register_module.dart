import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/config/app_config.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

@module
abstract class RegisterModule {
  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage();

  @lazySingleton
  AuraTunnelService get tunnelService => AuraTunnelService();

  @lazySingleton
  AuraActivityService get activityService => AuraActivityService();

  @lazySingleton
  http.Client get httpClient => http.Client();

  @preResolve
  Future<AppConfig> get appConfig => AppConfig.load();
}
