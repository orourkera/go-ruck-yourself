import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Interface for authentication operations
abstract class AuthService {
  /// Sign in with email and password
  Future<User> signIn(String email, String password);
  
  /// Register a new user
  Future<User> register({
    required String username, // This is the display name
    required String email,
    required String password,
    bool? preferMetric,
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
  
  /// Refresh the authentication token
  Future<String?> refreshToken();
  
  /// Log the user out
  Future<void> logout();
  
  /// Update the user profile
  Future<User> updateProfile({
    String? username,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
  });

  /// Delete the current user's account
  /// Requires the user's ID to target the correct backend endpoint.
  Future<void> deleteAccount({required String userId});
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
      final refreshToken = response['refresh_token'] as String;
      final userData = response['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);
      
      // Debug logging to confirm token receipt
      print('[AUTH] Login successful. Access token received: ${token.isNotEmpty}');
      print('[AUTH] Refresh token received: ${refreshToken.isNotEmpty}');
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      await _storageService.setSecureString(AppConfig.refreshTokenKey, refreshToken);
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      await _storageService.setString(AppConfig.userIdKey, user.userId);
      // Confirm storage
      print('[AUTH] Tokens and user data stored in secure storage.');
      
      // Set token in API client
      _apiClient.setAuthToken(token);
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<User> register({
    required String username, // This is the display name
    required String email,
    required String password,
    bool? preferMetric,
    double? weightKg,
    double? heightCm,
    String? dateOfBirth,
  }) async {
    try {
      final response = await _apiClient.post(
        '/users/register',
        {
          'username': username, // This is the display name
          'email': email,
          'password': password,
          if (preferMetric != null) 'preferMetric': preferMetric,
          if (weightKg != null) 'weight_kg': weightKg,
          if (heightCm != null) 'height_cm': heightCm,
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        },
      );
      
      final token = response['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Registration failed: No token returned from server.');
      }
      final refreshToken = response['refresh_token'] as String?;
      final userData = response['user'];
      if (userData == null) {
        throw Exception('Registration failed: No user data returned from server.');
      }
      final user = User.fromJson(userData as Map<String, dynamic>);
      
      // Store token and user data
      await _storageService.setSecureString(AppConfig.tokenKey, token);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _storageService.setSecureString(AppConfig.refreshTokenKey, refreshToken);
      }
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
  Future<void> signOut() async {
    // Clear token and user data
    await _storageService.removeSecure(AppConfig.tokenKey);
    await _storageService.removeSecure(AppConfig.refreshTokenKey);
    await _storageService.remove(AppConfig.userProfileKey);
    await _storageService.remove(AppConfig.userIdKey);
    
    // Confirm token clearing
    print('[AUTH] Tokens and user data cleared from storage during sign out.');
    // Clear token in API client
    _apiClient.clearAuthToken();
  }
  
  @override
  Future<User?> getCurrentUser() async {
    User? userToReturn;
    String? userId = await _storageService.getString(AppConfig.userIdKey);
    
    // Ideally, fetch email stored securely during login if available
    // For simplicity now, we'll assume ID is enough to link
    if (userId == null) {
        await signOut(); // If no ID, sign out
        return null;
    }

    try {
      // Get profile data from API using userId
      final profileResponse = await _apiClient.get('/users/profile'); // This uses g.user.id on backend
      
      final userFromProfile = User.fromJson(profileResponse);
      
      // Update stored user data (might overwrite email if missing from profile)
      await _storageService.setObject(AppConfig.userProfileKey, userFromProfile.toJson());
      userToReturn = userFromProfile;
      
    } catch (e) {
      if (e is UnauthorizedException) {
        await signOut();
        return null;
      }
      // Fallback to stored user on network error
      final storedUserData = await _storageService.getObject(AppConfig.userProfileKey);
      if (storedUserData != null) {
        userToReturn = User.fromJson(storedUserData);
      }
    }
    return userToReturn;
  }
  
  @override
  Future<bool> isAuthenticated() async {
    // First check if we have a token stored
    final token = await _storageService.getSecureString(AppConfig.tokenKey);
    if (token == null) {
      return false; // No token means not authenticated
    }
    
    // Set the token for API requests
    _apiClient.setAuthToken(token);
    
    try {
      // Try to get the user profile
      final response = await _apiClient.get('/users/profile');
      return response != null;
    } catch (e) {
      if (e is UnauthorizedException) {
        // Token is invalid or expired
        await signOut();
        return false;
      }
      
      // For network errors, check if we have a stored user
      final userData = await _storageService.getObject(AppConfig.userProfileKey);
      return userData != null;
    }
  }
  
  @override
  Future<String?> getToken() async {
    return await _storageService.getSecureString(AppConfig.tokenKey);
  }
  
  @override
  Future<String?> refreshToken() async {
    final storedRefreshToken = await _storageService.getSecureString(AppConfig.refreshTokenKey);
    // Debug logging to check if refresh token exists
    print('[AUTH] Attempting token refresh. Refresh token available: ${storedRefreshToken != null}');
    // Log a redacted version of the token for debugging (first few and last few characters only)
    if (storedRefreshToken != null) {
      String redactedToken = storedRefreshToken.length > 10 
          ? '${storedRefreshToken.substring(0, 5)}...${storedRefreshToken.substring(storedRefreshToken.length - 5)}' 
          : '[SHORT TOKEN]';
      print('[AUTH] Refresh token (redacted): $redactedToken');
    }
    if (storedRefreshToken == null) {
      throw UnauthorizedException('Refresh token not found');
    }
    final response = await _apiClient.post('/auth/refresh', {'refresh_token': storedRefreshToken});
    // Log the response from the server for debugging
    print('[AUTH] Token refresh response: $response');
    final newToken = response['token'] as String;
    final newRefreshToken = response['refresh_token'] as String;

    // Store new tokens
    await _storageService.setSecureString(AppConfig.tokenKey, newToken);
    await _storageService.setSecureString(AppConfig.refreshTokenKey, newRefreshToken);
    
    // Set new token in API client
    _apiClient.setAuthToken(newToken);
    
    return newToken;
  }
  
  @override
  Future<void> logout() async {
    await signOut();
  }
  
  @override
  Future<User> updateProfile({
    String? username,
    double? weightKg,
    double? heightCm,
    bool? preferMetric,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (username != null) data['username'] = username;
      if (weightKg != null) data['weight_kg'] = weightKg;
      if (heightCm != null) data['height_cm'] = heightCm;
      if (preferMetric != null) data['preferMetric'] = preferMetric;
      
      // Only send request if there is data to update
      if (data.isEmpty) {
         final currentUser = await getCurrentUser(); // This might hit API again
         if (currentUser != null) return currentUser;
         throw ApiException('No profile data provided for update.');
      }

      final response = await _apiClient.put(
        '/users/profile', // No /api prefix needed here
        data,
      );
      
      // The response from PUT likely contains the updated profile
      final user = User.fromJson(response);
      
      // Update stored user data
      await _storageService.setObject(AppConfig.userProfileKey, user.toJson());
      
      return user;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }
  
  @override
  Future<void> deleteAccount({required String userId}) async {
    try {
      // The ApiClient should already have the token set from previous auth checks/logins.
      // The base URL is handled by ApiClient, we just need the path.
      final String endpoint = '/users/$userId'; 
      AppLogger.info("AuthService: Attempting to delete account via $endpoint");
      
      // Make the DELETE request
      await _apiClient.delete(endpoint);
      
      AppLogger.info("AuthService: Backend account deletion successful for $userId. Signing out locally.");
      
      // If the API call succeeds (doesn't throw), sign out locally
      await signOut();
      
    } on UnauthorizedException catch (e) {
      // If unauthorized, token might be invalid. Sign out anyway.
      AppLogger.warning("AuthService: Unauthorized during delete account for $userId. Signing out. Error: $e");
      await signOut();
      // Rethrow or handle as specific error for the UI/Bloc
      throw e; 
    } catch (e) {
      // Handle other potential API errors or network issues
      AppLogger.error("AuthService: Error during delete account API call for $userId: $e");
      // Rethrow the error so the Bloc/UI layer knows it failed
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