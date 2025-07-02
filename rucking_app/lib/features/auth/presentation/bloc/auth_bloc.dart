import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/services/app_lifecycle_service.dart';
import 'package:rucking_app/core/services/firebase_messaging_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// BLoC for handling authentication logic
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc(this._authRepository) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onAuthLoginRequested);
    on<AuthGoogleLoginRequested>(_onAuthGoogleLoginRequested);
    on<AuthAppleLoginRequested>(_onAuthAppleLoginRequested);
    on<AuthRegisterRequested>(_onAuthRegisterRequested);
    on<AuthGoogleRegisterRequested>(_onAuthGoogleRegisterRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
    on<AuthUpdateProfileRequested>(_onAuthUpdateProfileRequested);
    on<AuthUpdateNotificationPreferences>(_onAuthUpdateNotificationPreferences);
    on<AuthDeleteAccountRequested>(_onAuthDeleteAccountRequested);
    on<AuthPasswordResetRequested>(_onAuthPasswordResetRequested);
    on<AuthPasswordResetConfirmed>(_onAuthPasswordResetConfirmed);
  }

  /// Verify authentication status on app start
  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final isAuthenticated = await _authRepository.isAuthenticated();
      
      if (isAuthenticated) {
        try {
          final user = await _authRepository.getCurrentUser();
          if (user != null) {
            // 🔥 Set user info in Crashlytics for better crash reports
            FirebaseCrashlytics.instance.setUserIdentifier(user.userId);
            FirebaseCrashlytics.instance.setCustomKey('user_email', user.email);
            FirebaseCrashlytics.instance.setCustomKey('user_username', user.username ?? 'unknown');
            FirebaseCrashlytics.instance.log('User authenticated: ${user.email}');
            
            emit(Authenticated(user));
            _registerFirebaseTokenAfterAuth();
          } else {
            // Could not fetch user data even though token exists – treating as unauthenticated
            AppLogger.warning('[AuthBloc] Could not get user data, emitting Unauthenticated.');
            emit(Unauthenticated());
          }
        } catch (e) {
          // Error while trying to fetch current user – assume session invalid
          AppLogger.warning('[AuthBloc] Error getting current user – emitting Unauthenticated: $e');
          emit(Unauthenticated());
        }
      } else {
        emit(Unauthenticated());
      }
    } catch (e) {
      AppLogger.error('[AuthBloc] Auth check error: $e');
      // Could not verify authentication – treat as unauthenticated so user can login
      emit(Unauthenticated());
    }
  }

  /// Handle login request
  Future<void> _onAuthLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      // First, perform the login
      final loginUser = await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      
      // After successful login, fetch the full user profile
      // This ensures we have profile data like name, weight, etc.
      final fullUser = await _authRepository.getCurrentUser();
      
      if (fullUser != null) {
         emit(Authenticated(fullUser));
         _registerFirebaseTokenAfterAuth();
      } else {
         // Should not happen if login succeeded, but handle defensively
         // Maybe emit Authenticated with just loginUser? Or an error?
         // For now, emit Authenticated with potentially incomplete loginUser data
         emit(Authenticated(loginUser)); 
         _registerFirebaseTokenAfterAuth();
         emit(AuthError('Login succeeded but failed to fetch full user profile afterward.'));
      }

    } catch (e) {
      emit(AuthError('Login failed: $e'));
    }
  }

  /// Handle Google login request
  Future<void> _onAuthGoogleLoginRequested(
    AuthGoogleLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final user = await _authRepository.googleLogin();
      // 🔥 Set user info in Crashlytics after Google login
      FirebaseCrashlytics.instance.setUserIdentifier(user.userId);
      FirebaseCrashlytics.instance.setCustomKey('user_email', user.email);
      FirebaseCrashlytics.instance.setCustomKey('user_username', user.username ?? 'unknown');
      FirebaseCrashlytics.instance.log('User logged in via Google: ${user.email}');
      
      emit(Authenticated(user));
      
      // Register Firebase token after successful authentication
      _registerFirebaseTokenAfterAuth();
    } catch (e) {
      AppLogger.error('Google login failed', exception: e);
      
      // Check if user needs to complete registration
      if (e is GoogleUserNeedsRegistrationException) {
        emit(GoogleUserNeedsRegistration(
          email: e.email,
          displayName: e.displayName,
        ));
      } else {
        emit(AuthError('Google login failed: $e'));
      }
    }
  }

  /// Handle Apple login request
  Future<void> _onAuthAppleLoginRequested(
    AuthAppleLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final user = await _authRepository.appleLogin();
      // 🔥 Set user info in Crashlytics after Apple login
      FirebaseCrashlytics.instance.setUserIdentifier(user.userId);
      FirebaseCrashlytics.instance.setCustomKey('user_email', user.email);
      FirebaseCrashlytics.instance.setCustomKey('user_username', user.username ?? 'unknown');
      FirebaseCrashlytics.instance.log('User logged in via Apple: ${user.email}');
      
      emit(Authenticated(user));
      
      // Register Firebase token after successful authentication
      _registerFirebaseTokenAfterAuth();
    } catch (e) {
      AppLogger.error('Apple login failed', exception: e);
      emit(AuthError('Apple login failed: $e'));
    }
  }

  /// Handle registration request
  Future<void> _onAuthRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final user = await _authRepository.register(
        username: event.username, // This is the display name
        email: event.email,
        password: event.password,
        preferMetric: event.preferMetric,
        weightKg: event.weightKg,
        heightCm: event.heightCm,
        dateOfBirth: event.dateOfBirth,
        gender: event.gender,
      );
      
      emit(Authenticated(user));
      _registerFirebaseTokenAfterAuth();
    } catch (e) {
      if (e.toString().contains('ConflictException') || e.toString().contains('already exists')) {
        emit(AuthUserAlreadyExists('An account with this email already exists. Please sign in instead.'));
      } else {
        emit(AuthError('Registration failed: $e'));
      }
    }
  }

  /// Handle Google registration request
  Future<void> _onAuthGoogleRegisterRequested(
    AuthGoogleRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final user = await _authRepository.googleRegister(
        email: event.email,
        displayName: event.displayName ?? event.username,
        username: event.username,
        preferMetric: event.preferMetric,
        weightKg: event.weightKg,
        heightCm: event.heightCm,
        dateOfBirth: event.dateOfBirth,
        gender: event.gender,
      );
      
      emit(Authenticated(user)); 
      _registerFirebaseTokenAfterAuth();
    } catch (e) {
      emit(AuthError('Google registration failed: $e'));
    }
  }

  /// Handle logout request
  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      // Stop all background services before logout to prevent widget disposal errors
      final lifecycleService = GetIt.I<AppLifecycleService>();
      lifecycleService.stopAllServices();
      
      // Small delay to ensure all services have stopped cleanly
      await Future.delayed(const Duration(milliseconds: 100));
      
      await _authRepository.logout();
      
      // 🔥 Clear user info from Crashlytics on logout
      FirebaseCrashlytics.instance.setUserIdentifier('');
      FirebaseCrashlytics.instance.log('User logged out');
      
      emit(Unauthenticated());
    } catch (e) {
      emit(AuthError('Logout failed: $e'));
    }
  }

  /// Handle profile update request
  Future<void> _onAuthUpdateProfileRequested(
    AuthUpdateProfileRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Get current state to maintain user ID if needed
    final currentState = state;
    if (currentState is Authenticated) {
      emit(AuthLoading()); // Indicate loading state
      try {
        // Call updateProfile with the fields from the event
        final updatedUser = await _authRepository.updateProfile(
          username: event.username,
          weightKg: event.weightKg,
          heightCm: event.heightCm,
          preferMetric: event.preferMetric,
          allowRuckSharing: event.allowRuckSharing,
          gender: event.gender,
          avatarUrl: event.avatarUrl,
        );
        emit(Authenticated(updatedUser)); // Emit new state with updated user
      } catch (e) {
        emit(AuthError('Profile update failed: $e'));
        // Re-emit the previous Authenticated state on error
        // to avoid losing the user's session in the UI
        emit(currentState); 
      }
    } else {
      // Cannot update profile if not authenticated
      emit(AuthError('Cannot update profile: User not authenticated.'));
    }
  }

  /// Handle notification preferences update request
  Future<void> _onAuthUpdateNotificationPreferences(
    AuthUpdateNotificationPreferences event,
    Emitter<AuthState> emit,
  ) async {
    // Get current state to maintain user ID if needed
    final currentState = state;
    if (currentState is Authenticated) {
      emit(AuthLoading()); // Indicate loading state
      try {
        // Call updateProfile with the notification preference fields from the event
        final updatedUser = await _authRepository.updateProfile(
          notificationClubs: event.preferences['clubs'],
          notificationBuddies: event.preferences['buddies'],
          notificationEvents: event.preferences['events'],  
          notificationDuels: event.preferences['duels'],
        );
        emit(Authenticated(updatedUser)); // Emit new state with updated user
      } catch (e) {
        emit(AuthError('Notification preferences update failed: $e'));
        // Re-emit the previous Authenticated state on error
        // to avoid losing the user's session in the UI
        emit(currentState); 
      }
    } else {
      // Cannot update notification preferences if not authenticated
      emit(AuthError('Cannot update notification preferences: User not authenticated.'));
    }
  }

  /// Handle delete account request
  Future<void> _onAuthDeleteAccountRequested(
    AuthDeleteAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;
    if (currentState is Authenticated) {
      emit(AuthLoading()); // Indicate processing
      try {
        final userId = currentState.user.userId;
        AppLogger.info('AuthBloc: Deleting account for user $userId');
        await _authRepository.deleteAccount(userId: userId);
        AppLogger.info('AuthBloc: Account deleted successfully, emitting Unauthenticated.');
        emit(Unauthenticated()); // Transition to Unauthenticated on successful deletion
      } catch (e) {
        AppLogger.error('AuthBloc: Failed to delete account: $e');
        emit(AuthError('Failed to delete account: ${e.toString()}'));
        // Re-emit the Authenticated state so the user isn't logged out if deletion failed
        // The UI should handle showing the error message.
        emit(currentState); 
      }
    } else {
      // Should not happen if the delete option is only shown when authenticated
      AppLogger.warning('AuthBloc: Delete account requested while not authenticated.');
      emit(AuthError('Cannot delete account. User not authenticated.'));
      if (currentState is! Authenticated) {
           emit(Unauthenticated()); // Ensure state is Unauthenticated if it wasn't already
      }
    }
  }

  /// Handle password reset request
  Future<void> _onAuthPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      await _authRepository.requestPasswordReset(email: event.email);
      // For password reset request, we don't change auth state
      // Just show success message via UI
      emit(AuthInitial()); // Return to initial state
    } catch (e) {
      emit(AuthError('Password reset request failed: $e'));
    }
  }

  /// Handle password reset confirmation
  Future<void> _onAuthPasswordResetConfirmed(
    AuthPasswordResetConfirmed event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      await _authRepository.confirmPasswordReset(
        token: event.token,
        newPassword: event.newPassword,
        refreshToken: event.refreshToken,
      );
      
      // After successful password reset, emit success state
      emit(const PasswordResetSuccess());
    } catch (e) {
      emit(AuthError('Password reset confirmation failed: $e'));
    }
  }

  /// Register Firebase messaging token after successful authentication
  void _registerFirebaseTokenAfterAuth() {
    try {
      final firebaseMessaging = GetIt.I<FirebaseMessagingService>();
      firebaseMessaging.registerTokenAfterAuth().catchError((e) {
        AppLogger.warning('Failed to register Firebase token after auth: $e');
      });
    } catch (e) {
      AppLogger.warning('Error accessing Firebase messaging service: $e');
    }
  }
}