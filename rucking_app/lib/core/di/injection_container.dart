import 'package:rucking_app/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart';
import 'package:rucking_app/features/planned_rucks/presentation/bloc/route_import_bloc.dart';
import 'package:rucking_app/core/repositories/planned_rucks_repository.dart';
import 'package:rucking_app/core/repositories/routes_repository.dart';
import 'package:rucking_app/core/services/gpx_service.dart';
import 'package:rucking_app/core/services/auth_service_consolidated.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:dio/dio.dart';

/// Simple stub storage service for DI
class _StubStorageService implements StorageService {
  final Map<String, dynamic> _storage = {};

  @override
  Future<void> setString(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<String?> getString(String key) async {
    return _storage[key];
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _storage[key] = value;
  }

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    return _storage[key] ?? defaultValue;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _storage[key] = value;
  }

  @override
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    return _storage[key] ?? defaultValue;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    _storage[key] = value;
  }

  @override
  Future<double> getDouble(String key, {double defaultValue = 0.0}) async {
    return _storage[key] ?? defaultValue;
  }

  @override
  Future<void> setObject(String key, Map<String, dynamic> value) async {
    _storage[key] = value;
  }

  @override
  Future<Map<String, dynamic>?> getObject(String key) async {
    return _storage[key];
  }

  @override
  Future<void> setSecureString(String key, String value) async {
    _storage['secure_$key'] = value;
  }

  @override
  Future<String?> getSecureString(String key) async {
    return _storage['secure_$key'];
  }

  @override
  Future<String?> getAuthToken() async {
    return _storage['secure_auth_token'];
  }

  @override
  Future<bool> hasKey(String key) async {
    return _storage.containsKey(key);
  }

  @override
  Future<Set<String>> getAllKeys() async {
    return _storage.keys.toSet();
  }

  @override
  Future<void> remove(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> removeSecure(String key) async {
    _storage.remove('secure_$key');
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }
}

/// Simple dependency injection stub
/// TODO: Replace with proper DI system when needed
class _ServiceLocator {
  final Map<Type, dynamic> _services = {};

  T call<T>() {
    if (!_services.containsKey(T)) {
      // Create instances on demand
      if (T == PlannedRuckBloc) {
        _services[T] = PlannedRuckBloc(
          plannedRucksRepository: PlannedRucksRepository(),
        );
      } else if (T == RouteImportBloc) {
        _services[T] = RouteImportBloc(
          routesRepository: RoutesRepository(),
          plannedRucksRepository: PlannedRucksRepository(),
          gpxService: GpxService(),
          authService: call<AuthService>(),
        );
      } else if (T == PlannedRucksRepository) {
        _services[T] = PlannedRucksRepository();
      } else if (T == RoutesRepository) {
        _services[T] = RoutesRepository();
      } else if (T == GpxService) {
        _services[T] = GpxService();
      } else if (T == AuthService) {
        _services[T] = AuthService(
          call<ApiClient>(),
          call<StorageService>(),
        );
      } else if (T == ApiClient) {
        _services[T] = ApiClient(call<StorageService>(), Dio());
      } else if (T == StorageService) {
        // Create a simple working storage service
        _services[T] = _StubStorageService();
      } else {
        throw Exception('Service $T not registered in DI container');
      }
    }
    return _services[T] as T;
  }
}

/// Global service locator instance
final getIt = _ServiceLocator();
