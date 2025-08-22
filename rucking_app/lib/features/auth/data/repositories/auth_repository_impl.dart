import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'dart:convert';

/// Implementation of the AuthRepository interface
class AuthRepositoryImpl implements AuthRepository {
  final AuthService _authService;
  
  AuthRepositoryImpl(this._authService);
  
  @override
  Future<User> login({required String email, required String password}) async {
    return await _authService.signIn(email, password);
  }

  @override
  Future<User> googleLogin() async {
    return await _authService.googleSignIn();
  }
  
  @override
  Future<User> appleLogin() async {
    return await _authService.appleSignIn();
  }
  
  @override
  Future<User> googleRegister({
    required String email,
    required String displayName,
    required String username,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    return await _authService.googleRegister(
      email: email,
      displayName: displayName,
      username: username,
      preferMetric: preferMetric,
      weightKg: weightKg,
      heightCm: heightCm,
      dateOfBirth: dateOfBirth,
      gender: gender,
    );
  }
  
  @override
  Future<User> register({
    required String username, // This is the display name
    required String email,
    required String password,
    required bool preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
    String? gender,
  }) async {
    return await _authService.register(
      username: username, // This is the display name
      email: email,
      password: password,
      preferMetric: preferMetric,
      weightKg: weightKg,
      heightCm: heightCm,
      dateOfBirth: dateOfBirth,
      gender: gender,
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
    String? username,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
    bool? allowRuckSharing,
    String? gender,
    String? avatarUrl,
    bool? notificationClubs,
    bool? notificationBuddies,
    bool? notificationEvents,
    bool? notificationDuels,
    String? dateOfBirth,
    int? restingHr,
    int? maxHr,
    String? calorieMethod,
    bool? calorieActiveOnly,
  }) async {
    return await _authService.updateProfile(
      username: username,
      weightKg: weightKg,
      heightCm: heightCm,
      preferMetric: preferMetric,
      allowRuckSharing: allowRuckSharing,
      gender: gender,
      avatarUrl: avatarUrl,
      notificationClubs: notificationClubs,
      notificationBuddies: notificationBuddies,
      notificationEvents: notificationEvents,
      notificationDuels: notificationDuels,
      dateOfBirth: dateOfBirth,
      restingHr: restingHr,
      maxHr: maxHr,
      calorieMethod: calorieMethod,
      calorieActiveOnly: calorieActiveOnly,
    );
  }

  @override
  Future<void> deleteAccount({required String userId}) async {
    await _authService.deleteAccount(userId: userId);
  }

  @override
  Future<String?> refreshToken() async {
    try {
      // Call the refreshToken method on AuthService, without passing the refresh token
      final newToken = await _authService.refreshToken();
      return newToken;
    } catch (e) {
      // Utilize ErrorHandler to get a user-friendly error message
      final userFriendlyMessage = ErrorHandler.getUserFriendlyMessage(e, 'Token Refresh');
      // If the error is related to authentication, trigger logout to clear invalid tokens
      if (e.toString().contains('Unauthorized') || e.toString().contains('401')) {
        await _authService.signOut();
        // Log a message indicating manual login is required due to persistent auth issues
        print('[AUTH] Persistent authentication failure. Manual login required.');
        print('[AUTH] The refresh token is invalid. Please log in again to obtain a new token.');
      }
      throw Exception('Failed to refresh token: $userFriendlyMessage');
    }
  }
  
  @override
  Future<void> requestPasswordReset({required String email}) async {
    await _authService.requestPasswordReset(email: email);
  }
  
  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
    String? refreshToken,
  }) async {
    await _authService.confirmPasswordReset(
      token: token,
      newPassword: newPassword,
      refreshToken: refreshToken,
    );
  }
}