import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/storage_service.dart';

/// Interface for authentication operations
abstract class AuthService {
  /// Sign in with email and password
  Future<User> signIn(String email, String password);
  
  /// Register a new user
  Future<User> register({
    required String name,
    required String email,
    required String password,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  });
  
  /// Sign out the current user
  Future<void> signOut();
  
  /// Get the current authenticated user
  Future<User?> getCurrentUser();
  
  /// Check if the user is authenticated
  Future<bool> isAuthenticated();
  
  /// Get the authentication token
  Future<String?> getToken();
  
  /// Update the user profile
  Future<User> updateProfile({
    String? name,
    double? weightKg,
    double? heightCm,
  });
}

/// Implementation of AuthService using ApiClient and StorageService
class AuthServiceImpl implements AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;
  
  AuthServiceImpl(this._apiClient, this._storageService);
  
  @override
  Future<User> signIn(String email, String password) async {
    try {
      final response = await _apiClient.post(
        '/auth/login',
        {
          'email': email,
          'password': password,
        },
      );
      
      final token = response['token'] as String;
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      
      // Set token in API client
      _apiClient.setAuthToken(token);
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  }) async {
    try {
      final response = await _apiClient.post(
        '/users/register',
        {
          'name': name,
          'email': email,
          'password': password,
          if (weightKg != null) 'weight_kg': weightKg,
          if (heightCm != null) 'height_cm': heightCm,
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        },
      );
      
      // After registration, login automatically
      return await signIn(email, password);
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<void> signOut() async {
    // Clear token and user data
    await _storageService.removeSecure(AppConfig.tokenKey);
    await _storageService.remove(AppConfig.userProfileKey);
    await _storageService.remove(AppConfig.userIdKey);
    
    // Clear token in API client
    _apiClient.clearAuthToken();
  }
  
  @override
  Future<User?> getCurrentUser() async {
    try {
      // Check if we have a stored user
      final userData = await _storageService.getObject(AppConfig.userProfileKey);
      if (userData == null) return null;
      
      // Get fresh user data from API
      final response = await _apiClient.get('/users/profile');
      final user = User.fromJson(response);
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      return user;
    } catch (e) {
      if (e is UnauthorizedException) {
        await signOut();
        return null;
      }
      
      // If there's a network error, return the stored user
      final userData = await _storageService.getObject(AppConfig.userProfileKey);
      if (userData != null) {
        return User.fromJson(userData);
      }
      
      return null;
    }
  }
  
  @override
  Future<bool> isAuthenticated() async {
    // For development without backend
    if ((await _apiClient.get('/users/profile')) != null) {
      // Save mock token for consistency
      await _storageService.setSecureString(AppConfig.tokenKey, 'mock_token_123456');
      return true;
    }
    
    final token = await _storageService.getSecureString(AppConfig.tokenKey);
    return token != null;
  }
  
  @override
  Future<String?> getToken() async {
    return await _storageService.getSecureString(AppConfig.tokenKey);
  }
  
  @override
  Future<User> updateProfile({
    String? name,
    double? weightKg,
    double? heightCm,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (weightKg != null) data['weight_kg'] = weightKg;
      if (heightCm != null) data['height_cm'] = heightCm;
      
      final response = await _apiClient.put(
        '/users/profile',
        data,
      );
      
      final user = User.fromJson(response);
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  /// Convert generic exceptions to auth-specific exceptions
  Exception _handleAuthError(dynamic error) {
    if (error is ApiException) {
      return error;
    }
    
    return ApiException('Authentication error: $error');
  }
} 