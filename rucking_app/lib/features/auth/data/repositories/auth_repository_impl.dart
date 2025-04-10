import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';

/// Implementation of the AuthRepository interface
class AuthRepositoryImpl implements AuthRepository {
  final AuthService _authService;
  
  AuthRepositoryImpl(this._authService);
  
  @override
  Future<User> login({required String email, required String password}) async {
    return await _authService.signIn(email, password);
  }
  
  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  }) async {
    return await _authService.register(
      name: name,
      email: email,
      password: password,
      weightKg: weightKg,
      heightCm: heightCm,
      dateOfBirth: dateOfBirth,
    );
  }
  
  @override
  Future<void> logout() async {
    await _authService.signOut();
  }
  
  @override
  Future<bool> isAuthenticated() async {
    return await _authService.isAuthenticated();
  }
  
  @override
  Future<User?> getCurrentUser() async {
    return await _authService.getCurrentUser();
  }
  
  @override
  Future<User> updateProfile({
    String? name,
    double? weightKg,
    double? heightCm,
  }) async {
    return await _authService.updateProfile(
      name: name,
      weightKg: weightKg,
      heightCm: heightCm,
    );
  }
} 